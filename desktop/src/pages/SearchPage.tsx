import { useState, useCallback } from "react";
import { searchDocuments, buildIndex, readSidecarFile } from "../hooks/useSidecar";
import type { SearchResult } from "../lib/types";

interface SearchPageProps {
  folderPath: string;
}

export default function SearchPage({ folderPath }: SearchPageProps) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [indexing, setIndexing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedResult, setSelectedResult] = useState<SearchResult | null>(null);
  const [previewContent, setPreviewContent] = useState<string | null>(null);
  const [hasSearched, setHasSearched] = useState(false);

  const handleSearch = useCallback(async () => {
    if (!query.trim()) return;
    setSearching(true);
    setError(null);
    setSelectedResult(null);
    setPreviewContent(null);
    try {
      const output = await searchDocuments(query.trim());
      setResults(output.results);
      setHasSearched(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setResults([]);
    } finally {
      setSearching(false);
    }
  }, [query]);

  const handleIndex = useCallback(async () => {
    if (!folderPath) return;
    setIndexing(true);
    setError(null);
    try {
      const result = await buildIndex([folderPath]);
      setError(null);
      alert(`Indexed ${result.documentCount} documents`);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setIndexing(false);
    }
  }, [folderPath]);

  const handleResultClick = useCallback(async (result: SearchResult) => {
    setSelectedResult(result);
    try {
      const content = await readSidecarFile(result.file);
      setPreviewContent(content);
    } catch {
      setPreviewContent("Could not load sidecar file.");
    }
  }, []);

  const scoreColor = (score: number) => {
    if (score >= 0.7) return "text-green-400";
    if (score >= 0.4) return "text-yellow-400";
    return "text-zinc-500";
  };

  return (
    <div className="flex-1 flex flex-col h-full overflow-hidden">
      {/* Search bar */}
      <div className="px-6 py-4 border-b border-zinc-800">
        <div className="flex gap-3">
          <div className="flex-1 relative">
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleSearch()}
              placeholder="Search your documents..."
              className="w-full px-4 py-2.5 bg-[var(--bg-tertiary)] border border-zinc-700 rounded-lg text-sm placeholder-zinc-500 focus:outline-none focus:border-[var(--accent)] transition-colors"
            />
          </div>
          <button
            onClick={handleSearch}
            disabled={searching || !query.trim()}
            className="px-5 py-2.5 bg-[var(--accent)] text-white rounded-lg text-sm font-medium hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {searching ? "Searching..." : "Search"}
          </button>
          {folderPath && (
            <button
              onClick={handleIndex}
              disabled={indexing}
              className="px-4 py-2.5 bg-zinc-700 text-zinc-200 rounded-lg text-sm hover:bg-zinc-600 disabled:opacity-50 transition-colors"
            >
              {indexing ? "Indexing..." : "Rebuild Index"}
            </button>
          )}
        </div>
        {error && (
          <p className="mt-2 text-xs text-red-400">{error}</p>
        )}
      </div>

      {/* Results area */}
      <div className="flex-1 flex overflow-hidden">
        {/* Results list */}
        <div className="flex-1 overflow-y-auto">
          {!hasSearched && (
            <div className="flex items-center justify-center h-full text-zinc-500">
              <div className="text-center">
                <p className="text-lg mb-2">Search your knowledge base</p>
                <p className="text-sm">
                  {folderPath
                    ? "Type a query and press Enter"
                    : "Select a folder first, then build the index"}
                </p>
              </div>
            </div>
          )}

          {hasSearched && results.length === 0 && (
            <div className="flex items-center justify-center h-full text-zinc-500">
              <div className="text-center">
                <p className="text-lg mb-2">No results found</p>
                <p className="text-sm">Try a different query or rebuild the index</p>
              </div>
            </div>
          )}

          {results.map((result, i) => (
            <button
              key={`${result.sidecar}-${i}`}
              onClick={() => handleResultClick(result)}
              className={`w-full text-left px-6 py-4 border-b border-zinc-800/50 hover:bg-zinc-800/50 transition-colors ${
                selectedResult?.sidecar === result.sidecar ? "bg-zinc-800/70" : ""
              }`}
            >
              <div className="flex items-start gap-3">
                <span className={`text-sm font-mono font-bold mt-0.5 ${scoreColor(result.score)}`}>
                  {result.score.toFixed(2)}
                </span>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">{result.title}</p>
                  <p className="text-xs text-zinc-500 truncate mt-0.5">{result.file}</p>
                  {result.topics.length > 0 && (
                    <div className="flex gap-1.5 mt-1.5 flex-wrap">
                      {result.topics.map((topic) => (
                        <span
                          key={topic}
                          className="px-1.5 py-0.5 text-[10px] bg-blue-500/10 text-blue-400 rounded"
                        >
                          {topic}
                        </span>
                      ))}
                    </div>
                  )}
                  {result.snippet && (
                    <p className="text-xs text-zinc-400 mt-1.5 line-clamp-2">{result.snippet}</p>
                  )}
                </div>
              </div>
            </button>
          ))}
        </div>

        {/* Preview panel */}
        {selectedResult && (
          <div className="w-[500px] border-l border-zinc-800 overflow-y-auto bg-[var(--bg-secondary)]">
            <div className="px-5 py-4 border-b border-zinc-800">
              <h3 className="text-sm font-medium">{selectedResult.title}</h3>
              <p className="text-xs text-zinc-500 mt-0.5 truncate">{selectedResult.file}</p>
            </div>
            <div className="px-5 py-4">
              <pre className="text-xs text-zinc-300 whitespace-pre-wrap font-mono leading-relaxed">
                {previewContent ?? "Loading..."}
              </pre>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
