import { readFile } from "node:fs/promises";
import type { Extractor, ExtractionResult } from "./types.js";

const TEXT_MIME_TYPES = [
  "text/plain",
  "text/markdown",
  "text/csv",
  "text/html",
  "text/xml",
  "text/css",
  "text/javascript",
  "application/json",
  "application/xml",
  "application/javascript",
  "application/typescript",
];

export const textExtractor: Extractor = {
  name: "text",
  supportedMimeTypes: TEXT_MIME_TYPES,

  async extract(filePath: string): Promise<ExtractionResult> {
    const content = await readFile(filePath, "utf-8");
    const lines = content.split("\n");
    const words = content.split(/\s+/).filter(Boolean);

    return {
      content,
      metadata: {
        wordCount: words.length,
        lineCount: lines.length,
      },
    };
  },
};
