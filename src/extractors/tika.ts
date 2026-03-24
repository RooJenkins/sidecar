import { readFile } from "node:fs/promises";
import type { Extractor, ExtractionResult } from "./types.js";

const DEFAULT_TIKA_URL = "http://localhost:9998";

export function createTikaExtractor(tikaUrl?: string): Extractor {
  const url = tikaUrl ?? DEFAULT_TIKA_URL;

  return {
    name: "tika",
    // Tika handles everything — this is the fallback extractor
    supportedMimeTypes: ["*"],

    async extract(filePath: string): Promise<ExtractionResult> {
      const buffer = await readFile(filePath);

      // Extract text content
      const textResponse = await fetch(`${url}/tika`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/octet-stream",
          Accept: "text/plain",
        },
        body: buffer,
        signal: AbortSignal.timeout(60_000),
      });

      if (!textResponse.ok) {
        throw new Error(
          `Tika text extraction failed: ${textResponse.status} ${textResponse.statusText}`
        );
      }

      const content = await textResponse.text();

      // Extract metadata
      const metaResponse = await fetch(`${url}/meta`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/octet-stream",
          Accept: "application/json",
        },
        body: buffer,
        signal: AbortSignal.timeout(30_000),
      });

      let tikaMeta: Record<string, unknown> = {};
      if (metaResponse.ok) {
        tikaMeta = (await metaResponse.json()) as Record<string, unknown>;
      }

      const words = content.split(/\s+/).filter(Boolean);

      return {
        content,
        metadata: {
          title: asString(tikaMeta["dc:title"] ?? tikaMeta["title"]),
          author: asString(tikaMeta["dc:creator"] ?? tikaMeta["Author"]),
          language: asString(tikaMeta["language"] ?? tikaMeta["dc:language"]),
          pageCount: asNumber(tikaMeta["xmpTPg:NPages"]),
          wordCount: words.length,
        },
      };
    },
  };
}

export async function isTikaAvailable(tikaUrl?: string): Promise<boolean> {
  const url = tikaUrl ?? DEFAULT_TIKA_URL;
  try {
    const response = await fetch(`${url}/version`, {
      signal: AbortSignal.timeout(3_000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function asString(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  return undefined;
}

function asNumber(value: unknown): number | undefined {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const n = parseInt(value, 10);
    if (!isNaN(n)) return n;
  }
  return undefined;
}
