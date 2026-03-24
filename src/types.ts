export interface ExtractedFile {
  sourcePath: string;
  fileName: string;
  mimeType: string;
  fileSizeBytes: number;
  createdAt: Date;
  modifiedAt: Date;
  processedAt: Date;
  extractor: string;
  content: string;
  metadata: FileMetadata;
}

export interface FileMetadata {
  title?: string;
  author?: string;
  language?: string;
  pageCount?: number;
  wordCount?: number;
  sheetNames?: string[];
  rowCount?: number;
  [key: string]: unknown;
}

export interface SidecarMetadata {
  sidecar_version: string;
  source_file: string;
  source_path: string;
  mime_type: string;
  file_size_bytes: number;
  file_hash_sha256?: string;
  created_at: string;
  modified_at: string;
  processed_at: string;
  extractor: string;
  author?: string;
  title?: string;
  language?: string;
  word_count?: number;
  has_ai_summary: boolean;
}

export interface ScanOptions {
  include?: string[];
  exclude?: string[];
  maxFileSize?: number;
  outputDir?: string;
  tikaUrl?: string;
  noTika?: boolean;
  summarize?: boolean;
  provider?: string;
  model?: string;
  apiUrl?: string;
  watch?: boolean;
  dryRun?: boolean;
  concurrency?: number;
  verbose?: boolean;
  json?: boolean;
}

export interface ScanResult {
  processed: number;
  skipped: number;
  errors: number;
  files: ExtractedFile[];
}
