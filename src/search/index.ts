import { BM25 } from "./bm25.js";
import { loadIndex } from "./indexer.js";
import type { SearchOutput } from "./types.js";

/**
 * Search the sidecar knowledge base.
 * Loads the index from ~/.sidecar/index.json and runs BM25 ranking.
 */
export async function search(query: string, topN = 5): Promise<SearchOutput> {
  const index = await loadIndex();

  if (!index || index.documentCount === 0) {
    return { query, results: [] };
  }

  const engine = new BM25(index.documents);
  const results = engine.search(query, topN);

  return { query, results };
}

export { buildIndex, saveIndex, loadIndex, INDEX_PATH } from "./indexer.js";
export { BM25, tokenize } from "./bm25.js";
export type { SearchResult, SearchOutput, SearchIndex, IndexedDocument } from "./types.js";
