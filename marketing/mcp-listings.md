# MCP Directory Listings

Ready-to-submit descriptions for MCP server directories.

---

## mcp.so

**Title:** Sidecar — Local Document Search

**Short Description:**
Search your local documents from Claude, Cursor, or any MCP client. Scans PDFs, DOCX, XLSX, and 1,400+ formats into structured markdown, then serves them via keyword and AI-powered search. Privacy-first — nothing leaves your machine.

**Long Description:**
Sidecar turns your local documents into a searchable knowledge base that any MCP-compatible AI client can query. It extracts text from PDFs, DOCX, XLSX, and 1,400+ other formats, generates structured `.sidecar.md` companion files, and indexes everything for fast retrieval.

The MCP server exposes four tools:

- **sidecar_search** — BM25 keyword search across all indexed documents. Fast, precise, works offline.
- **sidecar_smart_search** — AI-powered contextual search that understands what you're actually looking for and filters out irrelevant results.
- **sidecar_read** — Read the full contents of any `.sidecar.md` file, giving your AI assistant the complete extracted text and metadata.
- **sidecar_status** — Check which directories are tracked, how many files are indexed, and whether any sidecars are stale.

Setup takes 30 seconds: `npm install -g uplo-sidecar`, scan a folder with `sidecar scan ~/Documents`, then add the server to your MCP client config. Works with Claude Desktop, Claude Code, Cursor, Windsurf, and any MCP-compatible tool.

All document processing happens locally. No data is sent to external services unless you opt into AI summarization. JS-native extractors handle PDFs, DOCX, and XLSX with zero external dependencies — no Docker or Java required for common formats.

**Category:** Knowledge & Memory

**GitHub URL:** https://github.com/RooJenkins/sidecar

**npm:** uplo-sidecar

**License:** MIT

---

## Smithery

**Title:** Sidecar — Local Document Search

**Short Description:**
Search your local documents from Claude, Cursor, or any MCP client. Indexes PDFs, DOCX, XLSX, and 1,400+ formats into structured markdown with keyword and AI-powered search. Privacy-first — all processing stays on your machine.

**Long Description:**
Sidecar makes your local files searchable by AI. It scans folders of documents, extracts their contents into structured `.sidecar.md` companion files, builds a search index, and serves results through four MCP tools:

- **sidecar_search** — BM25 keyword search across indexed documents.
- **sidecar_smart_search** — AI-powered contextual search with relevance filtering. Understands conversation context so it returns documents that actually matter, not just keyword matches.
- **sidecar_read** — Read the full extracted contents and metadata of any sidecar file.
- **sidecar_status** — Check tracking status, index health, and stale file counts for a directory.

### Quick Setup

```bash
npm install -g uplo-sidecar
sidecar scan ~/Documents
sidecar index ~/Documents
```

Then add to your MCP client:

```json
{
  "mcpServers": {
    "sidecar": {
      "command": "sidecar-mcp"
    }
  }
}
```

Or for Claude Code: `claude mcp add sidecar -- sidecar mcp`

### Key Features

- Handles PDFs, DOCX, XLSX natively — no Docker or Java needed
- Apache Tika support for 1,400+ additional formats (optional)
- AI summarization via Claude CLI, Ollama, or any OpenAI-compatible API
- Watch mode for automatic re-indexing on file changes
- All processing local — documents never leave your machine

**Category:** Knowledge & Memory

**GitHub URL:** https://github.com/RooJenkins/sidecar

**npm:** uplo-sidecar

**License:** MIT

---

## awesome-mcp-servers (GitHub PR Entry)

Add to the **Knowledge & Memory** section (or equivalent category in the list):

```markdown
- [Sidecar](https://github.com/RooJenkins/sidecar) - Search your local documents from any MCP client. Scans PDFs, DOCX, XLSX, and 1,400+ formats into structured markdown, then serves keyword search (`sidecar_search`), AI-powered contextual search (`sidecar_smart_search`), full document reading (`sidecar_read`), and status checking (`sidecar_status`). Privacy-first — all processing stays on your machine. `npm install -g uplo-sidecar`
```

### PR Title

`Add Sidecar — local document search MCP server`

### PR Body

Adds [Sidecar](https://github.com/RooJenkins/sidecar), an MCP server for searching local documents from Claude Desktop, Cursor, or any MCP client.

- Scans PDFs, DOCX, XLSX, and 1,400+ formats into structured `.sidecar.md` files
- Four tools: BM25 keyword search, AI-powered smart search, document reading, status checking
- JS-native extractors for common formats — no Docker or Java required
- Privacy-first: all document processing happens locally
- Install: `npm install -g uplo-sidecar`
- License: MIT
