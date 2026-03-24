export interface SummaryRequest {
  fileName: string;
  mimeType: string;
  content: string;
  metadata: Record<string, unknown>;
}

export interface SummaryResult {
  purpose: string;
  keyPoints: string[];
  entities: string[];
  topics: string[];
  relevance: string;
}

export interface SummaryProvider {
  name: string;
  maxContentChars: number;
  summarize(request: SummaryRequest): Promise<SummaryResult>;
}
