import { useState, useEffect } from "react";
import FolderPicker from "../components/FolderPicker";
import FileList from "../components/FileList";
import SidecarPreview from "../components/SidecarPreview";
import { useScanEvents } from "../hooks/useScanEvents";
import { scanFolder, loadConfig } from "../hooks/useSidecar";
import type { FileEntry, SidecarConfig } from "../lib/types";

interface ScanPageProps {
  folderPath: string;
  onFolderSelect: (path: string) => void;
}

export default function ScanPage({ folderPath, onFolderSelect }: ScanPageProps) {
  const { state, handleEvent, startScan, reset } = useScanEvents();
  const [previewFile, setPreviewFile] = useState<FileEntry | null>(null);
  const [error, setError] = useState<string>("");
  const [config, setConfig] = useState<SidecarConfig>({});
  const [scanning, setScanning] = useState(false);

  // Load config when folder changes
  useEffect(() => {
    if (folderPath) {
      loadConfig(folderPath).then(setConfig);
    }
  }, [folderPath]);

  const handleScan = async () => {
    if (!folderPath || scanning) return;
    setError("");
    setScanning(true);
    startScan();
    try {
      await scanFolder(folderPath, config, handleEvent);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setError(msg);
      console.error("Scan failed:", msg);
    } finally {
      setScanning(false);
    }
  };

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-5 border-b border-zinc-800">
        <h2 className="text-lg font-semibold">Scan</h2>
        {folderPath ? (
          <p className="text-xs text-zinc-500 font-mono mt-0.5">{folderPath}</p>
        ) : (
          <p className="text-xs text-zinc-500 mt-0.5">
            Select a folder to generate .sidecar.md files
          </p>
        )}
      </div>

      {state.phase === "idle" && !folderPath && (
        <FolderPicker onSelect={onFolderSelect} selectedPath={folderPath} />
      )}

      {state.phase === "idle" && folderPath && (
        <div className="flex flex-col items-center justify-center flex-1 gap-4">
          <div className="px-4 py-3 bg-[var(--bg-secondary)] rounded-lg border border-zinc-800 min-w-80">
            <p className="text-xs text-zinc-500">Folder</p>
            <p className="text-sm font-mono truncate">{folderPath}</p>
            {config.summarize && (
              <p className="text-xs text-[var(--accent)] mt-1">AI summarization enabled ({config.provider ?? "claude"})</p>
            )}
          </div>
          <div className="flex gap-3">
            <button
              onClick={handleScan}
              disabled={scanning}
              className="px-6 py-2.5 bg-[var(--accent)] text-white rounded-lg text-sm font-medium hover:bg-blue-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Start Scan
            </button>
            <button
              onClick={() => { reset(); onFolderSelect(""); }}
              className="px-4 py-2.5 bg-zinc-800 text-zinc-300 rounded-lg text-sm hover:bg-zinc-700 transition-colors"
            >
              Change Folder
            </button>
          </div>
          {error && (
            <div className="px-4 py-3 bg-red-900/20 border border-red-800/30 rounded-lg text-sm text-red-400 max-w-lg">
              {error}
            </div>
          )}
        </div>
      )}

      {state.phase === "scanning" && (
        <div className="flex-1 flex flex-col items-center justify-center gap-4">
          <div className="animate-spin w-8 h-8 border-2 border-zinc-700 border-t-[var(--accent)] rounded-full" />
          <p className="text-sm text-zinc-400">Scanning files...</p>
          <p className="text-xs text-zinc-600">
            {config.summarize ? "Extracting & summarizing — this may take a few minutes" : "This may take a moment"}
          </p>
          {error && (
            <div className="mt-4 px-4 py-3 bg-red-900/20 border border-red-800/30 rounded-lg text-sm text-red-400 max-w-lg">
              {error}
            </div>
          )}
        </div>
      )}

      {state.phase === "complete" && (
        <div className="flex-1 flex flex-col px-6 py-5 gap-4 overflow-hidden">
          <div className="flex items-center justify-between shrink-0">
            <div>
              <p className="text-sm font-medium">
                Scan complete
                <span className="text-zinc-500 ml-2">({state.elapsed}s)</span>
              </p>
              <div className="flex gap-4 mt-1 text-xs">
                <span className="text-[var(--success)]">✓ {state.processed} processed</span>
                <span className="text-[var(--warning)]">⊘ {state.skipped} skipped</span>
                <span className="text-[var(--error)]">✗ {state.errors} errors</span>
              </div>
            </div>
            <div className="flex gap-2">
              <button
                onClick={handleScan}
                disabled={scanning}
                className="px-4 py-2 bg-[var(--accent)] text-white rounded-lg text-xs font-medium hover:bg-blue-600 transition-colors disabled:opacity-50"
              >
                Rescan
              </button>
              <button
                onClick={() => { reset(); onFolderSelect(""); }}
                className="px-4 py-2 bg-zinc-800 text-zinc-300 rounded-lg text-xs hover:bg-zinc-700 transition-colors"
              >
                New Folder
              </button>
            </div>
          </div>
          <div className="flex-1 overflow-hidden">
            <FileList files={state.files} onSelect={setPreviewFile} />
          </div>
        </div>
      )}

      <SidecarPreview file={previewFile} onClose={() => setPreviewFile(null)} />
    </div>
  );
}
