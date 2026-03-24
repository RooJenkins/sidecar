import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { cleanSidecars } from "../clean.js";
import { join } from "node:path";
import { writeFile, mkdir, rm, access } from "node:fs/promises";

const TEMP = join(import.meta.dirname, "temp-clean");

describe("clean", () => {
  beforeEach(async () => {
    await mkdir(TEMP, { recursive: true });
    await mkdir(join(TEMP, "sub"), { recursive: true });
    await mkdir(join(TEMP, ".sidecar"), { recursive: true });

    // Create source files
    await writeFile(join(TEMP, "a.txt"), "hello");
    await writeFile(join(TEMP, "sub", "b.txt"), "world");

    // Create sidecar files
    await writeFile(join(TEMP, "a.txt.sidecar.md"), "sidecar content");
    await writeFile(join(TEMP, "sub", "b.txt.sidecar.md"), "sidecar content");

    // Create index files
    await writeFile(join(TEMP, "SIDECAR.md"), "index");
    await writeFile(join(TEMP, "sub", "SIDECAR.md"), "index");

    // Create cache
    await writeFile(join(TEMP, ".sidecar", "cache.json"), "{}");
  });

  afterEach(async () => {
    await rm(TEMP, { recursive: true, force: true });
  });

  it("removes sidecar files", async () => {
    const result = await cleanSidecars(TEMP);
    expect(result.sidecarFiles).toBe(2);

    await expect(access(join(TEMP, "a.txt.sidecar.md"))).rejects.toThrow();
    await expect(access(join(TEMP, "sub", "b.txt.sidecar.md"))).rejects.toThrow();
  });

  it("removes index files", async () => {
    const result = await cleanSidecars(TEMP);
    expect(result.indexFiles).toBe(2);

    await expect(access(join(TEMP, "SIDECAR.md"))).rejects.toThrow();
  });

  it("removes cache directory", async () => {
    const result = await cleanSidecars(TEMP);
    expect(result.cacheRemoved).toBe(true);

    await expect(access(join(TEMP, ".sidecar"))).rejects.toThrow();
  });

  it("preserves source files", async () => {
    await cleanSidecars(TEMP);
    await expect(access(join(TEMP, "a.txt"))).resolves.toBeUndefined();
    await expect(access(join(TEMP, "sub", "b.txt"))).resolves.toBeUndefined();
  });

  it("reports bytes freed", async () => {
    const result = await cleanSidecars(TEMP);
    expect(result.bytesFreed).toBeGreaterThan(0);
  });
});
