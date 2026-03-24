# I built an MCP server that gives Claude access to all your local documents

**r/ClaudeAI**

---

I kept running into the same problem: I have hundreds of PDFs, contracts, specs, and reports on my machine, and every time I need Claude's help with them, I'm manually copy-pasting content into the chat. It's tedious and I always lose context.

So I built **Sidecar** — a CLI that scans your documents and makes them searchable by Claude through MCP.

Here's the workflow:

```bash
npm install -g uplo-sidecar
sidecar scan ~/Documents
sidecar index ~/Documents
```

This generates `.sidecar.md` companion files (structured markdown with extracted text + metadata) and builds a search index. Then you add it as an MCP server:

**Claude Code:**
```bash
claude mcp add sidecar -- sidecar mcp
```

**Claude Desktop:**
```json
{
  "mcpServers": {
    "sidecar": {
      "command": "sidecar-mcp"
    }
  }
}
```

Now Claude can search your documents mid-conversation. It exposes `sidecar_search` (BM25 keyword search) and `sidecar_smart_search` (AI-powered contextual search that uses Haiku to filter results based on your actual conversation).

The smart search is the part I'm most happy with. If you're discussing Project B and ask about "pricing," it won't pull up pricing docs from Project A. It understands context.

**macOS menu bar app**: There's also a native app — press **Cmd+J** from any app and it opens a floating search panel. It reads your current conversation via Accessibility API and shows the most relevant documents. One click to inject them into Claude (or ChatGPT, or Gemini).

**Chrome extension**: Same Cmd+J workflow but in the browser — works on claude.ai, chatgpt.com, and gemini.google.com.

Supports PDF, DOCX, XLSX natively (no dependencies), plus 1400+ formats via Apache Tika if you need them. All processing is local — documents never leave your machine.

MIT licensed, free core. GitHub: https://github.com/RooJenkins/sidecar
