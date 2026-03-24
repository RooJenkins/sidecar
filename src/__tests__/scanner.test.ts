import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { scan } from "../scanner.js";
import { join } from "node:path";
import { writeFile, mkdir, rm } from "node:fs/promises";

const FIXTURES = join(import.meta.dirname, "fixtures");
const TEMP = join(import.meta.dirname, "temp-scanner");

describe("scanner", () => {
  beforeEach(async () => {
    await mkdir(TEMP, { recursive: true });
    await mkdir(join(TEMP, "sub"), { recursive: true });
    await writeFile(join(TEMP, "a.txt"), "hello world");
    await writeFile(join(TEMP, "b.md"), "# heading");
    await writeFile(join(TEMP, "sub", "c.txt"), "nested");
    await writeFile(join(TEMP, "~$lockfile.docx"), "temp");
    await writeFile(join(TEMP, "existing.txt.sidecar.md"), "---\n---");
    await writeFile(join(TEMP, "SIDECAR.md"), "index");
  });

  afterEach(async () => {
    await rm(TEMP, { recursive: true, force: true });
  });

  it("scans text files recursively", async () => {
    const result = await scan(TEMP, {});
    const fileNames = result.files.map((f) => f.fileName).sort();
    expect(fileNames).toContain("a.txt");
    expect(fileNames).toContain("b.md");
    expect(fileNames).toContain("c.txt");
  });

  it("skips ~$ temp files", async () => {
    const result = await scan(TEMP, {});
    const fileNames = result.files.map((f) => f.fileName);
    expect(fileNames).not.toContain("~$lockfile.docx");
  });

  it("skips .sidecar.md files", async () => {
    const result = await scan(TEMP, {});
    const fileNames = result.files.map((f) => f.fileName);
    expect(fileNames).not.toContain("existing.txt.sidecar.md");
  });

  it("skips SIDECAR.md index files", async () => {
    const result = await scan(TEMP, {});
    const fileNames = result.files.map((f) => f.fileName);
    expect(fileNames).not.toContain("SIDECAR.md");
  });

  it("respects include filter", async () => {
    const result = await scan(TEMP, { include: ["*.md"] });
    expect(result.files.length).toBe(1);
    expect(result.files[0].fileName).toBe("b.md");
  });

  it("respects max file size", async () => {
    const result = await scan(TEMP, { maxFileSize: 5 });
    // All test files are > 5 bytes so all should be skipped
    expect(result.processed).toBe(0);
    expect(result.skipped).toBeGreaterThan(0);
  });

  it("returns correct counts", async () => {
    const result = await scan(TEMP, {});
    expect(result.processed).toBe(3);
    expect(result.errors).toBe(0);
  });
});
