interface StatusCardProps {
  label: string;
  value: number | string;
  color?: string;
}

export default function StatusCard({ label, value, color }: StatusCardProps) {
  const colorClass = color ?? "text-[var(--text-primary)]";

  return (
    <div className="bg-[var(--bg-secondary)] rounded-xl p-5 border border-zinc-800">
      <p className="text-xs text-zinc-500 mb-1">{label}</p>
      <p className={`text-2xl font-bold ${colorClass}`}>{value}</p>
    </div>
  );
}
