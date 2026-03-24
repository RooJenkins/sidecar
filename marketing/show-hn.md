# Show HN: Sidecar – Make your local files searchable by AI agents via MCP

I built a CLI tool that scans your documents (PDF, DOCX, XLSX, 1400+ formats) and generates structured `.sidecar.md` companion files next to each original. Then it serves them to AI agents through an MCP server.

**The problem**: AI tools can't read your local files. You end up copy-pasting content into chat windows, losing context, and repeating yourself.

**What Sidecar does**:

1. `sidecar scan ~/Documents` — extracts text and metadata, writes a `.sidecar.md` next to each file
2. `sidecar index ~/Documents` — builds a BM25 search index
3. `sidecar mcp` — exposes your knowledge base as an MCP server

Any MCP-compatible client (Claude Desktop, Claude Code, Cursor) can then search and read your documents directly. Claude asks "what were the pricing terms?" and Sidecar finds the right PDF.

**Smart search**: BM25 for keywords, plus an AI relevance filter (Claude Haiku) that understands conversation context — it won't return docs about Project A when you're asking about Project B.

**Privacy**: All document processing is local. The AI relevance filter only sends document titles and brief summaries, never full content. For fully offline operation, use Ollama instead of Claude for summarization.

There's also a macOS menu bar app (Cmd+J to search and inject docs into any AI chat) and a Chrome extension for claude.ai/chatgpt.com/gemini.

MIT licensed. Free core, Pro tier for AI-powered features.

```
npm install -g uplo-sidecar
```

GitHub: https://github.com/RooJenkins/sidecar

Website: https://uplo.ai/sidecar
