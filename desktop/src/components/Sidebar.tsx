interface SidebarProps {
  activePage: string;
  onNavigate: (page: string) => void;
  folderPath: string;
}

const navItems = [
  { id: "scan", label: "Scan", icon: "⚡" },
  { id: "search", label: "Search", icon: "🔍" },
  { id: "status", label: "Status", icon: "📊" },
  { id: "settings", label: "Settings", icon: "⚙️" },
];

export default function Sidebar({ activePage, onNavigate, folderPath }: SidebarProps) {
  const folderName = folderPath ? folderPath.split("/").pop() : null;

  return (
    <div className="flex flex-col w-52 h-screen bg-[var(--bg-secondary)] border-r border-zinc-800">
      <div className="px-5 py-5">
        <h1 className="text-lg font-bold tracking-tight">Sidecar</h1>
        <p className="text-xs text-zinc-500 mt-0.5">Document companion files</p>
      </div>

      {folderName && (
        <div className="mx-3 mb-3 px-3 py-2 bg-[var(--bg-tertiary)] rounded-lg">
          <p className="text-[10px] text-zinc-500 uppercase tracking-wider">Active folder</p>
          <p className="text-xs font-medium truncate mt-0.5">{folderName}</p>
        </div>
      )}

      <nav className="flex-1 px-3 space-y-1">
        {navItems.map((item) => (
          <button
            key={item.id}
            onClick={() => onNavigate(item.id)}
            className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
              activePage === item.id
                ? "bg-[var(--accent)]/15 text-[var(--accent)]"
                : "text-zinc-400 hover:bg-zinc-800 hover:text-zinc-200"
            }`}
          >
            <span>{item.icon}</span>
            <span>{item.label}</span>
          </button>
        ))}
      </nav>

      <div className="px-5 py-4 border-t border-zinc-800">
        <p className="text-[10px] text-zinc-600">v0.1.0</p>
      </div>
    </div>
  );
}
