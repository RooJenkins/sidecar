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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 400, height: 300)
        panel.title = "Sidecar Q&A"

        panel.isFloatingPanel = true
        panel.level = .floating
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

// MARK: - SwiftUI View (Unified layout: chat + input always visible)

struct VoiceAnswerView: View {
    @ObservedObject var voiceQA: VoiceQA
    let onDismiss: () -> Void
    @State private var followUpText = ""
    @State private var visibleSourceCount = 0
    @State private var sourceRevealTimer: Timer?
    @State private var showingContextPreview = false
    @FocusState private var textFieldFocused: Bool

    private var isRecording: Bool {
        if case .listening = voiceQA.state { return true }
        return false
    }

    private var isBusy: Bool {
        switch voiceQA.state {
        case .loading, .transcribing, .searching, .answering: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat area — always visible
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Conversation history with attachments + inline docs
                        ForEach(Array(voiceQA.conversationHistory.enumerated()), id: \.offset) { _, entry in
                            // Attachments shown above the question
                            if !entry.attachments.isEmpty {
                                attachmentChips(entry.attachments)
                            }
                            questionBubble(entry.question)
                            answerBubble(entry.answer)
                            if !entry.sources.isEmpty {
                                docStrip(entry.sources)
                            }
                        }

                        // Current question (if not yet in history)
                        if !voiceQA.partialTranscription.isEmpty {
                            let isOld = voiceQA.conversationHistory.last?.question == voiceQA.partialTranscription
                            if !isOld {
                                questionBubble(voiceQA.partialTranscription)
                            }
                        }

                        // Inline status indicators
                        if isBusy {
                            statusIndicator
                        }

                        // Error
                        if case .error(let msg) = voiceQA.state {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                                Text(msg).font(.callout)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .onChange(of: voiceQA.conversationHistory.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: voiceQA.state) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
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

            // Recording indicator
            if isRecording {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    Text("Listening...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 1) {
                        ForEach(Array(voiceQA.bufferEnergy.suffix(20).enumerated()), id: \.offset) { _, energy in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(energy > 0.3 ? Color.red : Color.secondary.opacity(0.3))
                                .frame(width: 2, height: CGFloat(max(4, energy * 30)))
                        }
                    }
                    .frame(height: 24)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            // Attached files
            if !voiceQA.attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(voiceQA.attachedFiles, id: \.path) { url in
                            HStack(spacing: 4) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 9))
                                Text(url.lastPathComponent)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Button(action: {
                                    voiceQA.attachedFiles.removeAll { $0 == url }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }

            // Input bar — ALWAYS visible
            HStack(spacing: 8) {
                if !voiceQA.injectedContext.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text.fill").font(.system(size: 9))
                        Text("Context").font(.caption2)
                        Button(action: {
                            voiceQA.injectedContext = ""
                            showingContextPreview = false
                        }) {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
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

                // Mic button — click to toggle recording
                Button(action: toggleRecording) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .foregroundStyle(isRecording ? .red : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Click to record voice")

                TextField("Ask a question...", text: $followUpText)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .focused($textFieldFocused)
                    .onSubmit { submitText() }
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

                // Attach file button
                Button(action: attachFile) {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Attach a file")

                Button("Send") { submitText() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString) else { return }
                    DispatchQueue.main.async {
                        if !voiceQA.attachedFiles.contains(url) {
                            voiceQA.attachedFiles.append(url)
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Actions

    private func submitText() {
        let text = followUpText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        voiceQA.submitTextQuestion(text)
        followUpText = ""
    }

    private func attachFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK else { return }
            DispatchQueue.main.async {
                for url in panel.urls where !voiceQA.attachedFiles.contains(url) {
                    voiceQA.attachedFiles.append(url)
                }
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            voiceQA.stopRecording()
        } else {
            voiceQA.startRecording()
        }
    }

    // MARK: - Inline Status

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Group {
                switch voiceQA.state {
                case .loading: Text("Loading model...")
                case .transcribing: Text("Transcribing...")
                case .searching: Text("Searching documents...")
                case .answering: Text("Generating answer...")
                default: Text("")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Attachment Chips (shown in chat timeline)

    private func attachmentChips(_ urls: [URL]) -> some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                ForEach(urls, id: \.path) { url in
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 8))
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                    .onTapGesture {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Inline Doc Strip

    private func docStrip(_ sources: [SearchResult]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources, id: \.file) { doc in
                    DocumentTile(source: doc)
                }
            }
        }
    }

    // MARK: - Chat Bubbles

    private func questionBubble(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
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
        let cleaned = text
            .replacingOccurrences(of: #"(?m)^#{1,4}\s+(.+)$"#, with: "**$1**", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^[-*]\s+"#, with: "• ", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\d+\.\s+"#, with: "", options: .regularExpression)
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
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

// MARK: - Document Tile (compact card for inline doc strips)

struct DocumentTile: View {
    let source: SearchResult
    @State private var isHovering = false

    private var fileURL: URL { URL(fileURLWithPath: source.file) }
    private var fileName: String {
        let name = fileURL.deletingPathExtension().lastPathComponent
        return source.title.isEmpty ? name : source.title
    }
    private var fileExt: String { fileURL.pathExtension.lowercased() }

    private var typeLabel: String {
        switch fileExt {
        case "pdf": return "PDF"
        case "docx", "doc": return "Word"
        case "xlsx", "xls": return "Excel"
        case "csv": return "CSV"
        case "pptx", "ppt": return "PPT"
        case "md": return "Markdown"
        case "txt": return "Text"
        case "eml", "msg": return "Email"
        case "rtf": return "RTF"
        case "png", "jpg", "jpeg", "gif", "webp": return "Image"
        case "mp4", "mov": return "Video"
        case "mp3", "wav", "m4a": return "Audio"
        default: return fileExt.uppercased()
        }
    }

    private var typeColor: Color {
        switch fileExt {
        case "pdf": return .red
        case "docx", "doc": return .blue
        case "xlsx", "xls", "csv": return .green
        case "pptx", "ppt": return .orange
        case "eml", "msg": return .purple
        case "png", "jpg", "jpeg", "gif", "webp": return .teal
        default: return .secondary
        }
    }

    private var icon: String {
        switch fileExt {
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc": return "doc.text.fill"
        case "xlsx", "xls", "csv": return "tablecells.fill"
        case "pptx", "ppt": return "rectangle.fill.on.rectangle.fill"
        case "md", "txt": return "doc.plaintext.fill"
        case "eml", "msg": return "envelope.fill"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo.fill"
        case "mp4", "mov": return "film.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            // Icon + type tag
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(typeColor)
                    .frame(width: 32, height: 28)

                Text(typeLabel)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(typeColor.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: 4, y: 2)
            }

            // File name
            Text(fileName)
                .font(.system(size: 9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(width: 80)

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    Button(action: openFile) {
                        Image(systemName: "arrow.up.forward.square").font(.system(size: 9))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Open in app")

                    Button(action: revealInFinder) {
                        Image(systemName: "folder").font(.system(size: 9))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Show in Finder")
                }
                .transition(.opacity)
            }
        }
        .frame(width: 96)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.05))
        )
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering } }
        .onTapGesture { quickLook() }
        .onDrag { NSItemProvider(object: fileURL as NSURL) }
        .help(source.file.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }

    /// Click tile → Quick Look preview (selects in Finder, press Space)
    private func quickLook() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Arrow button → Open with default app
    private func openFile() {
        NSWorkspace.shared.open(fileURL)
    }

    /// Folder button → Reveal in Finder
    private func revealInFinder() {
        NSWorkspace.shared.selectFile(source.file, inFileViewerRootedAtPath: "")
    }
}
