import { spawn, execSync, type ChildProcess } from "node:child_process";
import { isTikaAvailable } from "./extractors/tika.js";

const DEFAULT_TIKA_URL = "http://localhost:9998";
const TIKA_DOCKER_IMAGE = "apache/tika:latest";
const TIKA_CONTAINER_NAME = "sidecar-tika";

let managedProcess: ChildProcess | null = null;
let managedContainerId: string | null = null;

export interface TikaStartOptions {
  tikaUrl?: string;
  verbose?: boolean;
  log?: (msg: string) => void;
}

export async function ensureTika(options: TikaStartOptions = {}): Promise<boolean> {
  const url = options.tikaUrl ?? DEFAULT_TIKA_URL;
  const log = options.log ?? (() => {});

  // Already running?
  if (await isTikaAvailable(url)) {
    log("Tika is already running");
    return true;
  }

  // Try Docker first
  if (isDockerAvailable()) {
    log("Starting Tika via Docker...");
    const started = await startTikaDocker(url, log);
    if (started) return true;
  }

  // Try JAR fallback
  if (isJavaAvailable()) {
    log("Docker not available. Starting Tika via JAR...");
    const started = await startTikaJar(url, log);
    if (started) return true;
  }

  log("Could not start Tika. Neither Docker nor Java is available.");
  log("Install Docker or Java to use Tika for exotic file formats.");
  log("Or use --no-tika to skip Tika and use JS-native extractors only.");
  return false;
}

async function startTikaDocker(url: string, log: (msg: string) => void): Promise<boolean> {
  const port = new URL(url).port || "9998";

  try {
    // Check if container already exists (stopped)
    try {
      execSync(`docker rm -f ${TIKA_CONTAINER_NAME}`, { stdio: "ignore" });
    } catch {
      // container didn't exist, fine
    }

    log(`Pulling ${TIKA_DOCKER_IMAGE} (one-time setup)...`);

    const pullResult = execSync(`docker pull ${TIKA_DOCKER_IMAGE}`, {
      encoding: "utf-8",
      timeout: 120_000,
      stdio: ["ignore", "pipe", "pipe"],
    });

    if (pullResult) log(pullResult.trim());

    const containerId = execSync(
      `docker run -d --name ${TIKA_CONTAINER_NAME} -p ${port}:9998 ${TIKA_DOCKER_IMAGE}`,
      { encoding: "utf-8", timeout: 30_000 }
    ).trim();

    managedContainerId = containerId;
    log(`Tika container started: ${containerId.slice(0, 12)}`);

    // Wait for readiness
    return await waitForTika(url, 30_000);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`Docker start failed: ${msg}`);
    return false;
  }
}

async function startTikaJar(url: string, log: (msg: string) => void): Promise<boolean> {
  const port = new URL(url).port || "9998";

  try {
    // Look for tika-server JAR in common locations
    const jarPath = findTikaJar();
    if (!jarPath) {
      log("No tika-server JAR found. Download from https://tika.apache.org/download.html");
      return false;
    }

    log(`Starting Tika JAR: ${jarPath}`);

    managedProcess = spawn("java", ["-jar", jarPath, "-p", port], {
      stdio: "ignore",
      detached: true,
    });

    managedProcess.unref();

    return await waitForTika(url, 30_000);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`JAR start failed: ${msg}`);
    return false;
  }
}

async function waitForTika(url: string, timeoutMs: number): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await isTikaAvailable(url)) return true;
    await sleep(1000);
  }
  return false;
}

export function stopTika(): void {
  if (managedContainerId) {
    try {
      execSync(`docker stop ${TIKA_CONTAINER_NAME}`, { timeout: 10_000, stdio: "ignore" });
      execSync(`docker rm ${TIKA_CONTAINER_NAME}`, { timeout: 10_000, stdio: "ignore" });
    } catch {
      // best effort
    }
    managedContainerId = null;
  }

  if (managedProcess) {
    managedProcess.kill("SIGTERM");
    managedProcess = null;
  }
}

// Signal handlers for graceful cleanup
function setupSignalHandlers(): void {
  const handler = () => {
    stopTika();
    process.exit(0);
  };
  process.on("SIGINT", handler);
  process.on("SIGTERM", handler);
  process.on("exit", () => stopTika());
}

setupSignalHandlers();

function isDockerAvailable(): boolean {
  try {
    execSync("docker info", { stdio: "ignore", timeout: 5_000 });
    return true;
  } catch {
    return false;
  }
}

function isJavaAvailable(): boolean {
  try {
    execSync("java -version", { stdio: "ignore", timeout: 5_000 });
    return true;
  } catch {
    return false;
  }
}

function findTikaJar(): string | null {
  const candidates = [
    "tika-server.jar",
    "tika-server-standard.jar",
    "./tika-server.jar",
    "./tika-server-standard.jar",
    `${process.env.HOME}/tika-server.jar`,
    `${process.env.HOME}/tika-server-standard.jar`,
  ];

  for (const candidate of candidates) {
    try {
      execSync(`test -f "${candidate}"`, { stdio: "ignore" });
      return candidate;
    } catch {
      continue;
    }
  }

  return null;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
