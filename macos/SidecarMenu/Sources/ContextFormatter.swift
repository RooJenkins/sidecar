import Foundation

enum ContextFormatter {
    static func format(results: [SearchResult]) -> String {
        var lines: [String] = []
        lines.append("<company_context>")

        for result in results {
            lines.append("  <document>")
            lines.append("    <title>\(escapeXML(result.title))</title>")
            lines.append("    <source>\(escapeXML(result.file))</source>")
            lines.append("    <relevance>\(String(format: "%.2f", result.score))</relevance>")

            if !result.topics.isEmpty {
                lines.append("    <topics>\(escapeXML(result.topics.joined(separator: ", ")))</topics>")
            }

            if !result.summary.isEmpty {
                lines.append("    <summary>\(escapeXML(result.summary))</summary>")
            }

            // For high-relevance results, include the full sidecar content
            // instead of just the snippet — much richer context for the AI
            if result.score >= 0.3, let content = loadSidecarContent(for: result.file) {
                lines.append("    <content>\(escapeXML(content))</content>")
            } else if !result.snippet.isEmpty {
                lines.append("    <snippet>\(escapeXML(result.snippet))</snippet>")
            }

            lines.append("  </document>")
        }

        lines.append("</company_context>")
        return lines.joined(separator: "\n")
    }

    /// Load the sidecar markdown content, stripping the YAML frontmatter
    private static func loadSidecarContent(for sourcePath: String) -> String? {
        guard let raw = SidecarCLI.readSidecarFile(sourcePath: sourcePath) else { return nil }

        // Strip YAML frontmatter (between --- delimiters)
        let stripped: String
        if raw.hasPrefix("---") {
            if let endRange = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 3)..<raw.endIndex) {
                stripped = String(raw[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                stripped = raw
            }
        } else {
            stripped = raw
        }

        // Truncate to ~4000 chars to keep injected context reasonable
        if stripped.count > 4000 {
            return String(stripped.prefix(4000)) + "\n..."
        }
        return stripped.isEmpty ? nil : stripped
    }

    private static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
