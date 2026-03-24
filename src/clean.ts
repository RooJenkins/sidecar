import { readdir, unlink, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { INDEX_FILENAME } from "./indexer.js";

export interface CleanResult {
  sidecarFiles: number;
  indexFiles: number;
  cacheRemoved: boolean;
  bytesFreed: number;
}

export async function cleanSidecars(targetPath: string, outputDir?: string): Promise<CleanResult> {
  const result: CleanResult = {
    sidecarFiles: 0,
    indexFiles: 0,
    cacheRemoved: false,
    bytesFreed: 0,
  };

  // Walk outputDir for sidecars when set, otherwise walk targetPath
  await walkAndClean(outputDir ?? targetPath, result);

  // Remove .sidecar cache directory (always from targetPath)
  try {
    const cacheDir = join(targetPath, ".sidecar");
    const cacheStat = await stat(cacheDir);
    if (cacheStat.isDirectory()) {
      result.bytesFreed += cacheStat.size;
      await rm(cacheDir, { recursive: true });
      result.cacheRemoved = true;
    }
  } catch {
    // no cache dir
  }

  return result;
}

async function walkAndClean(
  dirPath: string,
  result: CleanResult
): Promise<void> {
  const excludes = ["node_modules", ".git", ".sidecar", "dist", "build", ".next"];

  let entries;
  try {
    entries = await readdir(dirPath, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (entry.name.startsWith(".") && excludes.includes(entry.name)) continue;

    const fullPath = join(dirPath, entry.name);

    if (entry.isDirectory()) {
      if (!excludes.includes(entry.name)) {
        await walkAndClean(fullPath, result);
      }
    } else if (entry.name.endsWith(".sidecar.md")) {
      try {
        const fileStat = await stat(fullPath);
        result.bytesFreed += fileStat.size;
        await unlink(fullPath);
        result.sidecarFiles++;
      } catch {
        // skip
      }
    } else if (entry.name === INDEX_FILENAME) {
      try {
        const fileStat = await stat(fullPath);
        result.bytesFreed += fileStat.size;
        await unlink(fullPath);
        result.indexFiles++;
      } catch {
        // skip
      }
    }
  }
}
