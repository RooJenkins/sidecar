import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { join, dirname } from "node:path";

interface CacheEntry {
  hash: string;
  mtime: number;
  size: number;
}

interface CacheData {
  version: string;
  entries: Record<string, CacheEntry>;
}

export class FileCache {
  private data: CacheData = { version: "1.0", entries: {} };
  private dirty = false;

  constructor(private cachePath: string) {}

  static forDirectory(targetDir: string): FileCache {
    return new FileCache(join(targetDir, ".sidecar", "cache.json"));
  }

  async load(): Promise<void> {
    try {
      const raw = await readFile(this.cachePath, "utf-8");
      this.data = JSON.parse(raw);
    } catch {
      this.data = { version: "1.0", entries: {} };
    }
  }

  async save(): Promise<void> {
    if (!this.dirty) return;
    await mkdir(dirname(this.cachePath), { recursive: true });
    await writeFile(this.cachePath, JSON.stringify(this.data, null, 2), "utf-8");
    this.dirty = false;
  }

  async isChanged(filePath: string): Promise<boolean> {
    const entry = this.data.entries[filePath];
    if (!entry) return true;

    // Fast path: check mtime + size first
    const fileStat = await stat(filePath);
    if (fileStat.mtimeMs === entry.mtime && fileStat.size === entry.size) {
      return false;
    }

    // Slow path: hash the file
    const hash = await hashFile(filePath);
    return hash !== entry.hash;
  }

  async update(filePath: string): Promise<void> {
    const fileStat = await stat(filePath);
    const hash = await hashFile(filePath);
    this.data.entries[filePath] = {
      hash,
      mtime: fileStat.mtimeMs,
      size: fileStat.size,
    };
    this.dirty = true;
  }

  remove(filePath: string): void {
    if (this.data.entries[filePath]) {
      delete this.data.entries[filePath];
      this.dirty = true;
    }
  }
}

function hashFile(filePath: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    const stream = createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", reject);
  });
}
