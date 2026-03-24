import { useEffect, useState } from "react";
import StatusCard from "../components/StatusCard";
import { getStatus, cleanFolder } from "../hooks/useSidecar";
import type { StatusResult } from "../lib/types";

interface StatusPageProps {
  folderPath: string;
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default function StatusPage({ folderPath }: StatusPageProps) {
  const [status, setStatus] = useState<StatusResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>("");

  const fetchStatus = async () => {
    if (!folderPath) return;
    setLoading(true);
    setError("");
    try {
      const result = await getStatus(folderPath);
      setStatus(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchStatus();
  }, [folderPath]);

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-5 border-b border-zinc-800 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">Status</h2>
          {folderPath && (
            <p className="text-xs text-zinc-500 font-mono mt-0.5">{folderPath}</p>
          )}
        </div>
        {folderPath && (
          <div className="flex gap-2">
          <button
            onClick={async () => {
              if (!confirm("Remove all sidecar files, indexes, and cache?")) return;
              try {
                const result = await cleanFolder(folderPath);
                alert(`Cleaned: ${result.sidecarFiles} sidecar files, ${result.indexFiles} indexes removed`);
                fetchStatus();
              } catch (err) {
                alert(`Clean failed: ${err}`);
              }
            }}
            className="px-3 py-1.5 bg-red-900/30 text-red-400 border border-red-800/30 rounded-lg text-xs hover:bg-red-900/50 transition-colors"
          >
            Clean All
          </button>
          <button
            onClick={fetchStatus}
            disabled={loading}
            className="px-3 py-1.5 bg-zinc-800 text-zinc-300 rounded-lg text-xs hover:bg-zinc-700 transition-colors disabled:opacity-50"
          >
            {loading ? "..." : "Refresh"}
          </button>
          </div>
        )}
      </div>

      {!folderPath && (
        <div className="flex-1 flex items-center justify-center text-zinc-600 text-sm">
          Select a folder on the Scan page first
        </div>
      )}

      {error && (
        <div className="mx-6 mt-4 px-4 py-3 bg-red-900/20 border border-red-800/30 rounded-lg text-sm text-red-400">
          {error}
        </div>
      )}

      {status && (
        <div className="flex-1 overflow-y-auto px-6 py-5 space-y-6">
          <div className="grid grid-cols-2 gap-4">
            <StatusCard label="Total Files" value={status.totalFiles} />
            <StatusCard label="With Sidecars" value={status.trackedFiles} color="text-[var(--success)]" />
            <StatusCard label="Missing Sidecars" value={status.missingFiles} color={status.missingFiles > 0 ? "text-[var(--warning)]" : "text-zinc-600"} />
            <StatusCard label="Stale Sidecars" value={status.staleFiles} color={status.staleFiles > 0 ? "text-[var(--error)]" : "text-zinc-600"} />
          </div>

          <div className="bg-[var(--bg-secondary)] rounded-xl p-5 border border-zinc-800">
            <p className="text-xs text-zinc-500 mb-3">Disk Usage</p>
            <div className="flex gap-8 text-sm">
              <div>
                <p className="text-zinc-400">Sidecar files</p>
                <p className="font-mono">{formatBytes(status.sidecarDiskBytes)}</p>
              </div>
              <div>
                <p className="text-zinc-400">Cache</p>
                <p className="font-mono">{formatBytes(status.cacheDiskBytes)}</p>
              </div>
            </div>
          </div>

          {Object.keys(status.byExtractor).length > 0 && (
            <div className="bg-[var(--bg-secondary)] rounded-xl p-5 border border-zinc-800">
              <p className="text-xs text-zinc-500 mb-3">By Extractor</p>
              <div className="space-y-2">
                {Object.entries(status.byExtractor).map(([name, count]) => (
                  <div key={name} className="flex items-center justify-between text-sm">
                    <span className="text-zinc-400">{name}</span>
                    <span className="font-mono text-[var(--accent)]">{count}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
