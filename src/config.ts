import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ScanOptions } from "./types.js";

interface SidecarConfig {
  include?: string[];
  exclude?: string[];
  maxFileSize?: string;
  outputDir?: string;
  summarize?: boolean;
  provider?: string;
  model?: string;
  apiUrl?: string;
  concurrency?: number;
  tikaUrl?: string;
}

export async function loadConfig(dir: string): Promise<SidecarConfig> {
  const configPath = join(dir, ".sidecarrc");
  try {
    const raw = await readFile(configPath, "utf-8");
    return JSON.parse(raw) as SidecarConfig;
  } catch {
    return {};
  }
}

export function mergeConfigWithOptions(
  config: SidecarConfig,
  cliOptions: ScanOptions
): ScanOptions {
  // CLI flags override config values
  return {
    include: cliOptions.include ?? config.include,
    exclude: cliOptions.exclude ?? config.exclude,
    maxFileSize: cliOptions.maxFileSize ?? parseFileSize(config.maxFileSize),
    outputDir: cliOptions.outputDir ?? config.outputDir,
    tikaUrl: cliOptions.tikaUrl ?? config.tikaUrl,
    noTika: cliOptions.noTika,
    summarize: cliOptions.summarize ?? config.summarize,
    provider: cliOptions.provider ?? config.provider,
    model: cliOptions.model ?? config.model,
    apiUrl: cliOptions.apiUrl ?? config.apiUrl,
    watch: cliOptions.watch,
    dryRun: cliOptions.dryRun,
    concurrency: cliOptions.concurrency ?? config.concurrency,
    verbose: cliOptions.verbose,
    json: cliOptions.json,
  };
}

function parseFileSize(size: string | undefined): number | undefined {
  if (!size) return undefined;
  const match = size.match(/^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb)$/i);
  if (!match) return undefined;
  const value = parseFloat(match[1]);
  const unit = match[2].toLowerCase();
  const multipliers: Record<string, number> = {
    b: 1,
    kb: 1024,
    mb: 1024 * 1024,
    gb: 1024 * 1024 * 1024,
  };
  return value * (multipliers[unit] ?? 1);
}
