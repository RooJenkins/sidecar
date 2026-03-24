import { describe, it, expect } from "vitest";
import { buildSidecarMarkdown, generateSidecarPath } from "../markdown.js";
import type { ExtractedFile } from "../types.js";

const mockFile: ExtractedFile = {
  sourcePath: "/tmp/test/report.pdf",
  fileName: "report.pdf",
  mimeType: "application/pdf",
  fileSizeBytes: 1024,
  createdAt: new Date("2026-01-01"),
  modifiedAt: new Date("2026-01-15"),
  processedAt: new Date("2026-01-20"),
  extractor: "pdf-parse",
  content: "This is the extracted text content.",
  metadata: {
    author: "Jane Smith",
    title: "Test Report",
    pageCount: 5,
    wordCount: 100,
  },
};

describe("generateSidecarPath", () => {
  it("appends .sidecar.md to source path", () => {
    expect(generateSidecarPath("/tmp/report.pdf")).toBe("/tmp/report.pdf.sidecar.md");
  });

  it("generates mirrored path with outputDir", () => {
    const result = generateSidecarPath("/tmp/docs/report.pdf", "/tmp/docs", "/tmp/mirror");
    expect(result).toBe("/tmp/mirror/report.pdf.sidecar.md");
  });
});

describe("buildSidecarMarkdown", () => {
  it("includes YAML frontmatter", () => {
    const md = buildSidecarMarkdown(mockFile);
    expect(md).toMatch(/^---\n/);
    expect(md).toContain('sidecar_version: "1.0"');
    expect(md).toContain("source_file: report.pdf");
    expect(md).toContain("extractor: pdf-parse");
    expect(md).toContain("has_ai_summary: false");
  });

  it("includes metadata section", () => {
    const md = buildSidecarMarkdown(mockFile);
    expect(md).toContain("## Metadata");
    expect(md).toContain("**Author**: Jane Smith");
    expect(md).toContain("**Pages**: 5");
    expect(md).toContain("**Words**: 100");
  });

  it("includes content extract", () => {
    const md = buildSidecarMarkdown(mockFile);
    expect(md).toContain("## Content Extract");
    expect(md).toContain("This is the extracted text content.");
  });

  it("includes AI summary when provided", () => {
    const summary = {
      purpose: "A test report",
      keyPoints: ["Point 1", "Point 2"],
      entities: ["Jane Smith"],
      topics: ["testing"],
      relevance: "QA team",
    };
    const md = buildSidecarMarkdown(mockFile, summary);
    expect(md).toContain("## AI Summary");
    expect(md).toContain("**Purpose**: A test report");
    expect(md).toContain("- Point 1");
    expect(md).toContain("has_ai_summary: true");
  });

  it("omits AI summary when not provided", () => {
    const md = buildSidecarMarkdown(mockFile);
    expect(md).not.toContain("## AI Summary");
  });
});
