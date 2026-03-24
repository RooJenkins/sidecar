import { useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";

interface FolderPickerProps {
  onSelect: (path: string) => void;
  selectedPath?: string;
}

export default function FolderPicker({ onSelect, selectedPath }: FolderPickerProps) {
  const [dragOver, setDragOver] = useState(false);

  const handleClick = async () => {
    const selected = await open({ directory: true, multiple: false });
    if (selected && typeof selected === "string") {
      onSelect(selected);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    const files = e.dataTransfer.files;
    if (files.length > 0) {
      // In Tauri, dropped files give us the path
      const path = (files[0] as unknown as { path?: string }).path;
      if (path) {
        onSelect(path);
      }
    }
  };

  return (
    <div className="flex flex-col items-center justify-center flex-1">
      <div
        onClick={handleClick}
        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        onDrop={handleDrop}
        className={`w-80 h-48 border-2 border-dashed rounded-2xl flex flex-col items-center justify-center cursor-pointer transition-all ${
          dragOver
            ? "border-[var(--accent)] bg-[var(--accent)]/10 scale-105"
            : "border-zinc-700 hover:border-[var(--accent)] hover:bg-[var(--accent)]/5"
        }`}
      >
        <span className="text-4xl mb-3">{dragOver ? "📥" : "📁"}</span>
        <p className="text-sm text-zinc-400">
          {dragOver ? "Drop folder here" : "Click to choose a folder"}
        </p>
        <p className="text-xs text-zinc-600 mt-1">or drag & drop</p>
      </div>

      {selectedPath && (
        <div className="mt-4 px-4 py-2 bg-[var(--bg-tertiary)] rounded-lg">
          <p className="text-xs text-zinc-500">Selected</p>
          <p className="text-sm font-mono truncate max-w-md">{selectedPath}</p>
        </div>
      )}
    </div>
  );
}
