import type { IndexedDocument, SearchResult } from "./types.js";

// ── Tokenizer ────────────────────────────────────────────────────────────

const STOP_WORDS = new Set([
  "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
  "of", "with", "by", "from", "is", "it", "as", "be", "was", "are",
  "were", "been", "has", "had", "do", "does", "did", "will", "would",
  "could", "should", "may", "might", "can", "this", "that", "these",
  "those", "not", "no", "so", "if", "then", "than", "into", "up",
  "out", "its", "all", "any", "each", "which", "their", "there",
  "about", "also", "more", "some", "such", "other", "over", "only",
]);

export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 1 && !STOP_WORDS.has(t));
}

// ── BM25 Engine ──────────────────────────────────────────────────────────

/** Field weights for scoring */
const FIELD_WEIGHTS = {
  topics: 5.0,
  entities: 5.0,
  title: 4.0,
  purpose: 3.5,
  aiSummary: 2.0,
  contentExtract: 1.0,
};

/** BM25 parameters */
const K1 = 1.2;
const B = 0.75;

interface FieldTokens {
  topics: string[];
  entities: string[];
  title: string[];
  purpose: string[];
  aiSummary: string[];
  contentExtract: string[];
}

interface PreparedDoc {
  doc: IndexedDocument;
  fields: FieldTokens;
  totalLength: number;
}

export class BM25 {
  private prepared: PreparedDoc[] = [];
  private avgDocLength = 0;
  /** doc frequency: how many docs contain each term (across all fields) */
  private df = new Map<string, number>();
  private docCount = 0;

  constructor(documents: IndexedDocument[]) {
    this.docCount = documents.length;
    if (this.docCount === 0) return;

    // Tokenize all fields for each document
    let totalLength = 0;
    this.prepared = documents.map((doc) => {
      const fields: FieldTokens = {
        topics: tokenize(doc.topics.join(" ")),
        entities: tokenize(doc.entities.join(" ")),
        title: tokenize(doc.title),
        purpose: tokenize(doc.purpose),
        aiSummary: tokenize(doc.aiSummary),
        contentExtract: tokenize(doc.contentExtract),
      };
      const docLen =
        fields.topics.length * FIELD_WEIGHTS.topics +
        fields.entities.length * FIELD_WEIGHTS.entities +
        fields.title.length * FIELD_WEIGHTS.title +
        fields.purpose.length * FIELD_WEIGHTS.purpose +
        fields.aiSummary.length * FIELD_WEIGHTS.aiSummary +
        fields.contentExtract.length * FIELD_WEIGHTS.contentExtract;
      totalLength += docLen;
      return { doc, fields, totalLength: docLen };
    });
    this.avgDocLength = totalLength / this.docCount;

    // Build document frequency map
    for (const { fields } of this.prepared) {
      const seen = new Set<string>();
      for (const fieldTokens of Object.values(fields)) {
        for (const token of fieldTokens) {
          seen.add(token);
        }
      }
      for (const term of seen) {
        this.df.set(term, (this.df.get(term) ?? 0) + 1);
      }
    }
  }

  search(query: string, topN: number): SearchResult[] {
    if (this.docCount === 0) return [];

    const queryTokens = tokenize(query);
    if (queryTokens.length === 0) return [];

    const scores: Array<{ idx: number; score: number }> = [];

    for (let i = 0; i < this.prepared.length; i++) {
      const { fields, totalLength } = this.prepared[i];
      let score = 0;

      for (const qTerm of queryTokens) {
        const docFreq = this.df.get(qTerm) ?? 0;
        if (docFreq === 0) continue;

        // IDF: log((N - df + 0.5) / (df + 0.5) + 1)
        const idf = Math.log((this.docCount - docFreq + 0.5) / (docFreq + 0.5) + 1);

        // Count weighted term frequency across fields
        let weightedTf = 0;
        for (const [fieldName, tokens] of Object.entries(fields)) {
          const count = (tokens as string[]).filter((t: string) => t === qTerm).length;
          if (count > 0) {
            weightedTf += count * FIELD_WEIGHTS[fieldName as keyof typeof FIELD_WEIGHTS];
          }
        }

        if (weightedTf === 0) continue;

        // BM25 TF component
        const tfNorm =
          (weightedTf * (K1 + 1)) /
          (weightedTf + K1 * (1 - B + B * (totalLength / this.avgDocLength)));

        score += idf * tfNorm;
      }

      if (score > 0) {
        scores.push({ idx: i, score });
      }
    }

    // Sort by score descending
    scores.sort((a, b) => b.score - a.score);

    // Normalize scores (max = 1.0)
    const maxScore = scores.length > 0 ? scores[0].score : 1;

    return scores.slice(0, topN).map(({ idx, score }) => {
      const { doc, fields } = this.prepared[idx];
      return {
        file: doc.sourcePath,
        sidecar: doc.sidecarPath,
        score: Math.round((score / maxScore) * 100) / 100,
        title: doc.title,
        summary: doc.purpose || doc.aiSummary.slice(0, 200) || "",
        topics: doc.topics,
        snippet: buildSnippet(fields, queryTokens),
      };
    });
  }
}

/** Build a snippet showing context around matched terms */
function buildSnippet(fields: FieldTokens, queryTokens: string[]): string {
  // Prefer content extract for snippets, fallback to AI summary
  const text = fields.contentExtract.length > 0
    ? fields.contentExtract.join(" ")
    : fields.aiSummary.join(" ");

  if (!text) return "";

  const querySet = new Set(queryTokens);
  const tokens = text.split(" ");

  // Find first matching token position
  let matchIdx = tokens.findIndex((t) => querySet.has(t));
  if (matchIdx === -1) matchIdx = 0;

  const start = Math.max(0, matchIdx - 5);
  const end = Math.min(tokens.length, matchIdx + 15);
  let snippet = tokens.slice(start, end).join(" ");

  if (start > 0) snippet = "..." + snippet;
  if (end < tokens.length) snippet = snippet + "...";

  return snippet;
}
