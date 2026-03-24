import type { SummaryProvider, SummaryRequest, SummaryResult } from "./providers/types.js";
import type { ExtractedFile } from "./types.js";

const DEFAULT_AI_CONCURRENCY = 2;

export interface SummarizerOptions {
  provider: SummaryProvider;
  concurrency?: number;
  onSuccess?: (fileName: string, result: SummaryResult) => void;
  onError?: (fileName: string, error: Error) => void;
}

export async function summarizeFiles(
  files: ExtractedFile[],
  options: SummarizerOptions
): Promise<Map<string, SummaryResult>> {
  const { provider, concurrency = DEFAULT_AI_CONCURRENCY } = options;
  const results = new Map<string, SummaryResult>();

  // Rate-limited pool
  const pending: Promise<void>[] = [];

  for (const file of files) {
    const task = (async () => {
      try {
        const content = truncateContent(file.content, provider.maxContentChars);

        const request: SummaryRequest = {
          fileName: file.fileName,
          mimeType: file.mimeType,
          content,
          metadata: file.metadata as Record<string, unknown>,
        };

        const result = await provider.summarize(request);
        results.set(file.sourcePath, result);
        options.onSuccess?.(file.fileName, result);
      } catch (err) {
        options.onError?.(
          file.fileName,
          err instanceof Error ? err : new Error(String(err))
        );
      }
    })();

    pending.push(task);

    if (pending.length >= concurrency) {
      await Promise.race(pending);
      for (let i = pending.length - 1; i >= 0; i--) {
        const settled = await Promise.race([
          pending[i].then(() => true),
          Promise.resolve(false),
        ]);
        if (settled) pending.splice(i, 1);
      }
    }
  }

  await Promise.all(pending);
  return results;
}

export async function summarizeSingle(
  file: ExtractedFile,
  provider: SummaryProvider
): Promise<SummaryResult> {
  const content = truncateContent(file.content, provider.maxContentChars);

  return provider.summarize({
    fileName: file.fileName,
    mimeType: file.mimeType,
    content,
    metadata: file.metadata as Record<string, unknown>,
  });
}

function truncateContent(content: string, maxChars: number): string {
  if (content.length <= maxChars) return content;
  const truncated = content.slice(0, maxChars);
  return truncated + "\n\n[Content truncated — original was " +
    `${content.length.toLocaleString()} characters]`;
}
