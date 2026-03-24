import AppKit

/// Reads text content from the frontmost application's window using the Accessibility API.
/// This avoids keyboard simulation (Escape/Tab) which doesn't work reliably across apps.
enum AccessibilityReader {

    /// Recursively extract all visible text from the focused app's window.
    /// Returns the concatenated text content, which typically includes conversation history.
    static func readWindowText() -> String? {
        guard AXIsProcessTrusted() else {
            Logger.log("AX not trusted", source: "AXReader")
            return nil
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused window
        var windowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard windowResult == .success, let window = windowValue else {
            Logger.log("Could not get focused window", source: "AXReader")
            return nil
        }

        // Recursively collect text from all children
        var texts: [String] = []
        collectText(from: window as! AXUIElement, into: &texts, depth: 0, maxDepth: 15)

        let combined = texts.joined(separator: "\n")
        Logger.log("AX read \(combined.count) chars from \(texts.count) elements", source: "AXReader")

        return combined.isEmpty ? nil : combined
    }

    private static func collectText(from element: AXUIElement, into texts: inout [String], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        // Try to get the value (text content)
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            texts.append(text)
        }

        // Also try the title
        var title: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success,
           let titleStr = title as? String, !titleStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Avoid duplicating text already captured as value
            if value as? String != titleStr {
                texts.append(titleStr)
            }
        }

        // Recurse into children
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childArray = children as? [AXUIElement] {
            for child in childArray {
                collectText(from: child, into: &texts, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }
}
