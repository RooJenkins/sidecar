import Foundation
import Observation

struct WatchState {
    var phase: String = "idle"  // "idle", "watching", "error"
    var processedCount: Int = 0
    var errorCount: Int = 0
    var lastEventTime: Date?
    var errorMessage: String?
    fileprivate var process: Process?
}

@Observable
final class WatchManager {
    static let shared = WatchManager()

    var watchedPaths: [String: WatchState] = [:]

    var activeCount: Int {
        watchedPaths.values.filter { $0.phase == "watching" }.count
    }

    private init() {}

    func startWatching(path: String, cliPath: String) {
        // Already watching this path
        if watchedPaths[path]?.phase == "watching" { return }

        let resolvedCLI = SidecarCLI.resolveCLIPath(cliPath)
        guard FileManager.default.isExecutableFile(atPath: resolvedCLI) else {
            watchedPaths[path] = WatchState(phase: "error", errorMessage: "CLI not found at \(resolvedCLI)")
            Logger.log("Watch failed: CLI not found at \(resolvedCLI)", source: "Watch")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedCLI)

        var args = ["scan", path, "--watch", "--json-stream"]

        // Load per-folder config
        if let config = SidecarCLI.loadConfig(dir: path) {
            if let include = config.include {
                for pattern in include { args += ["--include", pattern] }
            }
            if let exclude = config.exclude {
                for pattern in exclude { args += ["--exclude", pattern] }
            }
            if let outputDir = config.outputDir { args += ["--output-dir", outputDir] }
            if config.summarize == true { args.append("--summarize") }
            if let provider = config.provider { args += ["--provider", provider] }
            if let model = config.model { args += ["--model", model] }
            if let apiUrl = config.apiUrl { args += ["--api-url", apiUrl] }
            if let concurrency = config.concurrency { args += ["--concurrency", String(concurrency)] }

            // API key from Keychain
            let provider = config.provider ?? "claude"
            if let apiKey = KeychainHelper.load(key: "apiKey-\(provider)"), !apiKey.isEmpty {
                args += ["--api-key", apiKey]
            }
        }

        process.arguments = args
        SidecarCLI.configureProcess(process)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let state = WatchState(phase: "watching", process: process)
        watchedPaths[path] = state

        let decoder = JSONDecoder()
        var buffer = Data()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard !lineData.isEmpty,
                      let event = try? decoder.decode(ScanEvent.self, from: lineData) else { continue }

                DispatchQueue.main.async {
                    self?.handleEvent(event, for: path)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard var s = self?.watchedPaths[path], s.phase == "watching" else { return }
                if proc.terminationStatus == 0 {
                    s.phase = "idle"
                } else {
                    s.phase = "error"
                    s.errorMessage = "Process exited with code \(proc.terminationStatus)"
                }
                s.process = nil
                self?.watchedPaths[path] = s
                Logger.log("Watch ended for \(path) (exit \(proc.terminationStatus))", source: "Watch")
            }
        }

        do {
            try process.run()
            Logger.log("Started watching \(path)", source: "Watch")
        } catch {
            watchedPaths[path] = WatchState(phase: "error", errorMessage: error.localizedDescription)
            Logger.log("Watch failed for \(path): \(error)", source: "Watch")
        }
    }

    func stopWatching(path: String) {
        guard var state = watchedPaths[path] else { return }
        state.process?.terminate()
        state.process = nil
        state.phase = "idle"
        watchedPaths[path] = state
        Logger.log("Stopped watching \(path)", source: "Watch")
    }

    func stopAll() {
        for path in watchedPaths.keys {
            stopWatching(path: path)
        }
        watchedPaths.removeAll()
    }

    func isWatching(_ path: String) -> Bool {
        watchedPaths[path]?.phase == "watching"
    }

    // Debounced index rebuild — waits 5s after last file event before rebuilding
    private var reindexWorkItem: DispatchWorkItem?

    private func handleEvent(_ event: ScanEvent, for path: String) {
        guard var state = watchedPaths[path] else { return }
        state.lastEventTime = Date()

        switch event.event {
        case "file":
            state.processedCount += 1
            Logger.log("Watch updated: \(event.fileName ?? "unknown") in \(path)", source: "Watch")
            scheduleReindex(path: path)
        case "error":
            state.errorCount += 1
            Logger.log("Watch error: \(event.message ?? "unknown") for \(event.fileName ?? "?") in \(path)", source: "Watch")
        default:
            break
        }

        watchedPaths[path] = state
    }

    private func scheduleReindex(path: String) {
        reindexWorkItem?.cancel()
        let cli = SettingsManager.shared.cliPath
        let item = DispatchWorkItem {
            do {
                _ = try SidecarCLI.index(paths: [path], cliPath: cli)
                Logger.log("Index rebuilt after watch update in \(path)", source: "Watch")
            } catch {
                Logger.log("Index rebuild failed: \(error)", source: "Watch")
            }
        }
        reindexWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: item)
    }
}
