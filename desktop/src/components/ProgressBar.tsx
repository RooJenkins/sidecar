interface ProgressBarProps {
  processed: number;
  skipped: number;
  errors: number;
  total: number;
}

export default function ProgressBar({ processed, skipped, errors, total }: ProgressBarProps) {
  const done = processed + skipped + errors;
  const percent = total > 0 ? Math.round((done / total) * 100) : 0;

  return (
    <div className="w-full">
      <div className="flex justify-between text-xs text-zinc-500 mb-1.5">
        <span>{done} / {total} files</span>
        <span>{percent}%</span>
      </div>
      <div className="w-full h-2 bg-zinc-800 rounded-full overflow-hidden">
        <div
          className="h-full bg-[var(--accent)] rounded-full transition-all duration-300"
          style={{ width: `${percent}%` }}
        />
      </div>
      <div className="flex gap-4 mt-2 text-xs">
        <span className="text-[var(--success)]">✓ {processed}</span>
        <span className="text-[var(--warning)]">⊘ {skipped}</span>
        <span className="text-[var(--error)]">✗ {errors}</span>
      </div>
    </div>
  );
}
