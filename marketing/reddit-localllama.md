# Sidecar: local-first document search for AI agents — full Ollama support, nothing leaves your machine

**r/LocalLLaMA**

---

I built a tool for making local documents searchable by LLMs, and I wanted to share it here because it was designed with the self-hosted crowd in mind.

**What it does**: Scans your documents (PDF, DOCX, XLSX, 1400+ formats), extracts text and metadata, and generates structured `.sidecar.md` companion files. Then indexes them for search. The whole pipeline runs locally.

```bash
npm install -g uplo-sidecar
sidecar scan ~/Documents
sidecar index ~/Documents
```

**Ollama integration**: AI summarization and smart search can run entirely through Ollama. Zero external API calls.

```bash
sidecar scan ~/Documents --summarize --provider ollama --model llama3.2
```

This generates summaries, key points, entities, and topic tags for each document — all processed by your local model.

**What stays local**:
- Document extraction — JS-native parsers for PDF, DOCX, XLSX. No cloud APIs.
- Search index — BM25 index built and stored on disk.
- AI summarization — Ollama by default, or any OpenAI-compatible local endpoint via `--api-url`.
- The `.sidecar.md` files themselves — plain markdown, no proprietary format, no lock-in.

**MCP server**: Exposes your document index as an MCP server (`sidecar mcp`). Works with Claude Desktop, Cursor, or anything that speaks MCP. If you're running a local MCP-compatible client, this slots right in.

**No Docker required for common formats**: PDF, DOCX, XLSX are handled by JS-native libraries bundled with the package. Apache Tika (Docker or local Java) is only needed for exotic formats and is entirely optional.

The generated `.sidecar.md` files are just markdown. You can read them, grep them, feed them to whatever local model you want, or commit them to a repo. No database, no daemon, no phone-home.

There's also a macOS menu bar app (Cmd+J hotkey for searching and injecting docs into any chat) and a Chrome extension, but the CLI is the core.

MIT licensed. The whole thing is on GitHub: https://github.com/RooJenkins/sidecar

Happy to answer questions about the architecture or Ollama integration.
