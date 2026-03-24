/** A single document in the search index */
export interface IndexedDocument {
  /** Path to the .sidecar.md file */
  sidecarPath: string;
  /** Path to the original source file */
  sourcePath: string;
  /** Document title (from frontmatter or filename) */
  title: string;
  /** MIME type of source file */
  mimeType: string;
  /** Word count of source document */
  wordCount: number;
  /** Whether an AI summary is present */
  hasAiSummary: boolean;
  /** Topics from frontmatter */
  topics: string[];
  /** Entities from frontmatter */
  entities: string[];
  /** Purpose line from AI Summary section */
  purpose: string;
  /** AI summary text (Key Points, etc.) */
  aiSummary: string;
  /** Raw content extract text */
  contentExtract: string;
}

/** Persisted search index */
export interface SearchIndex {
  version: string;
  builtAt: string;
  documentCount: number;
  documents: IndexedDocument[];
}

/** A single search result returned to the caller */
export interface SearchResult {
  /** Original source file path */
  file: string;
  /** Sidecar file path */
  sidecar: string;
  /** Relevance score (0-1 normalized) */
  score: number;
  /** Document title */
  title: string;
  /** Summary or purpose text */
  summary: string;
  /** Topics */
  topics: string[];
  /** Text snippet with matching context */
  snippet: string;
}

/** Output of a search query */
export interface SearchOutput {
  query: string;
  results: SearchResult[];
}
