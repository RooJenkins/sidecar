import { useState, useCallback } from "react";
import type { ScanEvent, FileEntry, ScanPhase } from "../lib/types";

interface ScanState {
  phase: ScanPhase;
  files: FileEntry[];
  processed: number;
  skipped: number;
  errors: number;
  elapsed: number;
}

export function useScanEvents() {
  const [state, setState] = useState<ScanState>({
    phase: "idle",
    files: [],
    processed: 0,
    skipped: 0,
    errors: 0,
    elapsed: 0,
  });

  const reset = useCallback(() => {
    setState({
      phase: "idle",
      files: [],
      processed: 0,
      skipped: 0,
      errors: 0,
      elapsed: 0,
    });
  }, []);

  const startScan = useCallback(() => {
    setState((s) => ({ ...s, phase: "scanning", files: [], processed: 0, skipped: 0, errors: 0, elapsed: 0 }));
  }, []);

  const handleEvent = useCallback((event: ScanEvent) => {
    setState((prev) => {
      switch (event.event) {
        case "file":
          return {
            ...prev,
            processed: prev.processed + 1,
            files: [
              ...prev.files,
              {
                fileName: event.fileName ?? "",
                sourcePath: event.sourcePath ?? "",
                extractor: event.extractor ?? "",
                mimeType: event.mimeType ?? "",
                status: "processed" as const,
              },
            ],
          };
        case "skip":
          return {
            ...prev,
            skipped: prev.skipped + 1,
            files: [
              ...prev.files,
              {
                fileName: event.sourcePath?.split("/").pop() ?? "",
                sourcePath: event.sourcePath ?? "",
                extractor: "",
                mimeType: "",
                status: "skipped" as const,
                reason: event.reason,
              },
            ],
          };
        case "error":
          return {
            ...prev,
            errors: prev.errors + 1,
            files: [
              ...prev.files,
              {
                fileName: event.sourcePath?.split("/").pop() ?? "",
                sourcePath: event.sourcePath ?? "",
                extractor: "",
                mimeType: "",
                status: "error" as const,
                message: event.message,
              },
            ],
          };
        case "done":
          return {
            ...prev,
            phase: "complete",
            processed: event.processed ?? prev.processed,
            skipped: event.skipped ?? prev.skipped,
            errors: event.errors ?? prev.errors,
            elapsed: event.elapsed_seconds ?? 0,
          };
        default:
          return prev;
      }
    });
  }, []);

  return { state, handleEvent, startScan, reset };
}
