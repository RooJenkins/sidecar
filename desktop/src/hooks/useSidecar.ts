import { invoke } from "@tauri-apps/api/core";
import type { StatusResult, SidecarConfig, ScanEvent, SearchOutput, IndexResult } from "../lib/types";

export async function scanFolder(
  path: string,
  options: Partial<SidecarConfig> = {},
  onEvent: (event: ScanEvent) => void
): Promise<void> {
  const args = ["scan", path, "--json-stream"];

  if (options.include) {
    args.push("--include", ...options.include);
  }
  if (options.exclude) {
    args.push("--exclude", ...options.exclude);
  }
  if (options.summarize) {
    args.push("--summarize");
  }
  if (options.provider) {
    args.push("--provider", options.provider);
  }
  if (options.model) {
    args.push("--model", options.model);
  }
  if (options.concurrency) {
    args.push("--concurrency", String(options.concurrency));
  }

  const stdout = await invoke<string>("run_sidecar", { args });

  const lines = stdout.split("\n");
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const event = JSON.parse(line) as ScanEvent;
      onEvent(event);
    } catch {
      // ignore non-JSON lines
    }
  }
}

export async function getStatus(path: string): Promise<StatusResult> {
  const stdout = await invoke<string>("run_sidecar", {
    args: ["status", path, "--json"],
  });
  return JSON.parse(stdout);
}

export interface CleanResult {
  sidecarFiles: number;
  indexFiles: number;
  cacheRemoved: boolean;
  bytesFreed: number;
}

export async function cleanFolder(path: string): Promise<CleanResult> {
  const stdout = await invoke<string>("run_sidecar", {
    args: ["clean", path, "--json"],
  });
  return JSON.parse(stdout);
}

export async function readSidecarFile(sourcePath: string): Promise<string> {
  const { readTextFile } = await import("@tauri-apps/plugin-fs");
  return readTextFile(`${sourcePath}.sidecar.md`);
}

export async function loadConfig(dir: string): Promise<SidecarConfig> {
  try {
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const raw = await readTextFile(`${dir}/.sidecarrc`);
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

export async function saveConfig(dir: string, config: SidecarConfig): Promise<void> {
  const { writeTextFile } = await import("@tauri-apps/plugin-fs");
  await writeTextFile(`${dir}/.sidecarrc`, JSON.stringify(config, null, 2));
}

export async function buildIndex(paths: string[]): Promise<IndexResult> {
  const args = ["index", ...paths, "--json"];
  const stdout = await invoke<string>("run_sidecar", { args });
  return JSON.parse(stdout);
}

export async function searchDocuments(query: string, topN = 5): Promise<SearchOutput> {
  const args = ["search", query, "--json", "--top", String(topN)];
  const stdout = await invoke<string>("run_sidecar", { args });
  return JSON.parse(stdout);
}
