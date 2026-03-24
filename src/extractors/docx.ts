import { readFile } from "node:fs/promises";
import type { Extractor, ExtractionResult } from "./types.js";

export const docxExtractor: Extractor = {
  name: "mammoth",
  supportedMimeTypes: [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ],

  async extract(filePath: string): Promise<ExtractionResult> {
    const mammoth = await import("mammoth");
    const buffer = await readFile(filePath);
    const result = await mammoth.extractRawText({ buffer });
    const text = result.value;
    const words = text.split(/\s+/).filter(Boolean);

    return {
      content: text,
      metadata: {
        wordCount: words.length,
      },
    };
  },
};
