export interface ScanEvent {
  event: "file" | "skip" | "error" | "summary" | "done";
  fileName?: string;
  sourcePath?: string;
  extractor?: string;
  mimeType?: string;
  status?: string;
  reason?: string;
  message?: string;
  processed?: number;
  skipped?: number;
  errors?: number;
  elapsed_seconds?: number;
}

export interface StatusResult {
  totalFiles: number;
  trackedFiles: number;
  staleFiles: number;
  missingFiles: number;
  sidecarDiskBytes: number;
  cacheDiskBytes: number;
  byExtractor: Record<string, number>;
}

export interface SidecarConfig {
  include?: string[];
  exclude?: string[];
  maxFileSize?: string;
  summarize?: boolean;
  provider?: string;
  model?: string;
  apiUrl?: string;
  concurrency?: number;
  tikaUrl?: string;
}

export interface FileEntry {
  fileName: string;
  sourcePath: string;
  extractor: string;
  mimeType: string;
  status: "processed" | "skipped" | "error";
  reason?: string;
  message?: string;
}

export type ScanPhase = "idle" | "scanning" | "complete";

export interface SearchResult {
  file: string;
  sidecar: string;
  score: number;
  title: string;
  summary: string;
  topics: string[];
  snippet: string;
}

export interface SearchOutput {
  query: string;
  results: SearchResult[];
}

export interface IndexResult {
  documentCount: number;
  indexPath: string;
  builtAt: string;
}
