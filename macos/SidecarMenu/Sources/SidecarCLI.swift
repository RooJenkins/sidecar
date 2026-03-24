import Foundation

struct SearchResult: Codable, Hashable {
    let file: String
    let sidecar: String
    let score: Double
    let title: String
    let summary: String
    let topics: [String]
    let snippet: String
}

struct SearchOutput: Codable {
    let query: String
    var results: [SearchResult]
}

struct ScanEvent: Codable {
    let event: String          // "file", "skip", "error", "summary", "done"
    let fileName: String?
    let sourcePath: String?
    let extractor: String?
    let mimeType: String?
    let status: String?
    let reason: String?
    let message: String?
    let processed: Int?
    let skipped: Int?
    let errors: Int?
    let elapsed_seconds: Double?
}

struct StatusResult: Codable {
    let totalFiles: Int
    let trackedFiles: Int
    let staleFiles: Int
    let missingFiles: Int
    let sidecarDiskBytes: Int
    let cacheDiskBytes: Int
    let byExtractor: [String: Int]
}

struct CleanResult: Codable {
    let sidecarFiles: Int
    let indexFiles: Int
    let cacheRemoved: Bool
    let bytesFreed: Int
}

struct IndexResult: Codable {
    let documentCount: Int
    let indexPath: String
    let builtAt: String
}

struct SidecarConfig: Codable {
    var include: [String]?
    var exclude: [String]?
    var maxFileSize: String?
    var outputDir: String?
    var summarize: Bool?
    var provider: String?
    var model: String?
    var apiUrl: String?
    var concurrency: Int?
    var tikaUrl: String?
}

enum SidecarCLIError: LocalizedError {
    case cliNotFound(String)
    case executionFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let path): return "sidecar CLI not found at \(path)"
        case .executionFailed(let msg): return "CLI execution failed: \(msg)"
        case .parseError(let msg): return "Failed to parse CLI output: \(msg)"
        }
    }
}

enum SidecarCLI {
    static func search(query: String, maxResults: Int, cliPath: String) throws -> [SearchResult] {
        let resolvedPath = resolveCLIPath(cliPath)

        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
            throw SidecarCLIError.cliNotFound(resolvedPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = ["search", query, "--json", "--top", String(maxResults)]
        configureProcess(process)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SidecarCLIError.executionFailed(errorMsg)
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()

        guard !data.isEmpty else {
            return []
        }

        let output = try JSONDecoder().decode(SearchOutput.self, from: data)
        return output.results
    }

    /// AI-powered smart search: pipes conversation context via stdin to
    /// `sidecar smart-search --json`, which uses claude to extract focused
    /// queries and returns deduplicated results.
    /// Runs on a background thread — call from a Task.
    static func smartSearch(conversation: String, maxResults: Int, cliPath: String) async throws -> [SearchResult] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let resolvedPath = resolveCLIPath(cliPath)

                    guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
                        continuation.resume(throwing: SidecarCLIError.cliNotFound(resolvedPath))
                        return
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: resolvedPath)
                    process.arguments = ["smart-search", "--json", "--top", String(maxResults)]
                    configureProcess(process)

                    let stdin = Pipe()
                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr

                    try process.run()

                    // Write conversation to stdin and close
                    if let inputData = conversation.data(using: .utf8) {
                        stdin.fileHandleForWriting.write(inputData)
                    }
                    stdin.fileHandleForWriting.closeFile()

                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: SidecarCLIError.executionFailed(errorMsg))
                        return
                    }

                    let data = stdout.fileHandleForReading.readDataToEndOfFile()

                    guard !data.isEmpty else {
                        continuation.resume(returning: [])
                        return
                    }

                    let output = try JSONDecoder().decode(SearchOutput.self, from: data)
                    continuation.resume(returning: output.results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func status(path: String, cliPath: String) throws -> StatusResult {
        let data = try runCLI(args: ["status", path, "--json"], cliPath: cliPath)
        return try JSONDecoder().decode(StatusResult.self, from: data)
    }

    static func clean(path: String, cliPath: String) throws -> CleanResult {
        let data = try runCLI(args: ["clean", path, "--json"], cliPath: cliPath)
        return try JSONDecoder().decode(CleanResult.self, from: data)
    }

    static func index(paths: [String], cliPath: String) throws -> IndexResult {
        let args = ["index"] + paths + ["--json"]
        let data = try runCLI(args: args, cliPath: cliPath)
        return try JSONDecoder().decode(IndexResult.self, from: data)
    }

    static func scan(path: String, options: SidecarConfig? = nil, apiKey: String? = nil, cliPath: String) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let resolvedPath = resolveCLIPath(cliPath)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolvedPath)

            var args = ["scan", path, "--json-stream"]
            if let opts = options {
                if let include = opts.include {
                    for pattern in include { args += ["--include", pattern] }
                }
                if let exclude = opts.exclude {
                    for pattern in exclude { args += ["--exclude", pattern] }
                }
                if let outputDir = opts.outputDir { args += ["--output-dir", outputDir] }
                if opts.summarize == true { args.append("--summarize") }
                if let provider = opts.provider { args += ["--provider", provider] }
                if let model = opts.model { args += ["--model", model] }
                if let apiUrl = opts.apiUrl { args += ["--api-url", apiUrl] }
                if let concurrency = opts.concurrency { args += ["--concurrency", String(concurrency)] }
            }
            if let apiKey, !apiKey.isEmpty { args += ["--api-key", apiKey] }
            process.arguments = args
            configureProcess(process)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let decoder = JSONDecoder()
            var buffer = Data()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)

                // Split on newlines and parse each complete line
                while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                    guard !lineData.isEmpty else { continue }
                    if let event = try? decoder.decode(ScanEvent.self, from: lineData) {
                        continuation.yield(event)
                    }
                }
            }

            process.terminationHandler = { _ in
                stdout.fileHandleForReading.readabilityHandler = nil
                // Parse any remaining buffer
                if !buffer.isEmpty, let event = try? decoder.decode(ScanEvent.self, from: buffer) {
                    continuation.yield(event)
                }
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.finish()
            }
        }
    }

    static func readSidecarFile(sourcePath: String) -> String? {
        let sidecarPath = sourcePath + ".sidecar.md"
        return try? String(contentsOfFile: sidecarPath, encoding: .utf8)
    }

    static func loadConfig(dir: String) -> SidecarConfig? {
        let configPath = (dir as NSString).appendingPathComponent(".sidecarrc")
        guard let data = FileManager.default.contents(atPath: configPath) else { return nil }
        return try? JSONDecoder().decode(SidecarConfig.self, from: data)
    }

    static func saveConfig(dir: String, config: SidecarConfig) throws {
        let configPath = (dir as NSString).appendingPathComponent(".sidecarrc")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: configPath))
    }

    /// Returns the sidecar CLI version string, or nil if not found.
    static func version(cliPath: String) -> String? {
        let resolvedPath = resolveCLIPath(cliPath)
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = ["--version"]
        configureProcess(process)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runCLI(args: [String], cliPath: String) throws -> Data {
        let resolvedPath = resolveCLIPath(cliPath)
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
            throw SidecarCLIError.cliNotFound(resolvedPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = args
        configureProcess(process)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SidecarCLIError.executionFailed(errorMsg)
        }

        return stdout.fileHandleForReading.readDataToEndOfFile()
    }

    /// Environment with a complete PATH so node/sidecar can be found from .app context.
    static let shellEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment

        // Resolve the user's login shell PATH without using waitUntilExit()
        // (which pumps the run loop and causes re-entrancy crashes with SwiftUI).
        let shell = env["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-ilc", "echo $PATH"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = Pipe()

        let semaphore = DispatchSemaphore(value: 0)
        probe.terminationHandler = { _ in semaphore.signal() }

        do {
            try probe.run()
            // Wait up to 5 seconds on a background queue — NOT the run loop
            let result = semaphore.wait(timeout: .now() + 5)
            if result == .success,
               let resolved = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !resolved.isEmpty {
                env["PATH"] = resolved
                return env
            }
        } catch {}

        // Fallback: prepend common locations
        let extra = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            NSHomeDirectory() + "/.local/bin",
        ].joined(separator: ":")
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        return env
    }()

    static func configureProcess(_ process: Process) {
        process.environment = shellEnvironment
    }

    static func resolveCLIPath(_ path: String) -> String {
        if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        // Try common locations
        let candidates = [
            "/usr/local/bin/sidecar",
            "/opt/homebrew/bin/sidecar",
            NSHomeDirectory() + "/.local/bin/sidecar",
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Fall back to which
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["sidecar"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()

        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return result.isEmpty ? path : result
    }
}
