import { readdir, stat } from "node:fs/promises";
import { join, relative } from "node:path";
import { generateSidecarPath } from "./markdown.js";
import { getMimeType, getExtractor } from "./extractors/index.js";
import { FileCache } from "./cache.js";

export interface StatusResult {
  totalFiles: number;
  trackedFiles: number;
  staleFiles: number;
  missingFiles: number;
  sidecarDiskBytes: number;
  cacheDiskBytes: number;
  byExtractor: Record<string, number>;
}

export async function getStatus(targetPath: string, outputDir?: string): Promise<StatusResult> {
  const sourceFiles = await collectSourceFiles(targetPath);
  const cache = FileCache.forDirectory(targetPath);
  await cache.load();

  let trackedFiles = 0;
  let staleFiles = 0;
  let missingFiles = 0;
  let sidecarDiskBytes = 0;
  const byExtractor: Record<string, number> = {};

  for (const filePath of sourceFiles) {
    const mimeType = getMimeType(filePath);
    const extractor = getExtractor(mimeType);
    if (!extractor) continue;

    const extractorName = extractor.name;
    byExtractor[extractorName] = (byExtractor[extractorName] ?? 0) + 1;

    const sidecarPath = generateSidecarPath(filePath, targetPath, outputDir);
    try {
      const sidecarStat = await stat(sidecarPath);
      trackedFiles++;
      sidecarDiskBytes += sidecarStat.size;

      const changed = await cache.isChanged(filePath);
      if (changed) staleFiles++;
    } catch {
      missingFiles++;
    }
  }

  let cacheDiskBytes = 0;
  try {
    const cacheStat = await stat(join(targetPath, ".sidecar", "cache.json"));
    cacheDiskBytes = cacheStat.size;
  } catch {
    // no cache file
  }

  return {
    totalFiles: sourceFiles.length,
    trackedFiles,
    staleFiles,
    missingFiles,
    sidecarDiskBytes,
    cacheDiskBytes,
    byExtractor,
  };
}

async function collectSourceFiles(dirPath: string): Promise<string[]> {
  const files: string[] = [];
  const excludes = ["node_modules", ".git", ".sidecar", "dist", "build", ".next"];

  let entries;
  try {
    entries = await readdir(dirPath, { withFileTypes: true });
  } catch {
    return files;
  }

  for (const entry of entries) {
    const name = entry.name;
    if (name.startsWith(".")) continue;
    if (excludes.includes(name)) continue;
    if (name.endsWith(".sidecar.md")) continue;

    const fullPath = join(dirPath, name);

    if (entry.isDirectory()) {
      const nested = await collectSourceFiles(fullPath);
      files.push(...nested);
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }

  return files;
}
