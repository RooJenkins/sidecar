import { useEffect, useState } from "react";
import { readSidecarFile } from "../hooks/useSidecar";
import type { FileEntry } from "../lib/types";

interface SidecarPreviewProps {
  file: FileEntry | null;
  onClose: () => void;
}

export default function SidecarPreview({ file, onClose }: SidecarPreviewProps) {
  const [content, setContent] = useState<string>("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!file) return;
    setLoading(true);
    readSidecarFile(file.sourcePath)
      .then(setContent)
      .catch(() => setContent("Failed to load sidecar file"))
      .finally(() => setLoading(false));
  }, [file]);

  if (!file) return null;

  return (
    <div className="fixed inset-y-0 right-0 w-[500px] bg-[var(--bg-secondary)] border-l border-zinc-800 shadow-2xl flex flex-col z-50">
      <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-800">
        <div className="min-w-0">
          <p className="text-sm font-medium truncate">{file.fileName}.sidecar.md</p>
          <p className="text-xs text-zinc-500 truncate">{file.sourcePath}</p>
        </div>
        <button
          onClick={onClose}
          className="ml-3 text-zinc-500 hover:text-zinc-200 text-lg shrink-0"
        >
          ✕
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-5">
        {loading ? (
          <p className="text-zinc-500 text-sm">Loading...</p>
        ) : (
          <pre className="text-xs font-mono text-zinc-300 whitespace-pre-wrap leading-relaxed">
            {content}
          </pre>
        )}
      </div>
    </div>
  );
}
