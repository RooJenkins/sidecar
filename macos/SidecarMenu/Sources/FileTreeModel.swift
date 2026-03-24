import Foundation
import Observation

enum SidecarStatus: String, CaseIterable {
    case upToDate = "Up to Date"
    case stale = "Stale"
    case missing = "Missing"
}

struct SidecarMeta {
    let processedAt: Date?
    let extractor: String
    let wordCount: Int
    let hasAISummary: Bool
}

struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]?
    var sidecarStatus: SidecarStatus?
    var sidecarMeta: SidecarMeta?
    var sourceModified: Date?

    /// Aggregate status for directories
    var aggregateStatus: SidecarStatus? {
        guard isDirectory, let children else { return nil }
        let allStatuses = children.flatMap { collectStatuses($0) }
        if allStatuses.contains(.missing) { return .missing }
        if allStatuses.contains(.stale) { return .stale }
        if allStatuses.allSatisfy({ $0 == .upToDate }) && !allStatuses.isEmpty { return .upToDate }
        return nil
    }

    var hasAISummary: Bool {
        sidecarMeta?.hasAISummary ?? false
    }

    private func collectStatuses(_ node: FileNode) -> [SidecarStatus] {
        if node.isDirectory {
            return node.children?.flatMap { collectStatuses($0) } ?? []
        }
        return [node.sidecarStatus].compactMap { $0 }
    }
}

@Observable
final class FileTreeModel {
    var root: [FileNode] = []
    var isLoading = false
    var counts: (upToDate: Int, stale: Int, missing: Int, aiSummary: Int) = (0, 0, 0, 0)

    func load(folderPath: String) {
        guard !folderPath.isEmpty else {
            root = []
            return
        }
        isLoading = true
        let path = folderPath
        Task.detached {
            let nodes = Self.walkDirectory(path)
            let c = Self.countStatuses(nodes)
            await MainActor.run {
                self.root = nodes
                self.counts = c
                self.isLoading = false
            }
        }
    }

    private static func countStatuses(_ nodes: [FileNode]) -> (upToDate: Int, stale: Int, missing: Int, aiSummary: Int) {
        var up = 0, stale = 0, missing = 0, ai = 0
        func walk(_ node: FileNode) {
            if node.isDirectory {
                node.children?.forEach { walk($0) }
            } else {
                switch node.sidecarStatus {
                case .upToDate: up += 1
                case .stale: stale += 1
                case .missing: missing += 1
                case .none: break
                }
                if node.hasAISummary { ai += 1 }
            }
        }
        nodes.forEach { walk($0) }
        return (up, stale, missing, ai)
    }

    private static func walkDirectory(_ path: String) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        var nodes: [FileNode] = []

        for name in contents.sorted() {
            // Skip hidden files, sidecar artifacts, temp files, unsupported formats
            if name.hasPrefix(".") { continue }
            if name.hasPrefix("~$") { continue }           // Word temp/lock files
            if name.hasSuffix(".sidecar.md") { continue }
            if name == "SIDECAR.md" { continue }            // sidecar index file
            if name == ".sidecar" { continue }
            if name == "node_modules" { continue }
            if name == ".git" { continue }

            let ext = (name as NSString).pathExtension.lowercased()
            let unsupportedExts: Set = ["zip", "gz", "tar", "rar", "7z", "avif", "webp",
                                         "png", "jpg", "jpeg", "gif", "bmp", "ico", "svg",
                                         "mp3", "mp4", "mov", "avi", "mkv", "wav",
                                         "exe", "dmg", "app", "dylib", "o", "a"]
            if unsupportedExts.contains(ext) { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                // Skip macOS bundle types that look like directories
                if name.hasSuffix(".rtfd") { continue }
                let children = walkDirectory(fullPath)
                // Skip empty directories
                if children.isEmpty { continue }
                nodes.append(FileNode(
                    name: name, path: fullPath, isDirectory: true,
                    children: children
                ))
            } else {
                let sidecarPath = fullPath + ".sidecar.md"
                let sourceAttrs = try? fm.attributesOfItem(atPath: fullPath)
                let sourceModified = sourceAttrs?[.modificationDate] as? Date

                if fm.fileExists(atPath: sidecarPath) {
                    let meta = parseSidecarFrontmatter(sidecarPath)
                    let status: SidecarStatus
                    if let processedAt = meta.processedAt, let srcMod = sourceModified {
                        status = srcMod > processedAt ? .stale : .upToDate
                    } else {
                        status = .upToDate
                    }
                    nodes.append(FileNode(
                        name: name, path: fullPath, isDirectory: false,
                        sidecarStatus: status, sidecarMeta: meta,
                        sourceModified: sourceModified
                    ))
                } else {
                    nodes.append(FileNode(
                        name: name, path: fullPath, isDirectory: false,
                        sidecarStatus: .missing, sourceModified: sourceModified
                    ))
                }
            }
        }

        // Sort: directories first, then alphabetical
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func parseSidecarFrontmatter(_ path: String) -> SidecarMeta {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return SidecarMeta(processedAt: nil, extractor: "", wordCount: 0, hasAISummary: false)
        }

        // Parse YAML frontmatter between --- delimiters
        guard content.hasPrefix("---") else {
            return SidecarMeta(processedAt: nil, extractor: "", wordCount: 0, hasAISummary: false)
        }

        let lines = content.components(separatedBy: "\n")
        var extractor = ""
        var wordCount = 0
        var hasAISummary = false
        var processedAt: Date?

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        for i in 1..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }

            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch key {
            case "extractor": extractor = value
            case "word_count": wordCount = Int(value) ?? 0
            case "has_ai_summary": hasAISummary = value == "true"
            case "processed_at":
                processedAt = isoFormatter.date(from: value) ?? isoFormatterNoFrac.date(from: value)
            default: break
            }
        }

        return SidecarMeta(processedAt: processedAt, extractor: extractor, wordCount: wordCount, hasAISummary: hasAISummary)
    }
}
