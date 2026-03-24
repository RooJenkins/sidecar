import type { SummaryProvider, SummaryRequest, SummaryResult } from "./types.js";

const SYSTEM_PROMPT = `You are a document summarizer. Given a document's content, produce a JSON object with exactly these fields:
- "purpose": one sentence describing what this document is
- "keyPoints": array of 3-7 bullet points (strings)
- "entities": array of people, teams, companies, or products mentioned
- "topics": array of topic tags
- "relevance": one sentence about who would care about this document

Return ONLY valid JSON, no markdown fences, no explanation.`;

export function createOllamaProvider(
  model?: string,
  baseUrl?: string
): SummaryProvider {
  const modelId = model ?? "llama3.2";
  const url = baseUrl ?? "http://localhost:11434";

  return {
    name: "ollama",
    maxContentChars: 8_000,

    async summarize(request: SummaryRequest): Promise<SummaryResult> {
      const prompt = buildPrompt(request);

      const response = await fetch(`${url}/api/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: modelId,
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: prompt },
          ],
          stream: false,
          format: "json",
        }),
        signal: AbortSignal.timeout(120_000),
      });

      if (!response.ok) {
        throw new Error(`Ollama API error: ${response.status} ${response.statusText}`);
      }

      const data = (await response.json()) as { message?: { content?: string } };
      const output = data.message?.content?.trim() ?? "";

      return parseSummaryJSON(output);
    },
  };
}

function buildPrompt(request: SummaryRequest): string {
  return `Summarize this document.

File: ${request.fileName}
Type: ${request.mimeType}

Content:
${request.content}`;
}

function parseSummaryJSON(output: string): SummaryResult {
  let cleaned = output;
  const fenceMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenceMatch) {
    cleaned = fenceMatch[1];
  }
  cleaned = cleaned.trim();

  const parsed = JSON.parse(cleaned);

  return {
    purpose: String(parsed.purpose ?? ""),
    keyPoints: Array.isArray(parsed.keyPoints) ? parsed.keyPoints.map(String) : [],
    entities: Array.isArray(parsed.entities) ? parsed.entities.map(String) : [],
    topics: Array.isArray(parsed.topics) ? parsed.topics.map(String) : [],
    relevance: String(parsed.relevance ?? ""),
  };
}
