import { readdir, stat } from "node:fs/promises";
import { join, relative, basename } from "node:path";
import { getMimeType, getExtractor } from "./extractors/index.js";
import { FileCache } from "./cache.js";
import type { ExtractedFile, ScanOptions, ScanResult } from "./types.js";

const DEFAULT_EXCLUDE = [
  "node_modules",
  ".git",
  ".sidecar",
  "dist",
  "build",
  ".next",
  "__pycache__",
  ".venv",
  "venv",
  "__MACOSX",
  "Thumbs.db",
];

const DEFAULT_MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB
const DEFAULT_CONCURRENCY = 4;

interface ScanCallbacks {
  onFile?: (file: ExtractedFile) => void | Promise<void>;
  onSkip?: (filePath: string, reason: string) => void;
  onError?: (filePath: string, error: Error) => void;
}

export async function scan(
  targetPath: string,
  options: ScanOptions,
  callbacks?: ScanCallbacks
): Promise<ScanResult> {
  const excludes = options.exclude ?? DEFAULT_EXCLUDE;
  const filePaths = await collectFiles(targetPath, excludes);
  const result: ScanResult = { processed: 0, skipped: 0, errors: 0, files: [] };

  // Load cache
  const cache = FileCache.forDirectory(targetPath);
  await cache.load();

  const concurrency = options.concurrency ?? DEFAULT_CONCURRENCY;

  // Process files with concurrency pool
  const pending: Promise<void>[] = [];

  for (const filePath of filePaths) {
    const task = (async () => {
      try {
        const extracted = await processFile(filePath, targetPath, options, cache, callbacks);
        if (extracted) {
          result.files.push(extracted);
          result.processed++;
          await callbacks?.onFile?.(extracted);
          await cache.update(filePath);
        } else {
          result.skipped++;
        }
      } catch (err) {
        result.errors++;
        callbacks?.onError?.(filePath, err instanceof Error ? err : new Error(String(err)));
      }
    })();

    pending.push(task);

    // Limit concurrency
    if (pending.length >= concurrency) {
      await Promise.race(pending);
      // Remove settled promises
      for (let i = pending.length - 1; i >= 0; i--) {
        const settled = await Promise.race([
          pending[i].then(() => true),
          Promise.resolve(false),
        ]);
        if (settled) pending.splice(i, 1);
      }
    }
  }

  // Wait for remaining
  await Promise.all(pending);

  // Save cache
  await cache.save();

  return result;
}

export async function scanSingleFile(
  filePath: string,
  rootPath: string,
  options: ScanOptions,
  callbacks?: ScanCallbacks
): Promise<ExtractedFile | null> {
  const cache = FileCache.forDirectory(rootPath);
  await cache.load();

  try {
    const extracted = await processFile(filePath, rootPath, options, cache, callbacks);
    if (extracted) {
      await callbacks?.onFile?.(extracted);
      await cache.update(filePath);
      await cache.save();
    }
    return extracted;
  } catch (err) {
    callbacks?.onError?.(filePath, err instanceof Error ? err : new Error(String(err)));
    return null;
  }
}

async function collectFiles(
  dirPath: string,
  excludes: string[]
): Promise<string[]> {
  const files: string[] = [];

  let entries;
  try {
    entries = await readdir(dirPath, { withFileTypes: true });
  } catch {
    return files;
  }

  for (const entry of entries) {
    const name = entry.name;

    // Skip hidden files/dirs
    if (name.startsWith(".")) continue;

    // Skip excluded directories/files
    if (excludes.some((pattern) => name === pattern)) continue;

    // Skip sidecar files and index files
    if (name.endsWith(".sidecar.md")) continue;
    if (name === "SIDECAR.md") continue;

    // Skip Office temp/lock files
    if (name.startsWith("~$")) continue;

    const fullPath = join(dirPath, name);

    if (entry.isDirectory()) {
      const nested = await collectFiles(fullPath, excludes);
      files.push(...nested);
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }

  return files;
}

async function processFile(
  filePath: string,
  rootPath: string,
  options: ScanOptions,
  cache: FileCache,
  callbacks?: ScanCallbacks
): Promise<ExtractedFile | null> {
  const maxSize = options.maxFileSize ?? DEFAULT_MAX_FILE_SIZE;
  const fileStat = await stat(filePath);

  if (fileStat.size > maxSize) {
    callbacks?.onSkip?.(filePath, `exceeds max file size (${formatBytes(fileStat.size)})`);
    return null;
  }

  const mimeType = getMimeType(filePath);
  const extractor = getExtractor(mimeType);

  if (!extractor) {
    callbacks?.onSkip?.(filePath, `no extractor for ${mimeType}`);
    return null;
  }

  // Include filter check
  if (options.include?.length) {
    const relPath = relative(rootPath, filePath);
    const matchesInclude = options.include.some((pattern) => {
      if (pattern.startsWith("*.")) {
        const ext = pattern.slice(1);
        return relPath.endsWith(ext);
      }
      if (pattern.startsWith("**/*.")) {
        const ext = pattern.slice(4);
        return relPath.endsWith(ext);
      }
      return relPath.includes(pattern);
    });
    if (!matchesInclude) {
      callbacks?.onSkip?.(filePath, "does not match include filter");
      return null;
    }
  }

  // Cache check — skip unchanged files
  const changed = await cache.isChanged(filePath);
  if (!changed) {
    callbacks?.onSkip?.(filePath, "unchanged (cached)");
    return null;
  }

  const { content, metadata } = await extractor.extract(filePath);

  return {
    sourcePath: filePath,
    fileName: basename(filePath),
    mimeType,
    fileSizeBytes: fileStat.size,
    createdAt: fileStat.birthtime,
    modifiedAt: fileStat.mtime,
    processedAt: new Date(),
    extractor: extractor.name,
    content,
    metadata,
  };
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
