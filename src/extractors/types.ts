import type { FileMetadata } from "../types.js";

export interface ExtractionResult {
  content: string;
  metadata: FileMetadata;
}

export interface Extractor {
  name: string;
  supportedMimeTypes: string[];
  extract(filePath: string): Promise<ExtractionResult>;
}
