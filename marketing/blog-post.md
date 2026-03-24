# How I Made 10,000 Documents Searchable by Claude in 5 Minutes

I have about 10,000 documents across my laptop. PDFs from clients, DOCX specs from teammates, spreadsheets from finance, markdown notes from three years of projects. All sitting in folders, completely invisible to every AI tool I use.

That's the fundamental problem with AI assistants today: they can't see your local files. Claude doesn't know about the proposal you wrote last week. ChatGPT can't reference the contract sitting in your Downloads folder. You end up copy-pasting fragments into chat windows, losing context, and wondering why the AI keeps giving you generic answers when you have thousands of pages of relevant material right there on your machine.

I built [Sidecar](https://github.com/RooJenkins/sidecar) to fix this. It scans your documents, generates structured companion files that AI agents can actually consume, and makes everything searchable with a single command. Here's how it works.

## The Core Idea: Companion Files for Every Document

Sidecar creates a `.sidecar.md` file next to each of your documents. Think of it as a machine-readable summary card:

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

Markdown is the universal language of LLMs. Every AI agent can read it. No special adapters, no proprietary formats, no vector database to maintain.

## Step 1: Install and Scan

```bash
npm install -g uplo-sidecar
```

Then point it at a folder:

```bash
sidecar scan ~/Documents
```

That's it. Sidecar walks the directory tree, extracts text from PDFs, DOCX, XLSX, and plain text files using JS-native libraries (no Docker, no Java, no external dependencies for common formats), and writes a `.sidecar.md` file alongside each original.

For my 10,000 documents, this took about five minutes. The JS-native extractors handle PDF, DOCX, and XLSX out of the box. If you have exotic formats (CAD files, old WordPerfect docs, whatever), Sidecar can optionally use Apache Tika for 1,400+ additional formats, but 90% of users will never need it.

Want AI summaries too? Add the `--summarize` flag:

```bash
sidecar scan ~/Documents --summarize
```

This uses the Claude CLI under the hood (free with a Max subscription), or you can point it at a local Ollama instance for fully offline summarization:

```bash
sidecar scan ~/Documents --summarize --provider ollama --model llama3.2
```

## Step 2: Build the Search Index

```bash
sidecar index ~/Documents
```

This builds a BM25 search index from all your sidecar files. Fast, local, no external services.

## Step 3: Search Your Documents

Now you can search across everything:

```bash
sidecar search "project timeline"
```

This returns ranked results with file paths, relevance scores, and snippets. Good for straightforward keyword queries.

But the real power is smart search.

## Step 4: Smart Search (The Game Changer)

```bash
sidecar smart-search "What did we propose for the platform migration?"
```

Smart search does two things regular search can't. First, it understands natural language queries instead of just matching keywords. Second, it uses Claude Haiku to judge whether each result is *actually* relevant to your question.

This matters more than you'd think. A keyword search for "pricing" returns every document that mentions the word. Smart search understands that you're asking about *Project B's pricing terms* and filters out the twelve documents about Project A's pricing that happened to match.

You can also pipe in conversation context for even better results:

```bash
pbpaste | sidecar smart-search --top 5
```

This reads your clipboard (say, a conversation you're having with Claude) and finds the documents most relevant to what you're actually discussing.

## The MCP Server: Give Claude Direct Access to Your Documents

Here's where it gets really good. Sidecar includes an MCP (Model Context Protocol) server, which means Claude can search your documents directly during a conversation without you lifting a finger.

For Claude Code, setup is one command:

```bash
claude mcp add sidecar -- sidecar mcp
```

For Claude Desktop or Cursor, add this to your config:

```json
{
  "mcpServers": {
    "sidecar": {
      "command": "sidecar-mcp"
    }
  }
}
```

Once connected, Claude gets four tools: `sidecar_search`, `sidecar_smart_search`, `sidecar_read`, and `sidecar_status`. When you ask it a question about your documents, it searches your index, reads the relevant sidecar files, and gives you answers grounded in your actual data.

No more copy-pasting. No more "here's the relevant section from page 47." Claude just knows about your files.

## Beyond the CLI: macOS App and Chrome Extension

If you don't live in the terminal, Sidecar also has a macOS menu bar app and a Chrome extension.

The macOS app gives you a global **Cmd+J** hotkey that opens a floating search panel. It reads the conversation context from whatever app you're in (via the Accessibility API), finds relevant documents, and lets you attach them with one click. Works with Claude, ChatGPT, or any text input.

The Chrome extension does the same thing inside your browser. It works on claude.ai, chatgpt.com, and gemini.google.com -- it reads the conversation from the page, runs a smart search, and injects the relevant document context directly into the chat.

## Privacy: Everything Stays Local

I want to be clear about what happens with your data, because this matters:

- All document scanning and text extraction happens locally on your machine.
- The search index is stored locally.
- No data is sent to external services unless you opt into AI summarization.
- Smart search sends only document titles and short summaries to Claude Haiku for relevance filtering -- never the full document content.
- If you want zero external calls, use Ollama for summarization and skip smart search. Fully air-gapped.

Your documents never leave your machine. That was a non-negotiable design constraint.

## Watch Mode: Keep Everything Up to Date

Documents change. New files arrive. Sidecar handles this with watch mode:

```bash
sidecar scan ~/Documents --watch
```

It monitors the directory for changes and regenerates sidecar files as needed. Set it up as a background process and forget about it.

## Get Started

Install:

```bash
npm install -g uplo-sidecar
```

Scan, index, and search:

```bash
sidecar scan ~/Documents
sidecar index ~/Documents
sidecar smart-search "What's our Q1 revenue forecast?"
```

Hook it up to Claude:

```bash
claude mcp add sidecar -- sidecar mcp
```

The project is MIT licensed and open source: [github.com/RooJenkins/sidecar](https://github.com/RooJenkins/sidecar)

More info at [uplo.ai/sidecar](https://uplo.ai/sidecar).

If you have thousands of documents sitting on your laptop that your AI assistant can't see, give Sidecar five minutes. You'll wonder how you worked without it.
