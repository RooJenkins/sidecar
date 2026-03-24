import type { SummaryProvider } from "./types.js";
import { createClaudeProvider } from "./claude.js";
import { createOllamaProvider } from "./ollama.js";
import { createOpenAICompatProvider } from "./openai-compat.js";

export interface ProviderOptions {
  provider?: string;
  model?: string;
  apiUrl?: string;
  apiKey?: string;
}

export function resolveProvider(options: ProviderOptions): SummaryProvider {
  const name = options.provider ?? "claude";

  switch (name) {
    case "claude":
      return createClaudeProvider(options.model);

    case "ollama":
      return createOllamaProvider(options.model, options.apiUrl);

    case "openai-compatible":
    case "openai":
      if (!options.apiUrl) {
        throw new Error(
          "openai-compatible provider requires --api-url (e.g. https://api.openai.com/v1)"
        );
      }
      return createOpenAICompatProvider(
        options.apiUrl,
        options.model,
        options.apiKey
      );

    default:
      throw new Error(
        `Unknown provider "${name}". Available: claude, ollama, openai-compatible`
      );
  }
}

export type { SummaryProvider, SummaryRequest, SummaryResult } from "./types.js";
