import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { search } from "./search/index.js";
import type { SearchOutput, SearchResult } from "./search/types.js";

/** Resolve the claude CLI path, checking common locations. */
function findClaude(): string {
  const pathDirs = (process.env.PATH || "").split(":");
  for (const dir of pathDirs) {
    const candidate = join(dir, "claude");
    if (existsSync(candidate)) return candidate;
  }
  const candidates = [
    join(homedir(), ".local/bin/claude"),
    "/opt/homebrew/bin/claude",
    "/usr/local/bin/claude",
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  return "claude";
}

function makeEnv() {
  return {
    ...process.env,
    PATH: [
      join(homedir(), ".local/bin"),
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      process.env.PATH || "",
    ].join(":"),
  };
}

const SMART_SEARCH_SCHEMA = JSON.stringify({
  type: "object",
  properties: {
    relevant: {
      type: "array",
      items: {
        type: "object",
        properties: {
          index: { type: "number", description: "0-based index from the candidate list" },
        },
        required: ["index"],
      },
      description: "Indices of candidates that are GENUINELY relevant. Empty array if none are relevant.",
    },
  },
  required: ["relevant"],
});

const SMART_SEARCH_PROMPT = [
  "You judge document relevance. Given a conversation and candidate documents from a knowledge base,",
  "return ONLY the indices of documents that are genuinely relevant to what's being discussed.",
  "Be strict: a document about 'pricing' for Project A is NOT relevant to a conversation about pricing Project B.",
  "A document about 'React setup' is NOT relevant to a conversation about renewable energy.",
  "If NONE of the candidates are relevant, return an empty array.",
  "Judge based on whether the document would actually help the user in their current conversation.",
].join(" ");

export interface SmartSearchOptions {
  maxResults?: number;
  model?: string;
  verbose?: boolean;
  onRelevance?: (kept: number, total: number) => void;
}

/**
 * AI-powered smart search — single AI call approach:
 * 1. Run a broad BM25 search using the raw conversation text
 * 2. Send candidates + conversation to AI in ONE call for relevance filtering
 *
 * This is ~2x faster than the two-call approach (extract queries + filter).
 */
export async function smartSearch(
  conversation: string,
  options: SmartSearchOptions = {}
): Promise<SearchOutput> {
  const { maxResults = 5, model = "haiku", verbose, onRelevance } = options;

  // Step 1: Broad BM25 search using the last ~500 chars as query
  // (BM25 is keyword-based so a chunk of conversation text works fine for candidates)
  const queryText = conversation.slice(-500);
  const candidateCount = Math.max(maxResults * 3, 15);
  const bm25Output = await search(queryText, candidateCount);

  // No candidates at all — skip the AI call entirely
  if (bm25Output.results.length === 0) {
    return { query: queryText, results: [] };
  }

  // Check if there's meaningful keyword overlap between the query and results.
  // BM25 normalizes scores relative to the best match (top is always ~1.0),
  // so we check the raw snippet/title overlap instead.
  // If the query words don't appear in any result titles or snippets, skip AI.
  // Extract meaningful words (5+ chars, skip common words)
  const stopWords = new Set(["about", "after", "again", "could", "every", "first", "found",
    "great", "have", "their", "there", "these", "think", "those", "under", "using",
    "where", "which", "while", "would", "should", "being", "other", "still", "what"]);
  const queryWords = new Set(
    queryText.toLowerCase().split(/\s+/)
      .filter(w => w.length >= 5 && !stopWords.has(w))
  );
  const resultText = bm25Output.results
    .map(r => `${r.title} ${r.snippet} ${r.summary}`.toLowerCase())
    .join(" ");
  const matchingWords = [...queryWords].filter(w => resultText.includes(w));
  // Need at least 2 meaningful keyword overlaps, or skip AI
  if (matchingWords.length < 2 && queryWords.size >= 2) {
    if (verbose) {
      process.stderr.write(`smart-search: no keyword overlap, skipping AI call\n`);
    }
    return { query: queryText, results: [] };
  }

  // Step 2: Single AI call — judge which candidates are relevant
  const prompt = [
    "## Conversation",
    conversation.slice(-4000),
    "",
    "## Candidate Documents",
    ...bm25Output.results.map((r, i) =>
      `[${i}] "${r.title}" — ${r.summary || r.snippet || "(no summary)"}`
    ),
    "",
    "Which candidates are genuinely relevant to this conversation?",
  ].join("\n");

  const claudePath = findClaude();
  const result = spawnSync(
    claudePath,
    [
      "-p",
      "--output-format", "json",
      "--json-schema", SMART_SEARCH_SCHEMA,
      "--system-prompt", SMART_SEARCH_PROMPT,
      "--model", model,
      "--tools", "",
    ],
    {
      input: prompt,
      encoding: "utf-8",
      timeout: 20000,
      env: makeEnv(),
    }
  );

  if (result.status !== 0 || !result.stdout?.trim()) {
    // AI unavailable — fall back to raw BM25 top N
    if (verbose) {
      const err = result.stderr?.toString().slice(0, 200) || "unknown error";
      process.stderr.write(`smart-search: AI unavailable (${err}), using BM25 fallback\n`);
    }
    return { query: queryText, results: bm25Output.results.slice(0, maxResults) };
  }

  try {
    const parsed = JSON.parse(result.stdout);
    const output = parsed.structured_output ?? parsed;

    if (Array.isArray(output.relevant)) {
      const filtered = output.relevant
        .map((r: { index: number }) => bm25Output.results[r.index])
        .filter((r: SearchResult | undefined): r is SearchResult => r != null)
        .slice(0, maxResults);

      if (onRelevance) onRelevance(filtered.length, bm25Output.results.length);
      return { query: queryText, results: filtered };
    }
  } catch {
    // parse failure — fall back
  }

  return { query: queryText, results: bm25Output.results.slice(0, maxResults) };
}
