import { readFile } from "node:fs/promises";
import type { Extractor, ExtractionResult } from "./types.js";

const XLSX_MIME_TYPES = [
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-excel",
];

export const xlsxExtractor: Extractor = {
  name: "sheetjs",
  supportedMimeTypes: XLSX_MIME_TYPES,

  async extract(filePath: string): Promise<ExtractionResult> {
    const XLSX = await import("xlsx");
    const buffer = await readFile(filePath);
    const workbook = XLSX.read(buffer, { type: "buffer" });

    const sheets: string[] = [];
    let totalRows = 0;

    for (const sheetName of workbook.SheetNames) {
      const sheet = workbook.Sheets[sheetName];
      if (!sheet) continue;
      const csv = XLSX.utils.sheet_to_csv(sheet);
      const rows = csv.split("\n").filter(Boolean);
      totalRows += rows.length;
      sheets.push(`## Sheet: ${sheetName}\n\n${csv}`);
    }

    const content = sheets.join("\n\n");
    const words = content.split(/\s+/).filter(Boolean);

    return {
      content,
      metadata: {
        sheetNames: workbook.SheetNames,
        rowCount: totalRows,
        wordCount: words.length,
      },
    };
  },
};
