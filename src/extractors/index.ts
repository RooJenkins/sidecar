import { extname } from "node:path";
import type { Extractor } from "./types.js";
import { textExtractor } from "./text.js";
import { pdfExtractor } from "./pdf.js";
import { docxExtractor } from "./docx.js";
import { xlsxExtractor } from "./xlsx.js";

const extractors: Extractor[] = [
  pdfExtractor,
  docxExtractor,
  xlsxExtractor,
  textExtractor,
];

let tikaExtractor: Extractor | null = null;

export function setTikaExtractor(extractor: Extractor): void {
  tikaExtractor = extractor;
}

const EXT_TO_MIME: Record<string, string> = {
  // PDF
  ".pdf": "application/pdf",
  // Word
  ".docx":
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ".doc": "application/msword",
  // Excel
  ".xlsx":
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ".xls": "application/vnd.ms-excel",
  // Text
  ".txt": "text/plain",
  ".md": "text/markdown",
  ".markdown": "text/markdown",
  ".csv": "text/csv",
  ".html": "text/html",
  ".htm": "text/html",
  ".xml": "text/xml",
  ".css": "text/css",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".ts": "application/typescript",
  ".tsx": "application/typescript",
  ".jsx": "text/javascript",
  ".json": "application/json",
  ".yaml": "text/plain",
  ".yml": "text/plain",
  ".toml": "text/plain",
  ".ini": "text/plain",
  ".cfg": "text/plain",
  ".conf": "text/plain",
  ".env": "text/plain",
  ".sh": "text/plain",
  ".bash": "text/plain",
  ".zsh": "text/plain",
  ".py": "text/plain",
  ".rb": "text/plain",
  ".go": "text/plain",
  ".rs": "text/plain",
  ".java": "text/plain",
  ".c": "text/plain",
  ".cpp": "text/plain",
  ".h": "text/plain",
  ".hpp": "text/plain",
  ".swift": "text/plain",
  ".kt": "text/plain",
  ".scala": "text/plain",
  ".r": "text/plain",
  ".sql": "text/plain",
  ".graphql": "text/plain",
  ".proto": "text/plain",
  ".log": "text/plain",
  ".svg": "text/xml",
};

export function getMimeType(filePath: string): string {
  const ext = extname(filePath).toLowerCase();
  return EXT_TO_MIME[ext] ?? "application/octet-stream";
}

export function getExtractor(mimeType: string): Extractor | undefined {
  // Try JS-native extractors first
  const native = extractors.find((e) => e.supportedMimeTypes.includes(mimeType));
  if (native) return native;

  // Fall back to Tika if available (handles any MIME type)
  if (tikaExtractor) return tikaExtractor;

  return undefined;
}

export { type Extractor, type ExtractionResult } from "./types.js";
