import AppKit
import SwiftUI
import Combine

/// Floating panel for voice Q&A: listening → searching → answer with follow-ups.
final class VoiceAnswerPanel {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    func show() {
        // If the panel still exists and is visible, just bring it forward
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Panel was closed externally or doesn't exist — recreate
        panel = nil

        guard let screen = NSScreen.main else { return }

        // Fixed size panel — no resizing, no jumping. Content adapts inside.
        let width: CGFloat = 500
        let height: CGFloat = 460

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 400, height: 300)
        panel.title = "Sidecar Q&A"

        panel.titlebarAppearsTransparent = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false

        let view = VoiceAnswerView(
            voiceQA: VoiceQA.shared,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: view)

        // Fixed position: top-center, never moves
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    @MainActor
    func dismissPanel() {
        panel?.close()
        panel = nil
        cancellables.removeAll()
    }

    @MainActor
    func dismiss() {
        dismissPanel()
        VoiceQA.shared.dismiss()
    }
}

// MARK: - SwiftUI View

struct VoiceAnswerView: View {
    @ObservedObject var voiceQA: VoiceQA
    let onDismiss: () -> Void
    @State private var followUpText = ""
    @State private var visibleSourceCount = 0
    @State private var sourceRevealTimer: Timer?
    @State private var showingContextPreview = false
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            switch voiceQA.state {
            case .idle:
                EmptyView()
            case .loading:
                statusView(icon: "arrow.down.circle", text: "Loading model...")
            case .listening:
                listeningView
            case .transcribing:
                statusView(icon: "waveform", text: "Transcribing...")
            case .searching:
                progressView(icon: "magnifyingglass", status: "Searching documents...")
            case .answering:
                progressView(icon: "brain", status: "Generating answer...")
            case .done(let answer, let sources, let knowledgeBlocks):
                answerView(answer: answer, sources: sources, knowledgeBlocks: knowledgeBlocks)
            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Listening

    private var listeningView: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .font(.title2)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text("Listening... release to search")
                    .font(.headline)
            }

            Spacer()

            HStack(spacing: 1) {
                ForEach(Array(voiceQA.bufferEnergy.suffix(20).enumerated()), id: \.offset) { _, energy in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(energy > 0.3 ? Color.red : Color.secondary.opacity(0.3))
                        .frame(width: 2, height: CGFloat(max(4, energy * 30)))
                }
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Status

    private func statusView(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func progressView(icon: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with dismiss
            HStack {
                Text("Sidecar Q&A")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Show the transcribed question
            if !voiceQA.partialTranscription.isEmpty {
                questionBubble(voiceQA.partialTranscription)
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Answer

    private func answerView(answer: String, sources: [SearchResult], knowledgeBlocks: [String]) -> some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Sidecar Q&A")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Divider()

            // Chat history
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Previous Q&A pairs
                        ForEach(Array(voiceQA.conversationHistory.enumerated()), id: \.offset) { i, pair in
                            questionBubble(pair.question)
                            answerBubble(pair.answer)
                        }

                        // Current question
                        if !voiceQA.partialTranscription.isEmpty {
                            let isOldQuestion = voiceQA.conversationHistory.last?.question == voiceQA.partialTranscription
                            if !isOldQuestion {
                                questionBubble(voiceQA.partialTranscription)
                            }
                        }

                        // Current answer / loading
                        if !knowledgeBlocks.isEmpty && answer.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(knowledgeBlocks.prefix(3).enumerated()), id: \.offset) { _, block in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.caption2)
                                        Text(block).font(.callout)
                                    }
                                }
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Generating answer...").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if !answer.isEmpty {
                            answerBubble(answer)
                        }

                        // Interactive file cards
                        if !sources.isEmpty {
                            let showCount = answer.isEmpty ? visibleSourceCount : sources.count
                            ForEach(Array(sources.prefix(showCount).enumerated()), id: \.element.file) { i, source in
                                FileCard(source: source)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: voiceQA.conversationHistory.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: answer) { _, _ in
                    visibleSourceCount = sources.count
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: sources.count) { _, newCount in
                    // Stagger source cards appearing one by one
                    if newCount > 0 && answer.isEmpty {
                        visibleSourceCount = 0
                        sourceRevealTimer?.invalidate()
                        var count = 0
                        sourceRevealTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
                            count += 1
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    visibleSourceCount = count
                                }
                                if count >= newCount { timer.invalidate() }
                            }
                        }
                    }
                }
            }

            // Context preview
            if showingContextPreview && !voiceQA.injectedContext.isEmpty {
                Divider()
                ScrollView {
                    Text(voiceQA.injectedContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color.secondary.opacity(0.04))
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                if !voiceQA.injectedContext.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 9))
                        Text("Context")
                            .font(.caption2)
                        Button(action: {
                            voiceQA.injectedContext = ""
                            showingContextPreview = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(showingContextPreview ? Color.accentColor.opacity(0.2) : Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                    .onTapGesture { showingContextPreview.toggle() }
                }

                Label("Hold ⌘J", systemImage: "mic")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 65)

                TextField("Type a follow-up...", text: $followUpText)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .focused($textFieldFocused)
                    .onSubmit {
                        guard !followUpText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        voiceQA.submitTextQuestion(followUpText)
                        followUpText = ""
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            textFieldFocused = true
                        }
                    }
                    .onChange(of: voiceQA.focusTrigger) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            textFieldFocused = true
                        }
                    }
                    .onChange(of: voiceQA.pendingInput) { _, newValue in
                        if !newValue.isEmpty {
                            followUpText = newValue
                            voiceQA.pendingInput = ""
                        }
                    }

                Button("Send") {
                    voiceQA.submitTextQuestion(followUpText)
                    followUpText = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Chat Bubbles

    private func questionBubble(_ text: String) -> some View {
        HStack {
            Spacer()
            HStack(alignment: .top, spacing: 6) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true) // Show full text, never truncate
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.caption2)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 350, alignment: .trailing)
        }
    }

    private func answerBubble(_ text: String) -> some View {
        HStack {
            Text(markdownToAttributed(text))
                .font(.callout)
                .textSelection(.enabled)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer()
        }
    }

    private func markdownToAttributed(_ text: String) -> AttributedString {
        // Convert block-level markdown (headers, bullets) to inline-friendly format
        let cleaned = text
            .replacingOccurrences(of: #"(?m)^#{1,4}\s+(.+)$"#, with: "**$1**", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^[-*]\s+"#, with: "• ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\d+\.\s+"#, with: "", options: .regularExpression)
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message).font(.body)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - File Card

struct FileCard: View {
    let source: SearchResult
    @State private var isHovering = false
    @State private var copied: String?

    private var fileURL: URL { URL(fileURLWithPath: source.file) }
    private var fileName: String { fileURL.deletingPathExtension().lastPathComponent }
    private var fileIcon: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc": return "doc.text.fill"
        case "xlsx", "xls": return "tablecells.fill"
        case "csv": return "tablecells"
        case "pptx", "ppt": return "rectangle.fill.on.rectangle.fill"
        case "md": return "text.document.fill"
        case "txt": return "doc.plaintext.fill"
        case "eml", "msg": return "envelope.fill"
        case "rtf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo.fill"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "mp4", "mov", "avi": return "film.fill"
        case "json", "xml", "yaml", "yml": return "curlybraces"
        case "html", "htm": return "globe"
        case "swift", "ts", "js", "py": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf": return .red
        case "docx", "doc": return .blue
        case "xlsx", "xls", "csv": return .green
        case "pptx", "ppt": return .orange
        case "md", "txt", "rtf": return .secondary
        case "eml", "msg": return .purple
        case "png", "jpg", "jpeg", "gif", "webp": return .teal
        case "mp3", "wav", "m4a", "aac": return .pink
        case "mp4", "mov", "avi": return .indigo
        case "html", "htm": return .cyan
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title.isEmpty ? fileName : source.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(abbreviatePath(source.file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .onTapGesture { openPreview() }

            Spacer()

            if isHovering || copied != nil {
                HStack(spacing: 4) {
                    if let copied = copied {
                        Text(copied)
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else {
                        // Preview document
                        Button(action: openPreview) {
                            Image(systemName: "eye")
                                .help("Preview document")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        // Copy sidecar markdown
                        Button(action: copySidecarMarkdown) {
                            Text("md")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .help("Copy sidecar summary")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        // Copy original file
                        Button(action: copyOriginalFile) {
                            Image(systemName: "doc.on.clipboard")
                                .help("Copy file to clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        // Reveal in Finder
                        Button(action: revealInFinder) {
                            Image(systemName: "folder")
                                .help("Show in Finder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .onHover { isHovering = $0 }
        .onDrag {
            // Use onDrag instead of draggable — avoids conflicts with window dragging
            NSItemProvider(object: fileURL as NSURL)
        }
    }

    private func openPreview() {
        NSWorkspace.shared.open(fileURL)
    }

    private func copySidecarMarkdown() {
        if let content = SidecarCLI.readSidecarFile(sourcePath: source.file) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            flashCopied("Copied")
        } else {
            flashCopied("No sidecar")
        }
    }

    private func copyOriginalFile() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fileURL as NSURL])
        flashCopied("Copied")
    }

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(source.file, inFileViewerRootedAtPath: "")
    }

    private func flashCopied(_ msg: String) {
        withAnimation { copied = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copied = nil }
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
