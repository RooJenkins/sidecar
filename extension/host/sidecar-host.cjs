#!/usr/bin/env node

/**
 * Sidecar Native Messaging Host
 *
 * Supports both one-shot (sendNativeMessage) and persistent (connectNative) modes.
 * Chrome native messaging protocol: 4-byte LE uint32 length prefix + JSON payload.
 */

const { execFile } = require("child_process");
const path = require("path");

const SIDECAR_CLI = path.resolve(__dirname, "../../dist/cli.js");

function sendMessage(msg) {
  const json = JSON.stringify(msg);
  const buf = Buffer.from(json, "utf-8");
  const header = Buffer.alloc(4);
  header.writeUInt32LE(buf.length, 0);
  process.stdout.write(header);
  process.stdout.write(buf);
}

function runSidecarSearch(query, maxResults) {
  return new Promise((resolve, reject) => {
    execFile("node", [SIDECAR_CLI, "search", query, "--json", "--top", String(maxResults)], { timeout: 25000 }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(stderr || err.message));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (parseErr) {
        reject(new Error(`Failed to parse sidecar output: ${parseErr.message}`));
      }
    });
  });
}

/**
 * AI-powered smart search via the CLI's smart-search command.
 * Pipes conversation text via stdin to `sidecar smart-search --json`.
 */
function smartSearch(conversation, maxResults) {
  return new Promise((resolve, reject) => {
    const { spawn } = require("child_process");
    const proc = spawn("node", [SIDECAR_CLI, "smart-search", "--json", "--top", String(maxResults)], {
      timeout: 45000,
      env: {
        ...process.env,
        PATH: [
          process.env.HOME + "/.local/bin",
          "/opt/homebrew/bin",
          "/usr/local/bin",
          "/usr/bin",
          process.env.PATH || "",
        ].join(":"),
      },
    });

    let stdout = "";
    let stderr = "";
    proc.stdin.write(conversation);
    proc.stdin.end();
    proc.stdout.on("data", (d) => { stdout += d; });
    proc.stderr.on("data", (d) => { stderr += d; });

    proc.on("close", (code) => {
      if (code !== 0 || !stdout.trim()) {
        reject(new Error(stderr || `smart-search exited with code ${code}`));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (parseErr) {
        reject(new Error(`Failed to parse smart-search output: ${parseErr.message}`));
      }
    });

    proc.on("error", (err) => {
      reject(err);
    });
  });
}

function checkStatus() {
  return new Promise((resolve) => {
    execFile("node", [SIDECAR_CLI, "--version"], { timeout: 5000 }, (err, stdout) => {
      if (err) {
        resolve({ available: false, error: err.message });
      } else {
        resolve({ available: true, version: stdout.trim() });
      }
    });
  });
}

async function handleMessage(msg) {
  try {
    switch (msg.type) {
      case "search": {
        const maxResults = msg.maxResults || 5;
        const output = await runSidecarSearch(msg.query, maxResults);
        sendMessage({ type: "results", results: output.results || [], query: output.query });
        break;
      }
      case "smart-search": {
        const maxResults = msg.maxResults || 5;
        const output = await smartSearch(msg.conversation, maxResults);
        sendMessage({ type: "results", results: output.results || [], query: output.query });
        break;
      }
      case "status": {
        const status = await checkStatus();
        sendMessage({ type: "status", ...status });
        break;
      }
      default:
        sendMessage({ type: "error", error: `Unknown message type: ${msg.type}` });
    }
  } catch (err) {
    sendMessage({ type: "error", error: err.message });
  }
}

// Track in-flight async work so we don't exit before responses are sent.
let pendingWork = 0;
let stdinEnded = false;

function maybeExit() {
  if (stdinEnded && pendingWork === 0) {
    process.exit(0);
  }
}

// Read messages in a loop — handles both one-shot and persistent connections.
// Chrome closes stdin when done (one-shot exits after first message, persistent keeps going).
function readLoop() {
  let headerBuf = Buffer.alloc(0);
  let bodyBuf = Buffer.alloc(0);
  let expectedLen = -1;

  process.stdin.on("data", (chunk) => {
    let data = chunk;

    while (data.length > 0) {
      if (expectedLen === -1) {
        // Reading header
        const needed = 4 - headerBuf.length;
        const take = data.slice(0, needed);
        headerBuf = Buffer.concat([headerBuf, take]);
        data = data.slice(needed);

        if (headerBuf.length === 4) {
          expectedLen = headerBuf.readUInt32LE(0);
          headerBuf = Buffer.alloc(0);
          bodyBuf = Buffer.alloc(0);

          if (expectedLen === 0) {
            expectedLen = -1;
            continue;
          }
        }
      }

      if (expectedLen > 0 && data.length > 0) {
        const needed = expectedLen - bodyBuf.length;
        const take = data.slice(0, needed);
        bodyBuf = Buffer.concat([bodyBuf, take]);
        data = data.slice(needed);

        if (bodyBuf.length === expectedLen) {
          try {
            const msg = JSON.parse(bodyBuf.toString("utf-8"));
            pendingWork++;
            handleMessage(msg).finally(() => {
              pendingWork--;
              maybeExit();
            });
          } catch (err) {
            sendMessage({ type: "error", error: `Invalid JSON: ${err.message}` });
          }
          expectedLen = -1;
          bodyBuf = Buffer.alloc(0);
        }
      }
    }
  });

  process.stdin.on("end", () => {
    stdinEnded = true;
    maybeExit();
  });

  process.stdin.resume();
}

readLoop();
