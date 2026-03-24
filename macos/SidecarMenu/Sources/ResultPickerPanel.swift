import AppKit
import SwiftUI
import Combine

/// Observable model for the picker — allows updating results after initial display.
final class PickerModel: ObservableObject {
    @Published var results: [SearchResult]
    @Published var isRefining = false

    init(results: [SearchResult]) {
        self.results = results
    }
}

/// Floating panel that shows smart search results and lets the user
/// one-click attach the original file or its .sidecar.md to the chat.
final class ResultPickerPanel {
    private var panel: NSPanel?
    private let model: PickerModel
    private let onDismiss: () -> Void
    private var previousApp: NSRunningApplication?
    private var previewWindow: NSWindow?

    init(results: [SearchResult], onDismiss: @escaping () -> Void) {
        self.model = PickerModel(results: results)
        self.onDismiss = onDismiss
    }

    /// Update results (e.g. after AI filtering completes).
    @MainActor
    func updateResults(_ results: [SearchResult]) {
        model.isRefining = false
        model.results = results
        // Resize panel to fit new result count
        if let panel = panel {
            let height = min(CGFloat(results.count) * 72 + 52, 440)
            var frame = panel.frame
            let oldHeight = frame.height
            frame.size.height = height
            frame.origin.y += (oldHeight - height) // keep top edge fixed
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    /// Show that AI refinement is in progress.
    @MainActor
    func setRefining(_ refining: Bool) {
        model.isRefining = refining
    }

    @MainActor
    func show() {
        guard let screen = NSScreen.main else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        let height = min(CGFloat(model.results.count) * 72 + 52, 440)
        let width: CGFloat = 480

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Sidecar — Attach Documents"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true

        let pickerView = ResultPickerView(
            model: model,
            onAttach: { [weak self] filePath in
                self?.attachFile(path: filePath)
            },
            onPreview: { [weak self] result in
                self?.showPreview(for: result)
            },
            onDone: { [weak self] in
                self?.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: pickerView)

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.previousApp?.activate()
        }
    }

    @MainActor
    func dismiss() {
        previewWindow?.close()
        previewWindow = nil
        panel?.close()
        panel = nil
        onDismiss()
    }

    // MARK: - Preview

    @MainActor
    private func showPreview(for result: SearchResult) {
        previewWindow?.close()

        let content = loadPreviewContent(for: result)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = result.title
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let previewView = PreviewContentView(
            title: result.title,
            filePath: result.file,
            content: content,
            onClose: { [weak self] in
                self?.previewWindow?.close()
                self?.previewWindow = nil
            }
        )
        window.contentView = NSHostingView(rootView: previewView)

        if let pickerFrame = panel?.frame {
            let x = pickerFrame.maxX + 8
            let y = pickerFrame.origin.y
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFrontRegardless()
        previewWindow = window
    }

    private func loadPreviewContent(for result: SearchResult) -> String {
        if let sidecar = SidecarCLI.readSidecarFile(sourcePath: result.file) {
            return sidecar
        }
        var parts: [String] = []
        if !result.summary.isEmpty { parts.append(result.summary) }
        if !result.snippet.isEmpty { parts.append(result.snippet) }
        parts.append("\nSource: \(result.file)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Attach (queued)

    private var attachQueue: [String] = []
    private var isProcessingAttach = false

    private func attachFile(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.log("File not found: \(path)", source: "Picker")
            return
        }

        attachQueue.append(path)
        processNextAttach()
    }

    private func processNextAttach() {
        guard !isProcessingAttach, !attachQueue.isEmpty else { return }
        isProcessingAttach = true

        let path = attachQueue.removeFirst()
        let url = URL(fileURLWithPath: path)

        previousApp?.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            let source = CGEventSource(stateID: .hidSystemState)

            // Cmd+Down to deselect
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7D, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7D, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([url as NSURL])
                Logger.log("File on clipboard: \(path)", source: "Picker")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                       let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                        keyDown.flags = .maskCommand
                        keyUp.flags = .maskCommand
                        keyDown.post(tap: .cghidEventTap)
                        keyUp.post(tap: .cghidEventTap)
                    }

                    // Wait for paste to complete, then process next in queue
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        self?.isProcessingAttach = false
                        self?.processNextAttach()
                    }
                }
            }
        }
    }
}

// MARK: - Picker View

private struct ResultPickerView: View {
    @ObservedObject var model: PickerModel
    let onAttach: (String) -> Void
    let onPreview: (SearchResult) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)

                if model.isRefining {
                    HStack(spacing: 6) {
                        Text("\(model.results.count) candidate\(model.results.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        ProgressView()
                            .controlSize(.mini)
                        Text("refining...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                } else {
                    Text("\(model.results.count) document\(model.results.count == 1 ? "" : "s") found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(model.results.enumerated()), id: \.element.file) { _, result in
                        ResultRow(result: result, onAttach: onAttach, onPreview: onPreview)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.25), value: model.results.map(\.file))
            }
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Result Row

private struct ResultRow: View {
    let result: SearchResult
    let onAttach: (String) -> Void
    let onPreview: (SearchResult) -> Void
    @State private var attachedOriginal = false
    @State private var attachedMd = false
    @State private var isExpanded = false
    @State private var isHoveringTitle = false
    @State private var isHoveringPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                // Clickable title — expands/collapses summary inline
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(result.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    if !isExpanded {
                        Text(result.summary.isEmpty ? result.file : result.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .onHover { isHoveringTitle = $0 }
                .cursor(isHoveringTitle ? .pointingHand : .arrow)

                // Full preview button
                Button(action: { onPreview(result) }) {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue.opacity(isHoveringPreview ? 1 : 0.5))
                }
                .buttonStyle(.plain)
                .onHover { isHoveringPreview = $0 }
                .cursor(isHoveringPreview ? .pointingHand : .arrow)
                .help("Open full preview")

                // Attach buttons
                Button(action: {
                    onAttach(result.file)
                    attachedOriginal = true
                }) {
                    HStack(spacing: 3) {
                        if attachedOriginal { Image(systemName: "checkmark") }
                        Text("Original")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(attachedOriginal ? .green : nil)

                Button(action: {
                    onAttach(result.sidecar)
                    attachedMd = true
                }) {
                    HStack(spacing: 3) {
                        if attachedMd { Image(systemName: "checkmark") }
                        Text(".md")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(attachedMd ? .green : nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Expanded summary
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !result.summary.isEmpty {
                        Text(result.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.85))
                            .textSelection(.enabled)
                    }
                    if !result.snippet.isEmpty && result.snippet != result.summary {
                        Text(result.snippet)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text(result.file)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .textSelection(.enabled)
                    if !result.topics.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(result.topics, id: \.self) { topic in
                                Text(topic)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, 30) // indent under chevron
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Preview Content View

private struct PreviewContentView: View {
    let title: String
    let filePath: String
    let content: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(filePath)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Text(content)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .cursor(.arrow)
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
