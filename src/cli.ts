#!/usr/bin/env node

import { Command } from "commander";
import { resolve } from "node:path";
import chalk from "chalk";
import ora from "ora";
import { scan, scanSingleFile } from "./scanner.js";
import { writeSidecarFile } from "./markdown.js";
import { loadConfig, mergeConfigWithOptions } from "./config.js";
import { getStatus } from "./status.js";
import { resolveProvider } from "./providers/index.js";
import { summarizeSingle } from "./summarizer.js";
import { setTikaExtractor } from "./extractors/index.js";
import { createTikaExtractor, isTikaAvailable } from "./extractors/tika.js";
import { ensureTika, stopTika } from "./tika-lifecycle.js";
import { initGitIntegration } from "./git.js";
import { generateIndexes } from "./indexer.js";
import { cleanSidecars } from "./clean.js";
import { buildIndex, saveIndex, search } from "./search/index.js";
import { rerankWithEmbeddings } from "./search/embeddings.js";
import { smartSearch } from "./smart-search.js";
import type { SummaryProvider } from "./providers/types.js";
import type { SummaryResult } from "./providers/types.js";
import type { ScanOptions } from "./types.js";

const program = new Command();

program
  .name("sidecar")
  .description(
    "Generate AI-ready .sidecar.md companion files for any document"
  )
  .version("0.1.0");

// ── scan command ──────────────────────────────────────────────────────────

program
  .command("scan")
  .description("Scan folder and generate sidecar files")
  .argument("<path>", "Directory to scan")
  .option("--include <globs...>", "File patterns to include")
  .option("--exclude <globs...>", "File patterns to exclude")
  .option(
    "--max-file-size <size>",
    "Skip files larger than this (default: 100MB)"
  )
  .option("--output-dir <dir>", "Write sidecars to mirrored directory instead of alongside source files")
  .option("--no-tika", "JS-native extractors only, skip Tika")
  .option("--dry-run", "Show what would be processed without writing files")
  .option("--concurrency <n>", "Parallel processing limit", "4")
  .option("--summarize", "Enable AI summarization")
  .option("--provider <name>", "AI provider: claude (default), ollama, openai-compatible")
  .option("--model <model>", "Model name (default varies by provider)")
  .option("--api-url <url>", "API endpoint for openai-compatible provider")
  .option("--api-key <key>", "API key for openai-compatible provider")
  .option("--watch", "Watch mode — re-process on file change")
  .option("-v, --verbose", "Verbose logging")
  .option("--json", "JSON output for scripting")
  .option("--json-stream", "Newline-delimited JSON events (for desktop app)")
  .action(async (targetPath: string, opts: Record<string, unknown>) => {
    const resolvedPath = resolve(targetPath);
    const config = await loadConfig(resolvedPath);

    const cliOptions: ScanOptions = {
      include: opts.include as string[] | undefined,
      exclude: opts.exclude as string[] | undefined,
      maxFileSize: parseFileSize(opts.maxFileSize as string | undefined),
      outputDir: opts.outputDir ? resolve(opts.outputDir as string) : undefined,
      noTika: opts.tika === false,
      summarize: opts.summarize as boolean,
      provider: opts.provider as string | undefined,
      model: opts.model as string | undefined,
      apiUrl: opts.apiUrl as string | undefined,
      dryRun: opts.dryRun as boolean,
      concurrency: parseInt(String(opts.concurrency), 10),
      watch: opts.watch as boolean,
      verbose: opts.verbose as boolean,
      json: opts.json as boolean,
    };

    const options = mergeConfigWithOptions(config, cliOptions);
    const isJsonStream = opts.jsonStream as boolean;
    const isJson = options.json || isJsonStream;
    const verbose = options.verbose;

    const emit = (obj: Record<string, unknown>) => {
      if (isJsonStream) console.log(JSON.stringify(obj));
    };

    // Resolve AI provider if summarization enabled
    let summaryProvider: SummaryProvider | undefined;
    if (options.summarize) {
      summaryProvider = resolveProvider({
        provider: options.provider,
        model: options.model,
        apiUrl: options.apiUrl,
        apiKey: opts.apiKey as string | undefined,
      });
      if (!isJson) {
        console.log(chalk.dim(`  AI provider: ${summaryProvider.name}\n`));
      }
    }

    // Set up Tika fallback extractor if not disabled
    if (!options.noTika) {
      const tikaUrl = options.tikaUrl;
      const tikaReady = await isTikaAvailable(tikaUrl);
      if (tikaReady) {
        setTikaExtractor(createTikaExtractor(tikaUrl));
        if (verbose && !isJson) {
          console.log(chalk.dim("  Tika available — exotic formats enabled\n"));
        }
      } else if (verbose && !isJson) {
        console.log(chalk.dim("  Tika not detected — using JS-native extractors only\n"));
      }
    }

    // Track summaries for index generation
    const fileSummaries = new Map<string, SummaryResult>();

    const spinner = isJson ? null : ora({ text: "Scanning...", color: "cyan" }).start();
    const startTime = Date.now();

    const result = await scan(resolvedPath, options, {
      onFile: async (file) => {
        if (spinner) spinner.stop();

        if (options.dryRun) {
          if (!isJson) {
            console.log(chalk.dim(`  [dry-run] Would process: ${file.fileName}`));
          }
          emit({ event: "file", fileName: file.fileName, sourcePath: file.sourcePath, extractor: file.extractor, status: "dry-run" });
        } else {
          let summary;
          if (summaryProvider && file.content.trim()) {
            if (!isJsonStream) {
              process.stdout.write(`  ${chalk.cyan("⟳")} Summarizing ${chalk.bold(file.fileName)}...`);
            }
            emit({ event: "summary", fileName: file.fileName, status: "start" });
            try {
              summary = await summarizeSingle(file, summaryProvider);
              if (!isJsonStream) {
                process.stdout.write(` ${chalk.green("done")}\n`);
              }
              emit({ event: "summary", fileName: file.fileName, status: "done" });
            } catch (err) {
              const msg = err instanceof Error ? err.message : String(err);
              if (!isJsonStream) {
                process.stdout.write(` ${chalk.red("failed")}: ${chalk.dim(msg)}\n`);
              }
              emit({ event: "summary", fileName: file.fileName, status: "failed", message: msg });
            }
          }

          if (summary) {
            fileSummaries.set(file.sourcePath, summary);
          }
          const sidecarPath = await writeSidecarFile(file, summary, {
            rootPath: resolvedPath,
            outputDir: options.outputDir,
          });
          if (!isJsonStream) {
            console.log(`  ${chalk.green("✓")} ${chalk.bold(file.fileName)} ${chalk.dim("→")} ${chalk.dim(sidecarPath)}`);
          }
          emit({ event: "file", fileName: file.fileName, sourcePath: file.sourcePath, extractor: file.extractor, mimeType: file.mimeType, status: "processed" });
        }

        if (spinner) spinner.start("Scanning...");
      },
      onSkip: (filePath, reason) => {
        emit({ event: "skip", sourcePath: filePath, reason });
        if (verbose && !isJsonStream) {
          if (spinner) spinner.stop();
          console.log(`  ${chalk.yellow("⊘")} ${chalk.dim(`Skipped: ${filePath} (${reason})`)}`);
          if (spinner) spinner.start("Scanning...");
        }
      },
      onError: (filePath, error) => {
        emit({ event: "error", sourcePath: filePath, message: error.message });
        if (!isJsonStream) {
          if (spinner) spinner.stop();
          console.error(`  ${chalk.red("✗")} ${chalk.red(`Error: ${filePath}`)} ${chalk.dim(`— ${error.message}`)}`);
          if (spinner) spinner.start("Scanning...");
        }
      },
    });

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

    if (spinner) spinner.stop();

    if (isJsonStream) {
      emit({ event: "done", processed: result.processed, skipped: result.skipped, errors: result.errors, elapsed_seconds: parseFloat(elapsed) });
    } else if (isJson) {
      console.log(
        JSON.stringify({
          processed: result.processed,
          skipped: result.skipped,
          errors: result.errors,
          elapsed_seconds: parseFloat(elapsed),
        })
      );
    } else {
      console.log("");
      console.log(
        chalk.bold("Done.") +
        ` ${chalk.green(`${result.processed} processed`)}, ` +
        `${chalk.yellow(`${result.skipped} skipped`)}, ` +
        `${chalk.red(`${result.errors} errors`)} ` +
        chalk.dim(`(${elapsed}s)`)
      );
      console.log("");
    }

    // Generate SIDECAR.md indexes
    if (!options.dryRun && result.processed > 0) {
      if (spinner) spinner.stop();
      if (!isJsonStream && !isJson) {
        process.stdout.write(chalk.dim("  Generating indexes..."));
      }

      const indexPaths = await generateIndexes(
        resolvedPath,
        result.files,
        fileSummaries,
        {
          provider: summaryProvider,
          onIndex: (indexPath) => {
            emit({ event: "index", sourcePath: indexPath, status: "written" });
          },
        }
      );

      if (!isJsonStream && !isJson) {
        console.log(chalk.dim(` ${indexPaths.length} SIDECAR.md file(s) written`));
        console.log("");
      }
    }

    if (options.watch && !options.dryRun) {
      await startWatchMode(resolvedPath, options, summaryProvider);
    }
  });

// ── status command ────────────────────────────────────────────────────────

program
  .command("status")
  .description("Show stats: tracked files, stale sidecars, disk usage")
  .argument("<path>", "Directory to check")
  .option("--output-dir <dir>", "Look for sidecars in mirrored directory")
  .option("--json", "JSON output for scripting")
  .action(async (targetPath: string, opts: Record<string, unknown>) => {
    const resolvedPath = resolve(targetPath);
    const outputDir = opts.outputDir ? resolve(opts.outputDir as string) : undefined;
    const isJson = opts.json as boolean;

    const spinner = isJson ? null : ora({ text: "Checking status...", color: "cyan" }).start();

    const status = await getStatus(resolvedPath, outputDir);

    if (spinner) spinner.stop();

    if (isJson) {
      console.log(JSON.stringify(status, null, 2));
      return;
    }

    console.log("");
    console.log(chalk.bold("Sidecar Status"));
    console.log(chalk.dim("─".repeat(40)));
    console.log(`  Total source files:  ${chalk.bold(String(status.totalFiles))}`);
    console.log(`  With sidecars:       ${chalk.green(String(status.trackedFiles))}`);
    console.log(`  Missing sidecars:    ${status.missingFiles > 0 ? chalk.yellow(String(status.missingFiles)) : chalk.dim("0")}`);
    console.log(`  Stale sidecars:      ${status.staleFiles > 0 ? chalk.red(String(status.staleFiles)) : chalk.dim("0")}`);
    console.log(chalk.dim("─".repeat(40)));
    console.log(`  Sidecar disk usage:  ${chalk.dim(formatBytes(status.sidecarDiskBytes))}`);
    console.log(`  Cache disk usage:    ${chalk.dim(formatBytes(status.cacheDiskBytes))}`);

    if (Object.keys(status.byExtractor).length > 0) {
      console.log(chalk.dim("─".repeat(40)));
      console.log(chalk.bold("  By extractor:"));
      for (const [name, count] of Object.entries(status.byExtractor)) {
        console.log(`    ${chalk.cyan(name)}: ${count}`);
      }
    }

    console.log("");

    if (status.staleFiles > 0) {
      console.log(chalk.yellow(`  ⚠ ${status.staleFiles} sidecar(s) may be outdated. Run ${chalk.bold("sidecar scan")} to update.`));
      console.log("");
    }
    if (status.missingFiles > 0) {
      console.log(chalk.dim(`  ℹ ${status.missingFiles} file(s) have no sidecar yet. Run ${chalk.bold("sidecar scan")} to generate.`));
      console.log("");
    }
  });

// ── clean command ─────────────────────────────────────────────────────────

program
  .command("clean")
  .description("Remove all .sidecar.md files, SIDECAR.md indexes, and cache")
  .argument("<path>", "Directory to clean")
  .option("--output-dir <dir>", "Remove sidecars from mirrored directory")
  .option("--json", "JSON output")
  .action(async (targetPath: string, opts: Record<string, unknown>) => {
    const resolvedPath = resolve(targetPath);
    const outputDir = opts.outputDir ? resolve(opts.outputDir as string) : undefined;
    const isJson = opts.json as boolean;

    if (!isJson) {
      const spinner = ora({ text: "Cleaning...", color: "cyan" }).start();
      const result = await cleanSidecars(resolvedPath, outputDir);
      spinner.stop();

      console.log("");
      console.log(`  ${chalk.green("✓")} Removed ${chalk.bold(String(result.sidecarFiles))} sidecar file(s)`);
      console.log(`  ${chalk.green("✓")} Removed ${chalk.bold(String(result.indexFiles))} index file(s)`);
      if (result.cacheRemoved) {
        console.log(`  ${chalk.green("✓")} Removed .sidecar/ cache`);
      }
      console.log(chalk.dim(`  Freed ${formatBytes(result.bytesFreed)}`));
      console.log("");
    } else {
      const result = await cleanSidecars(resolvedPath, outputDir);
      console.log(JSON.stringify(result));
    }
  });

// ── init command ──────────────────────────────────────────────────────────

program
  .command("init")
  .description("Set up git pre-commit hook (advisory mode)")
  .action(async () => {
    const cwd = process.cwd();
    const result = await initGitIntegration(cwd);

    for (const msg of result.messages) {
      if (msg.startsWith("Not a git") || msg.startsWith("Failed") || msg.startsWith("Could not")) {
        console.log(`  ${chalk.red("✗")} ${msg}`);
      } else {
        console.log(`  ${chalk.green("✓")} ${msg}`);
      }
    }

    console.log("");
    if (result.hookInstalled) {
      console.log(chalk.dim("  The pre-commit hook will warn about stale sidecars."));
      console.log(chalk.dim("  It does NOT block commits or auto-stage files."));
      console.log("");
    }
  });

// ── tika command ──────────────────────────────────────────────────────────

program
  .command("tika-start")
  .description("Start Apache Tika server (Docker or JAR)")
  .option("--tika-url <url>", "Tika URL", "http://localhost:9998")
  .action(async (opts: Record<string, unknown>) => {
    const tikaUrl = opts.tikaUrl as string;
    const started = await ensureTika({
      tikaUrl,
      verbose: true,
      log: (msg) => console.log(`  ${chalk.dim(msg)}`),
    });

    if (started) {
      console.log(`\n  ${chalk.green("✓")} Tika is running at ${chalk.bold(tikaUrl)}\n`);
    } else {
      console.log(`\n  ${chalk.red("✗")} Failed to start Tika\n`);
      process.exit(1);
    }
  });

program
  .command("tika-stop")
  .description("Stop managed Tika server")
  .action(() => {
    stopTika();
    console.log(`  ${chalk.green("✓")} Tika stopped\n`);
  });

// ── index command ─────────────────────────────────────────────────────────

program
  .command("index")
  .description("Build/rebuild search index from .sidecar.md files")
  .argument("[paths...]", "Directories to index (default: current dir)")
  .option("--output-dir <dir>", "Look for sidecars in mirrored directory")
  .option("-v, --verbose", "List indexed documents")
  .option("--json", "JSON output")
  .action(async (paths: string[], opts: Record<string, unknown>) => {
    const outputDir = opts.outputDir ? resolve(opts.outputDir as string) : undefined;
    const resolvedPaths = outputDir
      ? [outputDir]
      : paths.length > 0
        ? paths.map((p) => resolve(p))
        : [resolve(".")];
    const isJson = opts.json as boolean;
    const verbose = opts.verbose as boolean;

    const spinner = isJson ? null : ora({ text: "Building search index...", color: "cyan" }).start();

    const index = await buildIndex(resolvedPaths);
    const indexPath = await saveIndex(index);

    if (spinner) {
      spinner.succeed(`Indexed ${index.documentCount} documents → ${indexPath}`);
    }

    if (isJson) {
      console.log(JSON.stringify({ documentCount: index.documentCount, indexPath, builtAt: index.builtAt }, null, 2));
    } else if (verbose) {
      for (const doc of index.documents) {
        console.log(chalk.dim("  •"), doc.title || doc.sourcePath);
      }
    }
  });

// ── search command ────────────────────────────────────────────────────────

program
  .command("search")
  .description("Search the sidecar knowledge base")
  .argument("<query>", "Search query")
  .option("--top <n>", "Number of results", "5")
  .option("--rerank", "Re-rank results using Ollama embeddings")
  .option("--json", "JSON output")
  .action(async (query: string, opts: Record<string, unknown>) => {
    const topN = opts.top ? parseInt(String(opts.top), 10) : 5;
    const isJson = opts.json as boolean;
    const rerank = opts.rerank as boolean;

    // BM25 search — fetch extra candidates if re-ranking
    const candidateCount = rerank ? Math.max(topN, 20) : topN;
    const output = await search(query, candidateCount);

    // Optional semantic re-ranking via Ollama embeddings
    if (rerank && output.results.length > 0) {
      try {
        output.results = await rerankWithEmbeddings(query, output.results);
        output.results = output.results.slice(0, topN);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (!isJson) {
          console.log(chalk.yellow("Re-ranking failed, showing BM25 results."), chalk.dim(msg));
        }
        output.results = output.results.slice(0, topN);
      }
    }

    if (output.results.length === 0) {
      if (isJson) {
        console.log(JSON.stringify(output, null, 2));
      } else {
        console.log(chalk.yellow("No results found."));
        console.log(chalk.dim("Have you run 'sidecar index <path>' first?"));
      }
      return;
    }

    if (isJson) {
      console.log(JSON.stringify(output, null, 2));
      return;
    }

    console.log(chalk.bold(`\n  Results for "${query}":\n`));
    for (const r of output.results) {
      const scoreColor = r.score >= 0.7 ? chalk.green : r.score >= 0.4 ? chalk.yellow : chalk.dim;
      console.log(`  ${scoreColor(`[${r.score.toFixed(2)}]`)} ${chalk.bold(r.title)}`);
      console.log(`         ${chalk.dim(r.file)}`);
      if (r.topics.length > 0) {
        console.log(`         ${chalk.cyan(r.topics.join(", "))}`);
      }
      if (r.snippet) {
        console.log(`         ${chalk.dim(r.snippet)}`);
      }
      console.log("");
    }
  });

// ── smart-search command ─────────────────────────────────────────────────

program
  .command("smart-search")
  .description("AI-powered search: analyzes context to find relevant documents")
  .argument("[query]", "Search query or conversation context (also reads from stdin)")
  .option("--top <n>", "Number of results", "5")
  .option("--model <model>", "Claude model for query extraction", "claude-haiku-4-5-20251001")
  .option("--json", "JSON output")
  .option("-v, --verbose", "Show extracted queries")
  .action(async (query: string | undefined, opts: Record<string, unknown>) => {
    const topN = opts.top ? parseInt(String(opts.top), 10) : 5;
    const isJson = opts.json as boolean;
    const verbose = opts.verbose as boolean;
    const model = opts.model as string;

    // Read from stdin if no query argument and stdin is piped
    let conversation = query || "";
    if (!conversation && !process.stdin.isTTY) {
      conversation = await new Promise<string>((resolve) => {
        const chunks: Buffer[] = [];
        process.stdin.on("data", (chunk) => chunks.push(chunk));
        process.stdin.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
        process.stdin.resume();
      });
    }

    if (!conversation.trim()) {
      console.error(chalk.red("No input provided. Pass a query argument or pipe text via stdin."));
      console.error(chalk.dim("  Example: echo 'What about pricing?' | sidecar smart-search"));
      console.error(chalk.dim("  Example: pbpaste | sidecar smart-search"));
      process.exit(1);
    }

    const spinner = isJson ? null : ora({ text: "Analyzing context...", color: "cyan" }).start();

    const output = await smartSearch(conversation, {
      maxResults: topN,
      model,
      verbose,
    });

    if (spinner) spinner.stop();

    if (output.results.length === 0) {
      if (isJson) {
        console.log(JSON.stringify(output, null, 2));
      } else {
        console.log(chalk.yellow("No results found."));
        console.log(chalk.dim("Have you run 'sidecar index <path>' first?"));
      }
      return;
    }

    if (isJson) {
      console.log(JSON.stringify(output, null, 2));
      return;
    }

    if (verbose) {
      console.log(chalk.dim(`  Queries: ${output.query}`));
      console.log("");
    }

    console.log(chalk.bold(`\n  Smart search results:\n`));
    for (const r of output.results) {
      const scoreColor = r.score >= 0.7 ? chalk.green : r.score >= 0.4 ? chalk.yellow : chalk.dim;
      console.log(`  ${scoreColor(`[${r.score.toFixed(2)}]`)} ${chalk.bold(r.title)}`);
      console.log(`         ${chalk.dim(r.file)}`);
      if (r.topics.length > 0) {
        console.log(`         ${chalk.cyan(r.topics.join(", "))}`);
      }
      if (r.snippet) {
        console.log(`         ${chalk.dim(r.snippet)}`);
      }
      console.log("");
    }
  });

program.parse();

// ── watch mode ────────────────────────────────────────────────────────────

async function startWatchMode(
  targetPath: string,
  options: ScanOptions,
  summaryProvider?: SummaryProvider
): Promise<void> {
  const chokidar = await import("chokidar");

  console.log(chalk.cyan("Watching for changes...") + chalk.dim(" (Ctrl+C to stop)\n"));

  const ignored = [
    /(^|[/\\])\./,
    /\.sidecar\.md$/,
    /node_modules/,
    /\.sidecar\//,
  ];

  const watcher = chokidar.watch(targetPath, {
    ignored,
    persistent: true,
    ignoreInitial: true,
    awaitWriteFinish: {
      stabilityThreshold: 500,
      pollInterval: 100,
    },
  });

  const pending = new Map<string, NodeJS.Timeout>();

  const handleChange = (filePath: string) => {
    const existing = pending.get(filePath);
    if (existing) clearTimeout(existing);

    pending.set(
      filePath,
      setTimeout(async () => {
        pending.delete(filePath);

        if (!options.json) {
          console.log(`  ${chalk.cyan("↻")} Changed: ${chalk.dim(filePath)}`);
        }

        await scanSingleFile(filePath, targetPath, options, {
          onFile: async (file) => {
            let summary;
            if (summaryProvider && file.content.trim()) {
              try {
                summary = await summarizeSingle(file, summaryProvider);
              } catch {
                // skip summary on error in watch mode
              }
            }
            const sidecarPath = await writeSidecarFile(file, summary, {
              rootPath: targetPath,
              outputDir: options.outputDir,
            });
            if (!options.json) {
              console.log(`  ${chalk.green("✓")} ${chalk.bold(file.fileName)} ${chalk.dim("→")} ${chalk.dim(sidecarPath)}`);
            }
          },
          onSkip: (fp, reason) => {
            if (options.verbose && !options.json) {
              console.log(`  ${chalk.yellow("⊘")} ${chalk.dim(`Skipped: ${fp} (${reason})`)}`);
            }
          },
          onError: (fp, error) => {
            if (!options.json) {
              console.error(`  ${chalk.red("✗")} ${chalk.red(fp)} ${chalk.dim(`— ${error.message}`)}`);
            }
          },
        });
      }, 300)
    );
  };

  watcher.on("change", handleChange);
  watcher.on("add", handleChange);

  await new Promise(() => {});
}

// ── helpers ───────────────────────────────────────────────────────────────

function parseFileSize(size: string | undefined): number | undefined {
  if (!size) return undefined;
  const match = size.match(/^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb)$/i);
  if (!match) return undefined;
  const value = parseFloat(match[1]);
  const unit = match[2].toLowerCase();
  const multipliers: Record<string, number> = {
    b: 1,
    kb: 1024,
    mb: 1024 * 1024,
    gb: 1024 * 1024 * 1024,
  };
  return value * (multipliers[unit] ?? 1);
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
