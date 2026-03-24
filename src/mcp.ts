#!/usr/bin/env node

/**
 * Sidecar MCP Server
 *
 * Exposes sidecar search and scan capabilities via the Model Context Protocol.
 * Use with Claude Desktop, Claude Code, Cursor, Windsurf, etc.
 *
 * Usage:
 *   sidecar mcp          (stdio transport)
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { search } from "./search/index.js";
import { smartSearch } from "./smart-search.js";
import { getStatus } from "./status.js";
import { readFile } from "node:fs/promises";

const server = new McpServer({
  name: "sidecar",
  version: "0.2.0",
});

// Tool: search
server.tool(
  "sidecar_search",
  "Search your document knowledge base using BM25 keyword ranking. Returns the most relevant documents matching the query.",
  {
    query: z.string().describe("Search query — keywords or natural language"),
    top: z.number().optional().default(5).describe("Number of results to return (default: 5)"),
  },
  async ({ query, top }) => {
    const output = await search(query, top);

    if (output.results.length === 0) {
      return {
        content: [
          {
            type: "text" as const,
            text: "No results found. Make sure you've run `sidecar index` first.",
          },
        ],
      };
    }

    const text = output.results
      .map(
        (r, i) =>
          `**${i + 1}. ${r.title}** (score: ${r.score.toFixed(2)})\n` +
          `   File: ${r.file}\n` +
          `   ${r.summary || r.snippet || ""}\n` +
          (r.topics.length ? `   Topics: ${r.topics.join(", ")}` : "")
      )
      .join("\n\n");

    return {
      content: [{ type: "text" as const, text }],
    };
  }
);

// Tool: smart-search
server.tool(
  "sidecar_smart_search",
  "AI-powered contextual search. Finds documents relevant to the current conversation context. Uses BM25 + AI relevance filtering.",
  {
    context: z
      .string()
      .describe(
        "Conversation context or question — the AI uses this to judge document relevance"
      ),
    top: z.number().optional().default(5).describe("Max results to return"),
  },
  async ({ context, top }) => {
    const output = await smartSearch(context, { maxResults: top });

    if (output.results.length === 0) {
      return {
        content: [
          {
            type: "text" as const,
            text: "No relevant documents found for this context.",
          },
        ],
      };
    }

    const text = output.results
      .map(
        (r, i) =>
          `**${i + 1}. ${r.title}** (score: ${r.score.toFixed(2)})\n` +
          `   File: ${r.file}\n` +
          `   ${r.summary || r.snippet || ""}\n` +
          (r.topics.length ? `   Topics: ${r.topics.join(", ")}` : "")
      )
      .join("\n\n");

    return {
      content: [{ type: "text" as const, text }],
    };
  }
);

// Tool: read sidecar file
server.tool(
  "sidecar_read",
  "Read the full contents of a .sidecar.md file for a given document. Use after searching to get the complete extracted content.",
  {
    file: z
      .string()
      .describe(
        "Path to the source file or its .sidecar.md companion"
      ),
  },
  async ({ file }) => {
    const sidecarPath = file.endsWith(".sidecar.md")
      ? file
      : file + ".sidecar.md";

    try {
      const content = await readFile(sidecarPath, "utf-8");
      return {
        content: [{ type: "text" as const, text: content }],
      };
    } catch {
      return {
        content: [
          {
            type: "text" as const,
            text: `Could not read sidecar file: ${sidecarPath}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// Tool: status
server.tool(
  "sidecar_status",
  "Show the status of sidecar-tracked files in a directory — counts, stale files, disk usage.",
  {
    path: z.string().describe("Directory path to check status for"),
  },
  async ({ path }) => {
    const status = await getStatus(path);

    const lines = [
      `**Sidecar Status: ${path}**`,
      `Total files: ${status.totalFiles}`,
      `Tracked (with sidecars): ${status.trackedFiles}`,
      `Missing sidecars: ${status.missingFiles}`,
      `Stale sidecars: ${status.staleFiles}`,
      `Sidecar disk usage: ${(status.sidecarDiskBytes / 1024).toFixed(1)} KB`,
    ];

    return {
      content: [{ type: "text" as const, text: lines.join("\n") }],
    };
  }
);

// Resource: index stats
server.resource("index-stats", "sidecar://index/stats", async () => {
  try {
    const { loadIndex } = await import("./search/indexer.js");
    const index = await loadIndex();
    if (!index) {
      return {
        contents: [
          {
            uri: "sidecar://index/stats",
            mimeType: "application/json",
            text: JSON.stringify({ indexed: false, documentCount: 0 }),
          },
        ],
      };
    }
    return {
      contents: [
        {
          uri: "sidecar://index/stats",
          mimeType: "application/json",
          text: JSON.stringify({
            indexed: true,
            documentCount: index.documentCount,
            builtAt: index.builtAt,
            version: index.version,
          }),
        },
      ],
    };
  } catch {
    return {
      contents: [
        {
          uri: "sidecar://index/stats",
          mimeType: "application/json",
          text: JSON.stringify({ indexed: false, error: "Failed to load index" }),
        },
      ],
    };
  }
});

export async function startMcpServer() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
