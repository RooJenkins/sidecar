import { writeFile, readdir, stat, readFile } from "node:fs/promises";
import { join, relative, dirname, basename } from "node:path";
import { stringify as yamlStringify } from "yaml";
import { spawnSync } from "node:child_process";
import type { ExtractedFile } from "./types.js";
import type { SummaryResult } from "./providers/types.js";
import type { SummaryProvider } from "./providers/types.js";

export const INDEX_FILENAME = "SIDECAR.md";

interface IndexEntry {
  fileName: string;
  relativePath: string;
  mimeType: string;
  extractor: string;
  wordCount?: number;
  author?: string;
  title?: string;
  summary?: SummaryResult;
}

interface SubfolderEntry {
  name: string;
  relativePath: string;
  fileCount: number;
  types: string[];
  description?: string;
}

interface DirectoryIndex {
  dirPath: string;
  relativePath: string;
  files: IndexEntry[];
  subfolders: SubfolderEntry[];
}

export async function generateIndexes(
  rootPath: string,
  processedFiles: ExtractedFile[],
  summaries: Map<string, SummaryResult>,
  options?: {
    provider?: SummaryProvider;
    onIndex?: (indexPath: string) => void;
  }
): Promise<string[]> {
  // Group files by directory
  const dirMap = new Map<string, IndexEntry[]>();

  for (const file of processedFiles) {
    const dir = dirname(file.sourcePath);
    const relPath = relative(rootPath, file.sourcePath);

    const entry: IndexEntry = {
      fileName: file.fileName,
      relativePath: relPath,
      mimeType: file.mimeType,
      extractor: file.extractor,
      wordCount: file.metadata.wordCount,
      author: file.metadata.author,
      title: file.metadata.title,
      summary: summaries.get(file.sourcePath),
    };

    const existing = dirMap.get(dir);
    if (existing) {
      existing.push(entry);
    } else {
      dirMap.set(dir, [entry]);
    }
  }

  // Also discover files from existing sidecars in dirs we didn't process
  // (files skipped by cache still need to appear in the index)
  await augmentFromExistingSidecars(rootPath, dirMap);

  // Build directory tree for subfolder summaries
  const allDirs = new Set<string>();
  for (const dir of dirMap.keys()) {
    allDirs.add(dir);
    // Add parent dirs up to root
    let parent = dirname(dir);
    while (parent.startsWith(rootPath) && parent !== rootPath) {
      allDirs.add(parent);
      parent = dirname(parent);
    }
    allDirs.add(rootPath);
  }

  // Build indexes from leaves up
  const sortedDirs = [...allDirs].sort((a, b) => b.length - a.length); // deepest first
  const dirIndexes = new Map<string, DirectoryIndex>();
  const writtenPaths: string[] = [];

  for (const dir of sortedDirs) {
    const files = dirMap.get(dir) ?? [];
    const relDir = relative(rootPath, dir) || ".";

    // Find immediate subdirectories that have indexes
    const subfolders: SubfolderEntry[] = [];
    for (const [otherDir, otherIndex] of dirIndexes) {
      if (dirname(otherDir) === dir) {
        const subName = basename(otherDir);
        const subFiles = collectAllFilesBelow(otherDir, dirMap);
        const types = [...new Set(subFiles.map((f) => getShortType(f.mimeType)))];

        // Build a brief description from file summaries
        const descriptions = subFiles
          .filter((f) => f.summary?.purpose)
          .map((f) => f.summary!.purpose)
          .slice(0, 3);
        const description = descriptions.length > 0
          ? descriptions.join("; ").slice(0, 120)
          : `${subFiles.length} files (${types.join(", ")})`;

        subfolders.push({
          name: subName,
          relativePath: relative(rootPath, otherDir),
          fileCount: subFiles.length,
          types,
          description,
        });
      }
    }

    const index: DirectoryIndex = { dirPath: dir, relativePath: relDir, files, subfolders };
    dirIndexes.set(dir, index);

    // Only write index if this dir has files or subfolders with files
    if (files.length > 0 || subfolders.length > 0) {
      const markdown = buildIndexMarkdown(index, rootPath, dirMap, !!options?.provider);

      // Generate folder-level AI summary if provider available
      let folderSummary: string | undefined;
      if (options?.provider && files.length > 0) {
        folderSummary = await generateFolderSummary(index, options.provider);
      }

      const finalMarkdown = folderSummary
        ? injectFolderSummary(markdown, folderSummary)
        : markdown;

      const indexPath = join(dir, INDEX_FILENAME);
      await writeFile(indexPath, finalMarkdown, "utf-8");
      writtenPaths.push(indexPath);
      options?.onIndex?.(indexPath);
    }
  }

  return writtenPaths;
}

async function augmentFromExistingSidecars(
  rootPath: string,
  dirMap: Map<string, IndexEntry[]>
): Promise<void> {
  await walkForSidecars(rootPath, rootPath, dirMap);
}

async function walkForSidecars(
  dirPath: string,
  rootPath: string,
  dirMap: Map<string, IndexEntry[]>
): Promise<void> {
  let entries;
  try {
    entries = await readdir(dirPath, { withFileTypes: true });
  } catch {
    return;
  }

  const excludes = ["node_modules", ".git", ".sidecar", "dist", "build", ".next"];

  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    if (excludes.includes(entry.name)) continue;
    if (entry.name === INDEX_FILENAME) continue;

    const fullPath = join(dirPath, entry.name);

    if (entry.isDirectory()) {
      await walkForSidecars(fullPath, rootPath, dirMap);
    } else if (entry.name.endsWith(".sidecar.md")) {
      // Check if we already have this file in dirMap
      const sourceName = entry.name.replace(/\.sidecar\.md$/, "");
      const existing = dirMap.get(dirPath);
      if (existing?.some((e) => e.fileName === sourceName)) continue;

      // Parse the sidecar file for metadata
      try {
        const content = await readFile(fullPath, "utf-8");
        const parsed = parseSidecarFrontmatter(content);
        if (parsed) {
          const indexEntry: IndexEntry = {
            fileName: sourceName,
            relativePath: relative(rootPath, join(dirPath, sourceName)),
            mimeType: String(parsed.mime_type ?? "unknown"),
            extractor: String(parsed.extractor ?? "unknown"),
            wordCount: typeof parsed.word_count === "number" ? parsed.word_count : undefined,
            author: typeof parsed.author === "string" ? parsed.author : undefined,
            title: typeof parsed.title === "string" ? parsed.title : undefined,
          };
          if (existing) {
            existing.push(indexEntry);
          } else {
            dirMap.set(dirPath, [indexEntry]);
          }
        }
      } catch {
        // skip unparseable sidecars
      }
    }
  }
}

function parseSidecarFrontmatter(content: string): Record<string, unknown> | null {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;
  try {
    const lines = match[1].split("\n");
    const obj: Record<string, unknown> = {};
    for (const line of lines) {
      const colonIdx = line.indexOf(":");
      if (colonIdx === -1) continue;
      const key = line.slice(0, colonIdx).trim();
      let value: unknown = line.slice(colonIdx + 1).trim();
      // Strip quotes
      if (typeof value === "string" && value.startsWith('"') && value.endsWith('"')) {
        value = value.slice(1, -1);
      }
      // Parse numbers
      if (typeof value === "string" && /^\d+$/.test(value)) {
        value = parseInt(value, 10);
      }
      obj[key] = value;
    }
    return obj;
  } catch {
    return null;
  }
}

function collectAllFilesBelow(dir: string, dirMap: Map<string, IndexEntry[]>): IndexEntry[] {
  const files: IndexEntry[] = [];
  for (const [d, entries] of dirMap) {
    if (d === dir || d.startsWith(dir + "/")) {
      files.push(...entries);
    }
  }
  return files;
}

function buildIndexMarkdown(
  index: DirectoryIndex,
  rootPath: string,
  dirMap: Map<string, IndexEntry[]>,
  hasAiProvider: boolean
): string {
  const lines: string[] = [];
  const dirName = index.relativePath === "." ? basename(rootPath) : index.relativePath;

  // Roll up total file count and words from all subdirectories
  const allFilesBelow = collectAllFilesBelow(index.dirPath, dirMap);
  const directFileCount = index.files.length;
  const totalFileCount = allFilesBelow.length;
  const allTypeBreakdown = getTypeBreakdown(allFilesBelow);
  const totalWords = allFilesBelow.reduce((sum, f) => sum + (f.wordCount ?? 0), 0);

  lines.push("---");
  lines.push(`sidecar_index: true`);
  lines.push(`directory: "${dirName}"`);
  lines.push(`file_count: ${directFileCount}`);
  lines.push(`total_file_count: ${totalFileCount}`);
  lines.push(`subfolder_count: ${index.subfolders.length}`);
  lines.push(`total_words: ${totalWords}`);
  lines.push(`generated_at: "${new Date().toISOString()}"`);
  lines.push("---");
  lines.push("");

  // Title and stats line
  lines.push(`# ${dirName}`);
  lines.push("");

  const typeSummary = allTypeBreakdown.map(([t, c]) => `${c} ${t}`).join(", ");
  const fileLabel = totalFileCount !== directFileCount
    ? `${totalFileCount} files (${directFileCount} direct)`
    : `${totalFileCount} files`;
  lines.push(`> ${fileLabel} | ${typeSummary} | ${totalWords.toLocaleString()} words`);
  lines.push("");

  // Placeholder for folder summary (injected later if AI is available)
  if (hasAiProvider) {
    lines.push("<!-- FOLDER_SUMMARY -->");
    lines.push("");
  }

  // Subfolders section
  if (index.subfolders.length > 0) {
    lines.push("## Subfolders");
    lines.push("");
    for (const sub of index.subfolders) {
      lines.push(`- **${sub.name}/** — ${sub.description}`);
    }
    lines.push("");
  }

  // Files table
  if (index.files.length > 0) {
    lines.push("## Files");
    lines.push("");
    lines.push("| File | Type | Words | Summary |");
    lines.push("|------|------|-------|---------|");

    for (const file of index.files) {
      const type = getShortType(file.mimeType);
      const words = file.wordCount?.toLocaleString() ?? "—";
      const summary = file.summary?.purpose ?? file.title ?? "—";
      // Truncate summary for table
      const shortSummary = summary.length > 80 ? summary.slice(0, 77) + "..." : summary;
      lines.push(`| ${file.fileName} | ${type} | ${words} | ${shortSummary} |`);
    }
    lines.push("");
  }

  // Entities and topics (aggregated from summaries)
  const allEntities = new Set<string>();
  const allTopics = new Set<string>();

  for (const file of index.files) {
    if (file.summary) {
      for (const e of file.summary.entities) allEntities.add(e);
      for (const t of file.summary.topics) allTopics.add(t);
    }
  }

  if (allEntities.size > 0) {
    lines.push("## Key Entities");
    lines.push("");
    lines.push([...allEntities].join(", "));
    lines.push("");
  }

  if (allTopics.size > 0) {
    lines.push("## Key Topics");
    lines.push("");
    lines.push([...allTopics].join(", "));
    lines.push("");
  }

  return lines.join("\n");
}

function injectFolderSummary(markdown: string, summary: string): string {
  return markdown.replace(
    "<!-- FOLDER_SUMMARY -->",
    `## Overview\n\n${summary}`
  );
}

async function generateFolderSummary(
  index: DirectoryIndex,
  _provider: SummaryProvider
): Promise<string> {
  const fileDescriptions = index.files
    .map((f) => {
      const desc = f.summary?.purpose ?? f.title ?? f.fileName;
      return `- ${f.fileName} (${getShortType(f.mimeType)}): ${desc}`;
    })
    .join("\n");

  const subfolderDescriptions = index.subfolders
    .map((s) => `- ${s.name}/: ${s.description}`)
    .join("\n");

  const prompt = `Describe this folder's purpose in 2-3 sentences. Be specific about what these documents are for and who would use them.

Directory: ${index.relativePath}
Files:
${fileDescriptions}
${subfolderDescriptions ? `\nSubfolders:\n${subfolderDescriptions}` : ""}

Return ONLY the description as plain text. No JSON, no markdown fences, no formatting.`;

  // Use claude -p directly for plain text output (not JSON)
  try {
    const result = spawnSync(
      "claude",
      ["-p", "--output-format", "text", "--model", "claude-sonnet-4-5-20250929", "--tools", ""],
      { input: prompt, encoding: "utf-8", timeout: 60_000, maxBuffer: 1024 * 1024 }
    );
    if (result.status === 0 && result.stdout.trim()) {
      return result.stdout.trim();
    }
  } catch {
    // fall through
  }
  return "";
}

function getTypeBreakdown(files: IndexEntry[]): [string, number][] {
  const counts = new Map<string, number>();
  for (const f of files) {
    const type = getShortType(f.mimeType);
    counts.set(type, (counts.get(type) ?? 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

function getShortType(mimeType: string): string {
  const map: Record<string, string> = {
    "application/pdf": "PDF",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "DOCX",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "XLSX",
    "application/vnd.ms-excel": "XLS",
    "text/plain": "TXT",
    "text/markdown": "MD",
    "text/csv": "CSV",
    "text/html": "HTML",
    "application/json": "JSON",
    "text/javascript": "JS",
    "application/typescript": "TS",
  };
  return map[mimeType] ?? mimeType.split("/").pop()?.toUpperCase() ?? "FILE";
}
