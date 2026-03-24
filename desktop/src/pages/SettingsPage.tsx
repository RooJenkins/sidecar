import { useEffect, useState } from "react";
import { loadConfig, saveConfig } from "../hooks/useSidecar";
import type { SidecarConfig } from "../lib/types";

interface SettingsPageProps {
  folderPath: string;
}

export default function SettingsPage({ folderPath }: SettingsPageProps) {
  const [config, setConfig] = useState<SidecarConfig>({});
  const [saved, setSaved] = useState(false);
  const [includeInput, setIncludeInput] = useState("");
  const [excludeInput, setExcludeInput] = useState("");

  useEffect(() => {
    if (!folderPath) return;
    loadConfig(folderPath).then(setConfig);
  }, [folderPath]);

  const handleSave = async () => {
    await saveConfig(folderPath, config);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const addPattern = (field: "include" | "exclude", value: string) => {
    if (!value.trim()) return;
    const current = config[field] ?? [];
    if (!current.includes(value.trim())) {
      setConfig({ ...config, [field]: [...current, value.trim()] });
    }
  };

  const removePattern = (field: "include" | "exclude", index: number) => {
    const current = config[field] ?? [];
    setConfig({ ...config, [field]: current.filter((_, i) => i !== index) });
  };

  if (!folderPath) {
    return (
      <div className="flex flex-col h-full">
        <div className="px-6 py-5 border-b border-zinc-800">
          <h2 className="text-lg font-semibold">Settings</h2>
        </div>
        <div className="flex-1 flex items-center justify-center text-zinc-600 text-sm">
          Select a folder on the Scan page first
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-5 border-b border-zinc-800 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold">Settings</h2>
          <p className="text-xs text-zinc-500 font-mono mt-0.5">{folderPath}/.sidecarrc</p>
        </div>
        <button
          onClick={handleSave}
          className={`px-4 py-2 rounded-lg text-xs font-medium transition-colors ${
            saved
              ? "bg-green-600 text-white"
              : "bg-[var(--accent)] text-white hover:bg-blue-600"
          }`}
        >
          {saved ? "Saved ✓" : "Save"}
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-6 py-5 space-y-6">
        {/* Include patterns */}
        <div>
          <label className="text-xs text-zinc-500 block mb-2">Include Patterns</label>
          <div className="flex flex-wrap gap-2 mb-2">
            {(config.include ?? []).map((pat, i) => (
              <span key={i} className="px-2 py-1 bg-zinc-800 rounded text-xs flex items-center gap-1.5">
                {pat}
                <button onClick={() => removePattern("include", i)} className="text-zinc-500 hover:text-red-400">×</button>
              </span>
            ))}
          </div>
          <div className="flex gap-2">
            <input
              value={includeInput}
              onChange={(e) => setIncludeInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") { addPattern("include", includeInput); setIncludeInput(""); } }}
              placeholder="e.g. **/*.pdf"
              className="flex-1 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--accent)]"
            />
            <button
              onClick={() => { addPattern("include", includeInput); setIncludeInput(""); }}
              className="px-3 py-2 bg-zinc-800 text-zinc-300 rounded-lg text-sm hover:bg-zinc-700"
            >
              Add
            </button>
          </div>
        </div>

        {/* Exclude patterns */}
        <div>
          <label className="text-xs text-zinc-500 block mb-2">Exclude Patterns</label>
          <div className="flex flex-wrap gap-2 mb-2">
            {(config.exclude ?? []).map((pat, i) => (
              <span key={i} className="px-2 py-1 bg-zinc-800 rounded text-xs flex items-center gap-1.5">
                {pat}
                <button onClick={() => removePattern("exclude", i)} className="text-zinc-500 hover:text-red-400">×</button>
              </span>
            ))}
          </div>
          <div className="flex gap-2">
            <input
              value={excludeInput}
              onChange={(e) => setExcludeInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") { addPattern("exclude", excludeInput); setExcludeInput(""); } }}
              placeholder="e.g. node_modules"
              className="flex-1 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--accent)]"
            />
            <button
              onClick={() => { addPattern("exclude", excludeInput); setExcludeInput(""); }}
              className="px-3 py-2 bg-zinc-800 text-zinc-300 rounded-lg text-sm hover:bg-zinc-700"
            >
              Add
            </button>
          </div>
        </div>

        {/* Max file size */}
        <div>
          <label className="text-xs text-zinc-500 block mb-2">Max File Size</label>
          <input
            value={config.maxFileSize ?? ""}
            onChange={(e) => setConfig({ ...config, maxFileSize: e.target.value })}
            placeholder="100MB"
            className="w-40 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--accent)]"
          />
        </div>

        {/* AI Summarization */}
        <div className="flex items-center justify-between">
          <div>
            <label className="text-sm">AI Summarization</label>
            <p className="text-xs text-zinc-500">Generate AI summaries for each file</p>
          </div>
          <button
            onClick={() => setConfig({ ...config, summarize: !config.summarize })}
            className={`w-12 h-6 rounded-full transition-colors ${config.summarize ? "bg-[var(--accent)]" : "bg-zinc-700"}`}
          >
            <div className={`w-5 h-5 bg-white rounded-full transition-transform ${config.summarize ? "translate-x-6" : "translate-x-0.5"}`} />
          </button>
        </div>

        {/* Provider */}
        <div>
          <label className="text-xs text-zinc-500 block mb-2">AI Provider</label>
          <select
            value={config.provider ?? "claude"}
            onChange={(e) => setConfig({ ...config, provider: e.target.value })}
            className="w-60 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--accent)]"
          >
            <option value="claude">Claude (via claude CLI)</option>
            <option value="ollama">Ollama (local)</option>
            <option value="openai-compatible">OpenAI-compatible</option>
          </select>
        </div>

        {/* Model */}
        <div>
          <label className="text-xs text-zinc-500 block mb-2">Model</label>
          <input
            value={config.model ?? ""}
            onChange={(e) => setConfig({ ...config, model: e.target.value })}
            placeholder={config.provider === "ollama" ? "llama3.2" : "claude-sonnet-4-5-20250929"}
            className="w-60 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--accent)]"
          />
        </div>

        {/* Concurrency */}
        <div>
          <label className="text-xs text-zinc-500 block mb-2">Concurrency</label>
          <input
            type="number"
            min={1}
            max={16}
            value={config.concurrency ?? 4}
            onChange={(e) => setConfig({ ...config, concurrency: parseInt(e.target.value) || 4 })}
            className="w-24 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-[var(--accent)]"
          />
        </div>
      </div>
    </div>
  );
}
