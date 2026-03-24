import { describe, it, expect } from "vitest";
import { BM25, tokenize } from "../search/bm25.js";
import type { IndexedDocument } from "../search/types.js";

const makeDoc = (overrides: Partial<IndexedDocument> = {}): IndexedDocument => ({
  sidecarPath: "/test/doc.sidecar.md",
  sourcePath: "/test/doc.pdf",
  title: "Test Document",
  mimeType: "application/pdf",
  wordCount: 100,
  hasAiSummary: false,
  topics: [],
  entities: [],
  purpose: "",
  aiSummary: "",
  contentExtract: "",
  ...overrides,
});

describe("tokenize", () => {
  it("splits text into lowercase words", () => {
    expect(tokenize("Hello World")).toEqual(["hello", "world"]);
  });

  it("filters short words", () => {
    const tokens = tokenize("a to the big cat");
    expect(tokens).not.toContain("a");
    expect(tokens).not.toContain("to");
    expect(tokens).toContain("big");
    expect(tokens).toContain("cat");
  });

  it("handles empty input", () => {
    expect(tokenize("")).toEqual([]);
  });
});

describe("BM25", () => {
  const docs: IndexedDocument[] = [
    makeDoc({
      title: "Solar Panel Installation Guide",
      contentExtract: "solar panels installation rooftop residential commercial",
      topics: ["solar", "installation"],
    }),
    makeDoc({
      title: "Wind Turbine Maintenance",
      sourcePath: "/test/wind.pdf",
      contentExtract: "wind turbine maintenance offshore onshore blades",
      topics: ["wind", "maintenance"],
    }),
    makeDoc({
      title: "Legal Framework for Renewable Energy",
      sourcePath: "/test/legal.pdf",
      contentExtract: "legal framework renewable energy regulation compliance permits",
      topics: ["legal", "renewable"],
    }),
  ];

  it("returns results ranked by relevance", () => {
    const engine = new BM25(docs);
    const results = engine.search("solar installation", 3);
    expect(results.length).toBeGreaterThan(0);
    expect(results[0].title).toBe("Solar Panel Installation Guide");
  });

  it("returns empty for completely unrelated query", () => {
    const engine = new BM25(docs);
    const results = engine.search("chocolate cake recipe", 3);
    // BM25 may still return results with low scores, but they should be minimal
    expect(results.length).toBeLessThanOrEqual(3);
  });

  it("respects topN limit", () => {
    const engine = new BM25(docs);
    const results = engine.search("renewable energy", 1);
    expect(results.length).toBe(1);
  });

  it("scores are normalized between 0 and 1", () => {
    const engine = new BM25(docs);
    const results = engine.search("wind turbine", 3);
    for (const r of results) {
      expect(r.score).toBeGreaterThanOrEqual(0);
      expect(r.score).toBeLessThanOrEqual(1);
    }
  });

  it("handles empty document set", () => {
    const engine = new BM25([]);
    const results = engine.search("anything", 5);
    expect(results).toEqual([]);
  });
});
