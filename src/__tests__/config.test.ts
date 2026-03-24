import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { loadConfig, mergeConfigWithOptions } from "../config.js";
import { join } from "node:path";
import { writeFile, mkdir, rm } from "node:fs/promises";

const TEMP = join(import.meta.dirname, "temp-config");

describe("config", () => {
  beforeEach(async () => {
    await mkdir(TEMP, { recursive: true });
  });

  afterEach(async () => {
    await rm(TEMP, { recursive: true, force: true });
  });

  it("returns empty config when no .sidecarrc", async () => {
    const config = await loadConfig(TEMP);
    expect(config).toEqual({});
  });

  it("loads .sidecarrc JSON", async () => {
    await writeFile(
      join(TEMP, ".sidecarrc"),
      JSON.stringify({ summarize: true, provider: "ollama", concurrency: 8 })
    );
    const config = await loadConfig(TEMP);
    expect(config.summarize).toBe(true);
    expect(config.provider).toBe("ollama");
    expect(config.concurrency).toBe(8);
  });

  it("CLI options override config", () => {
    const config = { provider: "ollama", concurrency: 8 };
    const cliOptions = { provider: "claude", concurrency: undefined };
    const merged = mergeConfigWithOptions(config, cliOptions as never);
    expect(merged.provider).toBe("claude");
    expect(merged.concurrency).toBe(8);
  });
});
