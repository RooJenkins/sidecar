import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { FileCache } from "../cache.js";
import { join } from "node:path";
import { writeFile, mkdir, rm } from "node:fs/promises";

const TEMP = join(import.meta.dirname, "temp-cache");
const TEST_FILE = join(TEMP, "test.txt");

describe("FileCache", () => {
  beforeEach(async () => {
    await mkdir(TEMP, { recursive: true });
    await writeFile(TEST_FILE, "hello world");
  });

  afterEach(async () => {
    await rm(TEMP, { recursive: true, force: true });
  });

  it("reports new files as changed", async () => {
    const cache = FileCache.forDirectory(TEMP);
    await cache.load();
    expect(await cache.isChanged(TEST_FILE)).toBe(true);
  });

  it("reports unchanged files after update", async () => {
    const cache = FileCache.forDirectory(TEMP);
    await cache.load();
    await cache.update(TEST_FILE);
    await cache.save();

    // Reload and check
    const cache2 = FileCache.forDirectory(TEMP);
    await cache2.load();
    expect(await cache2.isChanged(TEST_FILE)).toBe(false);
  });

  it("detects changes after file modification", async () => {
    const cache = FileCache.forDirectory(TEMP);
    await cache.load();
    await cache.update(TEST_FILE);
    await cache.save();

    // Modify file
    await writeFile(TEST_FILE, "modified content");

    const cache2 = FileCache.forDirectory(TEMP);
    await cache2.load();
    expect(await cache2.isChanged(TEST_FILE)).toBe(true);
  });

  it("saves and loads from disk", async () => {
    const cache = FileCache.forDirectory(TEMP);
    await cache.load();
    await cache.update(TEST_FILE);
    await cache.save();

    // New instance should load persisted data
    const cache2 = FileCache.forDirectory(TEMP);
    await cache2.load();
    expect(await cache2.isChanged(TEST_FILE)).toBe(false);
  });
});
