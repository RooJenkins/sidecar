import * as vscode from "vscode";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);

function getCliPath(): string {
  return vscode.workspace.getConfiguration("sidecar").get("cliPath", "sidecar");
}

async function runSidecar(
  args: string[]
): Promise<{ stdout: string; stderr: string }> {
  const cli = getCliPath();
  return exec(cli, args, { timeout: 30000 });
}

interface SearchResult {
  file: string;
  title: string;
  score: number;
  summary: string;
  topics: string[];
  snippet: string;
}

interface SearchOutput {
  query: string;
  results: SearchResult[];
}

export function activate(context: vscode.ExtensionContext) {
  // Search command
  context.subscriptions.push(
    vscode.commands.registerCommand("sidecar.search", async () => {
      const query = await vscode.window.showInputBox({
        prompt: "Search your sidecar knowledge base",
        placeHolder: "Enter search query...",
      });

      if (!query) return;

      try {
        const { stdout } = await runSidecar([
          "search",
          query,
          "--json",
          "--top",
          "10",
        ]);
        const output: SearchOutput = JSON.parse(stdout);

        if (output.results.length === 0) {
          vscode.window.showInformationMessage("No results found.");
          return;
        }

        const items = output.results.map((r) => ({
          label: r.title,
          description: `Score: ${r.score.toFixed(2)}`,
          detail: r.summary || r.snippet || "",
          result: r,
        }));

        const picked = await vscode.window.showQuickPick(items, {
          placeHolder: `${output.results.length} results for "${query}"`,
          matchOnDescription: true,
          matchOnDetail: true,
        });

        if (picked) {
          const sidecarPath = picked.result.file + ".sidecar.md";
          const doc = await vscode.workspace.openTextDocument(sidecarPath);
          await vscode.window.showTextDocument(doc, { preview: true });
        }
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Unknown error";
        vscode.window.showErrorMessage(`Sidecar search failed: ${message}`);
      }
    })
  );

  // Smart search command
  context.subscriptions.push(
    vscode.commands.registerCommand("sidecar.smartSearch", async () => {
      const editor = vscode.window.activeTextEditor;
      const selection = editor?.selection;
      const selectedText =
        selection && !selection.isEmpty
          ? editor.document.getText(selection)
          : "";

      const query = await vscode.window.showInputBox({
        prompt: "AI-powered smart search",
        placeHolder: "Enter context or question...",
        value: selectedText,
      });

      if (!query) return;

      try {
        const { stdout } = await runSidecar([
          "smart-search",
          query,
          "--json",
          "--top",
          "5",
        ]);
        const output: SearchOutput = JSON.parse(stdout);

        if (output.results.length === 0) {
          vscode.window.showInformationMessage(
            "No relevant documents found."
          );
          return;
        }

        const items = output.results.map((r) => ({
          label: r.title,
          description: r.topics.join(", "),
          detail: r.summary || r.snippet || "",
          result: r,
        }));

        const picked = await vscode.window.showQuickPick(items, {
          placeHolder: `${output.results.length} relevant documents`,
        });

        if (picked) {
          const sidecarPath = picked.result.file + ".sidecar.md";
          const doc = await vscode.workspace.openTextDocument(sidecarPath);
          await vscode.window.showTextDocument(doc, { preview: true });
        }
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Unknown error";
        vscode.window.showErrorMessage(
          `Sidecar smart search failed: ${message}`
        );
      }
    })
  );

  // Scan workspace command
  context.subscriptions.push(
    vscode.commands.registerCommand("sidecar.scanWorkspace", async () => {
      const folders = vscode.workspace.workspaceFolders;
      if (!folders || folders.length === 0) {
        vscode.window.showWarningMessage("No workspace folder open.");
        return;
      }

      const folder = folders[0].uri.fsPath;

      await vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: "Sidecar: Scanning workspace...",
          cancellable: false,
        },
        async () => {
          try {
            const { stdout } = await runSidecar([
              "scan",
              folder,
              "--json",
            ]);
            const result = JSON.parse(stdout);
            vscode.window.showInformationMessage(
              `Sidecar: Scanned ${result.processed ?? 0} files.`
            );
          } catch (err) {
            const message =
              err instanceof Error ? err.message : "Unknown error";
            vscode.window.showErrorMessage(`Sidecar scan failed: ${message}`);
          }
        }
      );
    })
  );

  // Status command
  context.subscriptions.push(
    vscode.commands.registerCommand("sidecar.status", async () => {
      const folders = vscode.workspace.workspaceFolders;
      if (!folders) {
        vscode.window.showWarningMessage("No workspace folder open.");
        return;
      }

      try {
        const { stdout } = await runSidecar([
          "status",
          folders[0].uri.fsPath,
        ]);
        const channel = vscode.window.createOutputChannel("Sidecar");
        channel.clear();
        channel.appendLine(stdout);
        channel.show();
      } catch (err) {
        const message =
          err instanceof Error ? err.message : "Unknown error";
        vscode.window.showErrorMessage(
          `Sidecar status failed: ${message}`
        );
      }
    })
  );
}

export function deactivate() {}
