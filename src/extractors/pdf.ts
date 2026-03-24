import { readFile } from "node:fs/promises";
import type { Extractor, ExtractionResult } from "./types.js";

export const pdfExtractor: Extractor = {
  name: "pdf-parse",
  supportedMimeTypes: ["application/pdf"],

  async extract(filePath: string): Promise<ExtractionResult> {
    const pdfParse = (await import("pdf-parse")).default;
    const buffer = await readFile(filePath);
    const data = await pdfParse(buffer);

    const words = data.text.split(/\s+/).filter(Boolean);

    return {
      content: data.text,
      metadata: {
        title: data.info?.Title || undefined,
        author: data.info?.Author || undefined,
        pageCount: data.numpages,
        wordCount: words.length,
      },
    };
  },
};
