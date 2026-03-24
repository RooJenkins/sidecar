import type { FileEntry } from "../lib/types";

interface FileListProps {
  files: FileEntry[];
  onSelect: (file: FileEntry) => void;
  showSkipped?: boolean;
}

const statusIcons: Record<string, string> = {
  processed: "✓",
  skipped: "⊘",
  error: "✗",
};

const statusColors: Record<string, string> = {
  processed: "text-[var(--success)]",
  skipped: "text-[var(--warning)]",
  error: "text-[var(--error)]",
};

export default function FileList({ files, onSelect, showSkipped = true }: FileListProps) {
  const filtered = showSkipped ? files : files.filter((f) => f.status !== "skipped");

  if (filtered.length === 0) {
    return (
      <div className="flex items-center justify-center py-12 text-zinc-600 text-sm">
        No files processed yet
      </div>
    );
  }

  return (
    <div className="overflow-y-auto h-full">
      <table className="w-full text-sm">
        <thead className="text-xs text-zinc-500 border-b border-zinc-800 sticky top-0 bg-[var(--bg-primary)] z-10">
          <tr>
            <th className="text-left py-2 px-3 w-8"></th>
            <th className="text-left py-2 px-3">File</th>
            <th className="text-left py-2 px-3 w-24">Type</th>
            <th className="text-left py-2 px-3">Details</th>
          </tr>
        </thead>
        <tbody>
          {filtered.map((file, i) => (
            <tr
              key={`${file.sourcePath}-${i}`}
              onClick={() => file.status === "processed" && onSelect(file)}
              className={`border-b border-zinc-800/50 transition-colors ${
                file.status === "processed"
                  ? "hover:bg-zinc-800/50 cursor-pointer"
                  : "opacity-60"
              }`}
            >
              <td className={`py-2 px-3 ${statusColors[file.status]}`}>
                {statusIcons[file.status]}
              </td>
              <td className="py-2 px-3 font-mono text-xs truncate max-w-xs">
                {file.fileName}
              </td>
              <td className="py-2 px-3 text-zinc-500 text-xs">
                {file.extractor || "—"}
              </td>
              <td className="py-2 px-3 text-zinc-600 text-xs truncate max-w-xs">
                {file.reason || file.message || (file.status === "processed" ? "click to preview" : "")}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
