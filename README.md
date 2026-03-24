# Sidecar

**Your files. Agent-readable. In seconds.**

Sidecar scans your documents and generates structured `.sidecar.md` companion files that AI agents can consume. Then searches them intelligently when you need context — in any AI chat, from any app, with a single hotkey.

Privacy-first: documents never leave your machine.

## Install

```bash
npm install -g uplo-sidecar
```

Or run directly:

```bash
npx uplo-sidecar scan ~/Documents
```

## Quick Start

```bash
# Scan a folder — generates .sidecar.md files alongside originals
sidecar scan ~/Documents

# Build a search index
sidecar index ~/Documents

# Search your knowledge base
sidecar search "project timeline"

# AI-powered smart search — understands context, filters irrelevant results
sidecar smart-search "What did we propose for the platform?"

# Pipe conversation context for better results
pbpaste | sidecar smart-search --top 5

# Watch for changes — keeps sidecars always up to date
sidecar scan ~/Documents --watch

# Check status
sidecar status ~/Documents
```

## How It Works

```
Your Documents          Sidecar                    AI Agents
┌──────────┐           ┌──────────────┐           ┌──────────┐
│ report.pdf│  scan →   │ report.pdf   │  search → │ Relevant │
│ specs.docx│           │   .sidecar.md│           │ context  │
│ data.xlsx │           │ specs.docx   │           │ injected │
│           │           │   .sidecar.md│           │ into chat│
└──────────┘           └──────────────┘           └──────────┘
```

1. **Scan** — Extract text and metadata from PDFs, DOCX, XLSX, and 1,400+ other formats
2. **Index** — Build a searchable knowledge base from your sidecar files
3. **Search** — Find relevant documents using keywords or AI-powered context analysis
4. **Inject** — Attach documents to any AI chat via hotkey (macOS app or Chrome extension)

## What It Generates

For each file, sidecar creates a companion `.sidecar.md`:

```markdown
---
sidecar_version: "1.0"
source_file: "report.pdf"
mime_type: "application/pdf"
extractor: "pdf-parse"
word_count: 4350
has_ai_summary: true
---

# report.pdf

## Metadata
- **Type**: PDF Document
- **Author**: Jane Smith
- **Pages**: 12
- **Words**: 4,350

## Content Extract
[Full extracted text...]

## AI Summary
**Purpose**: Quarterly performance report for Q1 2026...
**Key Points**: [bullets]
**Entities**: Jane Smith, Platform Engineering
**Topics**: infrastructure, kubernetes, SRE
```

It also generates `SIDECAR.md` index files per directory with file stats, subfolder summaries, and aggregated topics.

## Commands

| Command | Description |
|---------|-------------|
| `sidecar scan <path>` | Scan folder and generate sidecar files |
| `sidecar index [paths...]` | Build/rebuild search index |
| `sidecar search <query>` | Search the knowledge base (BM25) |
| `sidecar smart-search [query]` | AI-powered contextual search |
| `sidecar status <path>` | Show tracked files, stale sidecars, disk usage |
| `sidecar clean <path>` | Remove all .sidecar.md files, indexes, and cache |
| `sidecar init` | Set up advisory git pre-commit hook |

### Scan Options

```
--include <globs...>      File patterns to include
--exclude <globs...>      Exclude patterns
--max-file-size <size>    Skip files larger than this (default: 100MB)
--output-dir <dir>        Write sidecars to mirrored directory
--summarize               Enable AI summarization
--provider <name>         AI provider: claude (default), ollama, openai-compatible
--model <model>           Model name
--watch                   Watch mode — re-process on change
--concurrency <n>         Parallel processing (default: 4)
--no-tika                 JS-native extractors only
--dry-run                 Preview without writing
--json                    JSON output
```

### Smart Search

AI-powered search that understands conversation context:

```bash
# Direct query
sidecar smart-search "What were the pricing terms?"

# Pipe in conversation context from clipboard
pbpaste | sidecar smart-search --top 5

# JSON output for scripting
echo "project timeline milestones" | sidecar smart-search --json
```

Smart search uses AI (Claude Haiku) to judge whether search results are genuinely relevant — it won't return documents about "pricing" for Project A when you're asking about Project B.

## Supported Formats

| Format | Extractor | Dependency |
|--------|-----------|------------|
| PDF | pdf-parse | npm (JS-native) |
| DOCX | mammoth | npm (JS-native) |
| XLSX/XLS | SheetJS | npm (JS-native) |
| TXT/MD/code | fs.readFile | none |
| Everything else | Apache Tika | Docker or Java (opt-in) |

90% of users never need Docker or Java — JS-native extractors handle the common formats.

## macOS App

A menu bar app that lets you search and attach sidecar documents to any AI chat with a hotkey.

- **Cmd+J** — Search your knowledge base from any app
- Reads conversation context via Accessibility API
- Shows a floating document picker with AI-filtered results
- One-click attach files to Claude, ChatGPT, or any chat
- Preview documents inline before attaching

## Chrome Extension

Browser extension for injecting document context into AI chat conversations.

- Works on claude.ai, chatgpt.com, gemini.google.com
- **Cmd+J** to trigger smart search
- Extracts full conversation history from the page DOM
- Injects relevant document context automatically

## Configuration (`.sidecarrc`)

Create a `.sidecarrc` file in your project root:

```json
{
  "include": ["**/*.pdf", "**/*.docx", "**/*.md"],
  "exclude": ["node_modules", ".git", "dist"],
  "maxFileSize": "100MB",
  "summarize": false,
  "provider": "claude",
  "concurrency": 4
}
```

CLI flags override `.sidecarrc` values.

## AI Summarization

Three providers:

- **`claude`** (default) — Uses `claude -p` CLI, free with Max subscription
- **`ollama`** — Any local model via localhost:11434
- **`openai-compatible`** — Any OpenAI-compatible API via `--api-url`

```bash
sidecar scan . --summarize
sidecar scan . --summarize --provider ollama --model llama3.2
```

## Privacy

- All document processing happens locally on your machine
- No data is sent to external services (unless you opt into AI summarization)
- Smart search uses Claude Haiku for relevance filtering — only document titles and summaries are sent, never full content
- Fully self-hosted with Ollama for zero external dependencies

## License

MIT — Built by [UPLO](https://uplo.ai)
