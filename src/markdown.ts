import { writeFile, mkdir } from "node:fs/promises";
import { join, relative, dirname } from "node:path";
import { stringify as yamlStringify } from "yaml";
import type { ExtractedFile, SidecarMetadata } from "./types.js";
import type { SummaryResult } from "./providers/types.js";

export function generateSidecarPath(
  sourcePath: string,
  rootPath?: string,
  outputDir?: string
): string {
  if (outputDir && rootPath) {
    const relPath = relative(rootPath, sourcePath);
    return join(outputDir, `${relPath}.sidecar.md`);
  }
  return `${sourcePath}.sidecar.md`;
}

export function buildSidecarMarkdown(
  file: ExtractedFile,
  summary?: SummaryResult
): string {
  const frontmatter = buildFrontmatter(file, !!summary);
  const sections: string[] = [];

  sections.push(`# ${file.fileName}`);
  sections.push("");
  sections.push(buildMetadataSection(file));
  sections.push("");

  if (file.content.trim()) {
    sections.push("## Content Extract");
    sections.push("");
    sections.push(file.content);
    sections.push("");
  }

  if (summary) {
    sections.push(buildSummarySection(summary));
    sections.push("");
  }

  const yaml = yamlStringify(frontmatter).trim();
  return `---\n${yaml}\n---\n\n${sections.join("\n")}`;
}

export async function writeSidecarFile(
  file: ExtractedFile,
  summary?: SummaryResult,
  options?: { rootPath?: string; outputDir?: string }
): Promise<string> {
  const sidecarPath = generateSidecarPath(
    file.sourcePath,
    options?.rootPath,
    options?.outputDir
  );
  await mkdir(dirname(sidecarPath), { recursive: true });
  const content = buildSidecarMarkdown(file, summary);
  await writeFile(sidecarPath, content, "utf-8");
  return sidecarPath;
}

function buildFrontmatter(
  file: ExtractedFile,
  hasSummary: boolean
): SidecarMetadata {
  return {
    sidecar_version: "1.0",
    source_file: file.fileName,
    source_path: file.sourcePath,
    mime_type: file.mimeType,
    file_size_bytes: file.fileSizeBytes,
    created_at: file.createdAt.toISOString(),
    modified_at: file.modifiedAt.toISOString(),
    processed_at: file.processedAt.toISOString(),
    extractor: file.extractor,
    ...(file.metadata.author ? { author: file.metadata.author } : {}),
    ...(file.metadata.title ? { title: file.metadata.title } : {}),
    ...(file.metadata.language ? { language: file.metadata.language } : {}),
    ...(file.metadata.wordCount ? { word_count: file.metadata.wordCount } : {}),
    has_ai_summary: hasSummary,
  };
}

function buildSummarySection(summary: SummaryResult): string {
  const lines: string[] = ["## AI Summary"];

  if (summary.purpose) {
    lines.push(`**Purpose**: ${summary.purpose}`);
  }

  if (summary.keyPoints.length > 0) {
    lines.push("");
    lines.push("**Key Points**:");
    for (const point of summary.keyPoints) {
      lines.push(`- ${point}`);
    }
  }

  if (summary.entities.length > 0) {
    lines.push("");
    lines.push(`**Entities Mentioned**: ${summary.entities.join(", ")}`);
  }

  if (summary.topics.length > 0) {
    lines.push("");
    lines.push(`**Topics**: ${summary.topics.join(", ")}`);
  }

  if (summary.relevance) {
    lines.push("");
    lines.push(`**Relevance**: ${summary.relevance}`);
  }

  return lines.join("\n");
}

function buildMetadataSection(file: ExtractedFile): string {
  const lines: string[] = ["## Metadata"];

  const typeLabel = getTypeLabel(file.mimeType);
  lines.push(`- **Type**: ${typeLabel}`);

  if (file.metadata.author) {
    lines.push(`- **Author**: ${file.metadata.author}`);
  }
  if (file.metadata.title) {
    lines.push(`- **Title**: ${file.metadata.title}`);
  }
  if (file.metadata.pageCount) {
    lines.push(`- **Pages**: ${file.metadata.pageCount}`);
  }
  if (file.metadata.sheetNames) {
    lines.push(`- **Sheets**: ${file.metadata.sheetNames.join(", ")}`);
  }
  if (file.metadata.rowCount) {
    lines.push(`- **Rows**: ${file.metadata.rowCount}`);
  }
  if (file.metadata.wordCount) {
    lines.push(`- **Words**: ${file.metadata.wordCount.toLocaleString()}`);
  }

  lines.push(`- **Size**: ${formatSize(file.fileSizeBytes)}`);
  lines.push(`- **Last Modified**: ${file.modifiedAt.toISOString().split("T")[0]}`);

  return lines.join("\n");
}

function getTypeLabel(mimeType: string): string {
  const labels: Record<string, string> = {
    "application/pdf": "PDF Document",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
      "Word Document (DOCX)",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
      "Excel Spreadsheet (XLSX)",
    "application/vnd.ms-excel": "Excel Spreadsheet (XLS)",
    "text/plain": "Plain Text",
    "text/markdown": "Markdown",
    "text/csv": "CSV",
    "text/html": "HTML",
    "application/json": "JSON",
    "text/javascript": "JavaScript",
    "application/typescript": "TypeScript",
  };
  return labels[mimeType] ?? mimeType;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
