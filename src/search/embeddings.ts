import type { SearchResult } from "./types.js";

const DEFAULT_MODEL = "nomic-embed-text";
const DEFAULT_URL = "http://localhost:11434";

/** Get embeddings from Ollama */
async function embed(texts: string[], model: string, baseUrl: string): Promise<number[][]> {
  const results: number[][] = [];

  for (const text of texts) {
    const response = await fetch(`${baseUrl}/api/embeddings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model, prompt: text }),
    });

    if (!response.ok) {
      throw new Error(`Ollama embeddings error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json() as { embedding: number[] };
    results.push(data.embedding);
  }

  return results;
}

/** Cosine similarity between two vectors */
function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom === 0 ? 0 : dot / denom;
}

/**
 * Re-rank BM25 results using semantic embeddings from Ollama.
 * Takes BM25 candidates and re-orders by cosine similarity to the query.
 */
export async function rerankWithEmbeddings(
  query: string,
  candidates: SearchResult[],
  options?: { model?: string; baseUrl?: string }
): Promise<SearchResult[]> {
  if (candidates.length === 0) return [];

  const model = options?.model ?? DEFAULT_MODEL;
  const baseUrl = options?.baseUrl ?? DEFAULT_URL;

  // Build texts: query + each candidate's summary/title
  const texts = [
    query,
    ...candidates.map((c) =>
      [c.title, c.summary, c.topics.join(" ")].filter(Boolean).join(". ")
    ),
  ];

  const embeddings = await embed(texts, model, baseUrl);
  const queryEmb = embeddings[0];

  // Score each candidate by cosine similarity
  const scored = candidates.map((candidate, i) => ({
    candidate,
    similarity: cosineSimilarity(queryEmb, embeddings[i + 1]),
  }));

  // Sort by similarity descending
  scored.sort((a, b) => b.similarity - a.similarity);

  // Replace scores with normalized similarity
  const maxSim = scored.length > 0 ? scored[0].similarity : 1;
  return scored.map(({ candidate, similarity }) => ({
    ...candidate,
    score: Math.round((similarity / maxSim) * 100) / 100,
  }));
}
