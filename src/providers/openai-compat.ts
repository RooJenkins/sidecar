import type { SummaryProvider, SummaryRequest, SummaryResult } from "./types.js";

const SYSTEM_PROMPT = `You are a document summarizer. Given a document's content, produce a JSON object with exactly these fields:
- "purpose": one sentence describing what this document is
- "keyPoints": array of 3-7 bullet points (strings)
- "entities": array of people, teams, companies, or products mentioned
- "topics": array of topic tags
- "relevance": one sentence about who would care about this document

Return ONLY valid JSON, no markdown fences, no explanation.`;

export function createOpenAICompatProvider(
  apiUrl: string,
  model?: string,
  apiKey?: string
): SummaryProvider {
  const modelId = model ?? "gpt-4o-mini";

  return {
    name: "openai-compatible",
    maxContentChars: 30_000,

    async summarize(request: SummaryRequest): Promise<SummaryResult> {
      const prompt = buildPrompt(request);

      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (apiKey) {
        headers["Authorization"] = `Bearer ${apiKey}`;
      }

      const response = await fetch(`${apiUrl}/chat/completions`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          model: modelId,
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: prompt },
          ],
          temperature: 0.3,
          response_format: { type: "json_object" },
        }),
        signal: AbortSignal.timeout(120_000),
      });

      if (!response.ok) {
        const body = await response.text().catch(() => "");
        throw new Error(`API error: ${response.status} ${response.statusText}${body ? ` — ${body}` : ""}`);
      }

      const data = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const output = data.choices?.[0]?.message?.content?.trim() ?? "";

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
