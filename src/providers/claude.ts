import { spawnSync } from "node:child_process";
import type { SummaryProvider, SummaryRequest, SummaryResult } from "./types.js";

const SYSTEM_PROMPT = `You are a document summarizer. Given a document's content, produce a JSON object with exactly these fields:
- "purpose": one sentence describing what this document is
- "keyPoints": array of 3-7 bullet points (strings)
- "entities": array of people, teams, companies, or products mentioned
- "topics": array of topic tags
- "relevance": one sentence about who would care about this document

Return ONLY valid JSON, no markdown fences, no explanation.`;

export function createClaudeProvider(model?: string): SummaryProvider {
  const modelId = model ?? "claude-sonnet-4-5-20250929";

  return {
    name: "claude",
    maxContentChars: 100_000,

    async summarize(request: SummaryRequest): Promise<SummaryResult> {
      const prompt = buildPrompt(request);

      const result = spawnSync(
        "claude",
        [
          "-p",
          "--output-format", "text",
          "--system-prompt", SYSTEM_PROMPT,
          "--model", modelId,
          "--tools", "",
        ],
        {
          input: prompt,
          encoding: "utf-8",
          timeout: 120_000,
          maxBuffer: 2 * 1024 * 1024,
        }
      );

      if (result.error) {
        throw new Error(`claude CLI error: ${result.error.message}`);
      }
      if (result.status !== 0) {
        const stderr = result.stderr?.trim() ?? "";
        throw new Error(`claude CLI exited with status ${result.status}${stderr ? `: ${stderr}` : ""}`);
      }

      const output = result.stdout.trim();
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
  // Strip markdown fences if present
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
