import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { homedir } from "node:os";
import { glob } from "glob";
import { parse as parseYaml } from "yaml";
import type { IndexedDocument, SearchIndex } from "./types.js";

const INDEX_DIR = join(homedir(), ".sidecar");
const INDEX_PATH = join(INDEX_DIR, "index.json");

/** Parse a .sidecar.md file into an IndexedDocument */
export async function parseSidecarFile(sidecarPath: string): Promise<IndexedDocument | null> {
  let raw: string;
  try {
    raw = await readFile(sidecarPath, "utf-8");
  } catch {
    return null;
  }

  // Extract YAML frontmatter
  const fmMatch = raw.match(/^---\n([\s\S]*?)\n---/);
  if (!fmMatch) return null;

  let frontmatter: Record<string, unknown>;
  try {
    frontmatter = parseYaml(fmMatch[1]) as Record<string, unknown>;
  } catch {
    return null;
  }

  // Extract Content Extract section
  const contentMatch = raw.match(/## Content Extract\n([\s\S]*?)(?=\n## |\n$|$)/);
  const contentExtract = contentMatch?.[1]?.trim() ?? "";

  // Extract AI Summary section
  const summaryMatch = raw.match(/## AI Summary\n([\s\S]*?)(?=\n## |\n$|$)/);
  const aiSummary = summaryMatch?.[1]?.trim() ?? "";

  // Extract Purpose line from AI Summary
  const purposeMatch = aiSummary.match(/\*\*Purpose\*\*:\s*(.+)/);
  const purpose = purposeMatch?.[1]?.trim() ?? "";

  const topics = Array.isArray(frontmatter.topics)
    ? (frontmatter.topics as string[])
    : [];
  const entities = Array.isArray(frontmatter.entities)
    ? (frontmatter.entities as string[])
    : [];

  return {
    sidecarPath: resolve(sidecarPath),
    sourcePath: (frontmatter.source_path as string) ?? "",
    title: (frontmatter.title as string) ?? (frontmatter.source_file as string) ?? "",
    mimeType: (frontmatter.mime_type as string) ?? "",
    wordCount: (frontmatter.word_count as number) ?? 0,
    hasAiSummary: (frontmatter.has_ai_summary as boolean) ?? false,
    topics,
    entities,
    purpose,
    aiSummary,
    contentExtract,
  };
}

/** Build a search index from all .sidecar.md files in the given paths */
export async function buildIndex(paths: string[]): Promise<SearchIndex> {
  const documents: IndexedDocument[] = [];

  for (const searchPath of paths) {
    const resolved = resolve(searchPath);
    const sidecarFiles = await glob("**/*.sidecar.md", {
      cwd: resolved,
      absolute: true,
      ignore: ["**/node_modules/**", "**/.git/**", "**/.sidecar/**"],
    });

    for (const file of sidecarFiles) {
      const doc = await parseSidecarFile(file);
      if (doc) documents.push(doc);
    }
  }

  return {
    version: "1.0",
    builtAt: new Date().toISOString(),
    documentCount: documents.length,
    documents,
  };
}

/** Save index to ~/.sidecar/index.json */
export async function saveIndex(index: SearchIndex): Promise<string> {
  await mkdir(INDEX_DIR, { recursive: true });
  await writeFile(INDEX_PATH, JSON.stringify(index), "utf-8");
  return INDEX_PATH;
}

/** Load index from ~/.sidecar/index.json */
export async function loadIndex(): Promise<SearchIndex | null> {
  try {
    const raw = await readFile(INDEX_PATH, "utf-8");
    return JSON.parse(raw) as SearchIndex;
  } catch {
    return null;
  }
}

export { INDEX_PATH };
