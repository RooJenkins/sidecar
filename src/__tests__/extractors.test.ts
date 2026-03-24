import { describe, it, expect } from "vitest";
import { textExtractor } from "../extractors/text.js";
import { getMimeType, getExtractor } from "../extractors/index.js";
import { join } from "node:path";

const FIXTURES = join(import.meta.dirname, "fixtures");

describe("text extractor", () => {
  it("extracts plain text content", async () => {
    const result = await textExtractor.extract(join(FIXTURES, "sample.txt"));
    expect(result.content).toContain("test document");
    expect(result.metadata.wordCount).toBeGreaterThan(0);
  });

  it("extracts markdown content", async () => {
    const result = await textExtractor.extract(join(FIXTURES, "sample.md"));
    expect(result.content).toContain("Test Markdown");
  });

  it("extracts JSON content", async () => {
    const result = await textExtractor.extract(join(FIXTURES, "sample.json"));
    expect(result.content).toContain('"name"');
  });
});

describe("MIME type detection", () => {
  it("detects PDF", () => {
    expect(getMimeType("report.pdf")).toBe("application/pdf");
  });

  it("detects DOCX", () => {
    expect(getMimeType("doc.docx")).toBe(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    );
  });

  it("detects XLSX", () => {
    expect(getMimeType("sheet.xlsx")).toBe(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
  });

  it("detects plain text", () => {
    expect(getMimeType("file.txt")).toBe("text/plain");
  });

  it("detects markdown", () => {
    expect(getMimeType("notes.md")).toBe("text/markdown");
  });

  it("returns octet-stream for unknown", () => {
    expect(getMimeType("file.xyz")).toBe("application/octet-stream");
  });
});

describe("extractor routing", () => {
  it("finds text extractor for plain text", () => {
    const ext = getExtractor("text/plain");
    expect(ext).toBeDefined();
    expect(ext!.name).toBe("text");
  });

  it("finds pdf extractor", () => {
    const ext = getExtractor("application/pdf");
    expect(ext).toBeDefined();
    expect(ext!.name).toBe("pdf-parse");
  });

  it("returns undefined for unknown MIME", () => {
    const ext = getExtractor("application/octet-stream");
    expect(ext).toBeUndefined();
  });
});
