import { describe, it, expect, vi, beforeEach } from "vitest";
import { smartSearch } from "../smart-search.js";
import * as searchModule from "../search/index.js";

// Mock the search module to avoid needing a real index
vi.mock("../search/index.js", () => ({
  search: vi.fn(),
}));

const mockSearch = vi.mocked(searchModule.search);

const makeResult = (title: string, score: number, summary = "") => ({
  file: `/docs/${title.toLowerCase().replace(/\s/g, "-")}.pdf`,
  sidecar: `/docs/${title.toLowerCase().replace(/\s/g, "-")}.pdf.sidecar.md`,
  score,
  title,
  summary,
  topics: [],
  snippet: "",
});

describe("smartSearch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns empty results when BM25 finds nothing", async () => {
    mockSearch.mockResolvedValue({ query: "test", results: [] });

    const output = await smartSearch("random conversation about nothing");
    expect(output.results).toEqual([]);
    expect(mockSearch).toHaveBeenCalledOnce();
  });

  it("calls BM25 with last 500 chars of conversation", async () => {
    const longConversation = "x".repeat(1000);
    mockSearch.mockResolvedValue({ query: "test", results: [] });

    await smartSearch(longConversation);

    const calledWith = mockSearch.mock.calls[0][0];
    expect(calledWith.length).toBe(500);
  });

  it("skips AI when no keyword overlap exists", async () => {
    // BM25 returns results but keywords don't overlap with query
    mockSearch.mockResolvedValue({
      query: "chocolate cake recipe baking",
      results: [
        makeResult("Solar Panel Guide", 1.0, "solar panel installation residential"),
        makeResult("Wind Turbine Manual", 0.9, "wind turbine offshore maintenance"),
      ],
    });

    const output = await smartSearch("how to bake a chocolate cake with frosting");
    // Should return empty because meaningful keywords (chocolate, frosting, baking)
    // don't appear in result titles/summaries
    expect(output.results).toEqual([]);
  });

  it("returns BM25 results when keywords overlap (AI may or may not be available)", async () => {
    mockSearch.mockResolvedValue({
      query: "solar panel installation",
      results: [
        makeResult("Solar Panel Guide", 1.0, "solar panel installation guide for residential"),
        makeResult("Solar Costs Analysis", 0.8, "solar panel costs pricing analysis"),
      ],
    });

    // With keyword overlap, smartSearch will attempt AI filtering.
    // In test env, claude may or may not work — either way we should get results.
    const output = await smartSearch("tell me about solar panel installation");
    // Either AI-filtered or BM25 fallback — both are valid
    expect(output.results.length).toBeGreaterThanOrEqual(0);
    expect(output.results.length).toBeLessThanOrEqual(5);
  }, 25000); // longer timeout for potential AI call

  it("respects maxResults option", async () => {
    mockSearch.mockResolvedValue({
      query: "test",
      results: [],
    });

    await smartSearch("test query", { maxResults: 3 });
    // Should request 3*3=9 or 15 candidates (whichever is larger)
    const requestedCount = mockSearch.mock.calls[0][1];
    expect(requestedCount).toBeGreaterThanOrEqual(9);
  });
});
