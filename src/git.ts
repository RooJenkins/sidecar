import { readFile, writeFile, appendFile, access, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { execSync } from "node:child_process";

const PRE_COMMIT_HOOK = `#!/bin/sh
# Sidecar pre-commit hook (advisory mode)
# Warns about stale sidecar files — does NOT block commits

stale_count=0
stale_files=""

for file in $(git diff --cached --name-only); do
  sidecar="\${file}.sidecar.md"
  if [ -f "$sidecar" ]; then
    # Check if source is newer than sidecar
    if [ "$file" -nt "$sidecar" ]; then
      stale_count=$((stale_count + 1))
      stale_files="\${stale_files}  - $file\\n"
    fi
  fi
done

if [ "$stale_count" -gt 0 ]; then
  echo ""
  echo "⚠️  Sidecar: $stale_count file(s) have outdated sidecars:"
  echo -e "$stale_files"
  echo "Run 'sidecar scan .' to update, then stage the sidecar files."
  echo ""
fi

# Always allow the commit (advisory only)
exit 0
`;

export function isGitRepo(dir: string): boolean {
  try {
    execSync("git rev-parse --is-inside-work-tree", {
      cwd: dir,
      stdio: "ignore",
      timeout: 5_000,
    });
    return true;
  } catch {
    return false;
  }
}

export function getGitRoot(dir: string): string | null {
  try {
    return execSync("git rev-parse --show-toplevel", {
      cwd: dir,
      encoding: "utf-8",
      timeout: 5_000,
    }).trim();
  } catch {
    return null;
  }
}

export interface InitResult {
  hookInstalled: boolean;
  gitignoreUpdated: boolean;
  messages: string[];
}

export async function initGitIntegration(dir: string): Promise<InitResult> {
  const result: InitResult = {
    hookInstalled: false,
    gitignoreUpdated: false,
    messages: [],
  };

  if (!isGitRepo(dir)) {
    result.messages.push("Not a git repository. Run 'git init' first.");
    return result;
  }

  const gitRoot = getGitRoot(dir);
  if (!gitRoot) {
    result.messages.push("Could not determine git root directory.");
    return result;
  }

  // Install pre-commit hook
  const hooksDir = join(gitRoot, ".git", "hooks");
  const hookPath = join(hooksDir, "pre-commit");

  try {
    await mkdir(hooksDir, { recursive: true });

    // Check if hook already exists
    let existingHook: string | null = null;
    try {
      existingHook = await readFile(hookPath, "utf-8");
    } catch {
      // no existing hook
    }

    if (existingHook?.includes("Sidecar pre-commit hook")) {
      result.messages.push("Pre-commit hook already installed.");
      result.hookInstalled = true;
    } else if (existingHook) {
      // Append to existing hook
      await appendFile(hookPath, "\n\n" + PRE_COMMIT_HOOK);
      result.hookInstalled = true;
      result.messages.push("Sidecar check appended to existing pre-commit hook.");
    } else {
      await writeFile(hookPath, PRE_COMMIT_HOOK, { mode: 0o755 });
      result.hookInstalled = true;
      result.messages.push("Pre-commit hook installed.");
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    result.messages.push(`Failed to install hook: ${msg}`);
  }

  // Update .gitignore
  const gitignorePath = join(gitRoot, ".gitignore");
  const sidecarCacheEntry = ".sidecar/";

  try {
    let gitignore = "";
    try {
      gitignore = await readFile(gitignorePath, "utf-8");
    } catch {
      // no .gitignore yet
    }

    if (gitignore.includes(sidecarCacheEntry)) {
      result.messages.push(".gitignore already includes .sidecar/ cache directory.");
      result.gitignoreUpdated = true;
    } else {
      const addition = gitignore.endsWith("\n") || gitignore === ""
        ? `\n# Sidecar cache\n${sidecarCacheEntry}\n`
        : `\n\n# Sidecar cache\n${sidecarCacheEntry}\n`;
      await appendFile(gitignorePath, addition);
      result.gitignoreUpdated = true;
      result.messages.push("Added .sidecar/ to .gitignore.");
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    result.messages.push(`Failed to update .gitignore: ${msg}`);
  }

  return result;
}
