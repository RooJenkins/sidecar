import SwiftUI

struct FilesView: View {
    let folderPath: String
    private let settings = SettingsManager.shared

    @State private var model = FileTreeModel()
    @State private var selectedPath: String?
    @State private var sidecarContent: String?
    @State private var searchText = ""
    @State private var statusFilter: SidecarStatus?
    @State private var showAISummaryOnly = false
    @State private var isRescanning = false
    @State private var lastLoadedPath = ""

    var body: some View {
        VStack(spacing: 0) {
            if folderPath.isEmpty {
                ContentUnavailableView("No Folder Selected", systemImage: "folder",
                    description: Text("Select a folder in the Scan tab first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isLoading {
                ProgressView("Scanning directory...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    leftPanel
                        .frame(minWidth: 280, idealWidth: 320)
                    rightPanel
                        .frame(minWidth: 350, idealWidth: 420)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: folderPath) {
            if folderPath != lastLoadedPath && !folderPath.isEmpty {
                lastLoadedPath = folderPath
                model.load(folderPath: folderPath)
            }
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(8)

            Divider()

            bulkActionsBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            List(selection: $selectedPath) {
                ForEach(filteredNodes) { node in
                    fileTreeRow(node)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedPath) { _, newPath in
                loadSidecarContent(for: newPath)
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter files...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))

            HStack(spacing: 4) {
                filterChip("All", count: totalFileCount, active: statusFilter == nil && !showAISummaryOnly) {
                    statusFilter = nil; showAISummaryOnly = false
                }
                filterChip("Up to Date", count: model.counts.upToDate, color: .green, active: statusFilter == .upToDate) {
                    statusFilter = .upToDate; showAISummaryOnly = false
                }
                filterChip("Stale", count: model.counts.stale, color: .yellow, active: statusFilter == .stale) {
                    statusFilter = .stale; showAISummaryOnly = false
                }
                filterChip("Missing", count: model.counts.missing, color: .red, active: statusFilter == .missing) {
                    statusFilter = .missing; showAISummaryOnly = false
                }
                filterChip("AI", count: model.counts.aiSummary, color: .blue, active: showAISummaryOnly) {
                    showAISummaryOnly.toggle(); statusFilter = nil
                }
            }
        }
    }

    private func filterChip(_ label: String, count: Int, color: Color = .primary, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(active ? .white : color)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(active ? AnyShapeStyle(color.opacity(0.8)) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var totalFileCount: Int {
        model.counts.upToDate + model.counts.stale + model.counts.missing
    }

    private var bulkActionsBar: some View {
        HStack(spacing: 6) {
            Button {
                rescanStale()
            } label: {
                Label("Rescan Stale", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .disabled(model.counts.stale == 0 || isRescanning)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                addAISummaries()
            } label: {
                Label("Add AI", systemImage: "brain")
                    .font(.caption)
            }
            .disabled(isRescanning)
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                model.load(folderPath: folderPath)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh file tree")
        }
    }

    // MARK: - File Tree

    @ViewBuilder
    private func fileTreeRow(_ node: FileNode) -> some View {
        if node.isDirectory {
            DisclosureGroup {
                if let children = node.children {
                    ForEach(filterChildren(children)) { child in
                        AnyView(fileTreeRow(child))
                    }
                }
            } label: {
                folderLabel(node)
            }
        } else {
            HStack(spacing: 6) {
                statusDot(node)
                fileIcon(node.name)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if node.hasAISummary {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                if let ext = node.sidecarMeta?.extractor, !ext.isEmpty {
                    Text(ext)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            .tag(node.path)
            .contentShape(Rectangle())
        }
    }

    private func folderLabel(_ node: FileNode) -> some View {
        HStack(spacing: 6) {
            if let agg = node.aggregateStatus {
                statusDotColor(agg)
                    .frame(width: 8, height: 8)
                    .clipShape(Circle())
            }
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            Text(node.name)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func statusDot(_ node: FileNode) -> some View {
        if let status = node.sidecarStatus {
            statusDotColor(status)
                .frame(width: 8, height: 8)
                .clipShape(Circle())
        }
    }

    private func statusDotColor(_ status: SidecarStatus) -> Color {
        switch status {
        case .upToDate: return .green
        case .stale: return .yellow
        case .missing: return .red
        }
    }

    private func fileIcon(_ name: String) -> some View {
        let ext = (name as NSString).pathExtension.lowercased()
        let symbol: String
        switch ext {
        case "pdf": symbol = "doc.richtext"
        case "docx", "doc": symbol = "doc.text"
        case "xlsx", "xls", "csv": symbol = "tablecells"
        case "md", "txt": symbol = "doc.plaintext"
        case "html", "htm": symbol = "globe"
        case "png", "jpg", "jpeg", "gif", "avif": symbol = "photo"
        default: symbol = "doc"
        }
        return Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(width: 16)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            if let path = selectedPath, let node = findNode(path: path, in: model.root) {
                fileDetailHeader(node)
                Divider()
                sidecarContentView
                Divider()
                fileActions(node)
            } else {
                ContentUnavailableView("Select a File", systemImage: "doc.text",
                    description: Text("Click a file in the tree to view its sidecar content."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fileDetailHeader(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.name)
                    .font(.headline)
                Spacer()
                if let status = node.sidecarStatus {
                    HStack(spacing: 4) {
                        statusDotColor(status)
                            .frame(width: 8, height: 8)
                            .clipShape(Circle())
                        Text(status.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }
                if node.hasAISummary {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                        Text("AI Summary")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.1), in: Capsule())
                }
            }

            Text(node.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 16) {
                if let meta = node.sidecarMeta {
                    if !meta.extractor.isEmpty {
                        Label(meta.extractor, systemImage: "gearshape")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if meta.wordCount > 0 {
                        Label("\(meta.wordCount) words", systemImage: "textformat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let mod = node.sourceModified {
                    Label(mod.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var sidecarContentView: some View {
        Group {
            if let content = sidecarContent {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else if selectedPath != nil {
                ContentUnavailableView("No Sidecar File", systemImage: "doc.text",
                    description: Text("This file has no .sidecar.md companion yet. Click Rescan to generate one."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fileActions(_ node: FileNode) -> some View {
        HStack(spacing: 8) {
            Button {
                rescanFile(node, summarize: false)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(isRescanning)
            .buttonStyle(.bordered)

            Button {
                rescanFile(node, summarize: true)
            } label: {
                Label("Rescan with AI", systemImage: "brain")
            }
            .disabled(isRescanning)
            .buttonStyle(.bordered)

            if node.sidecarStatus != .missing {
                Button(role: .destructive) {
                    deleteSidecar(node)
                } label: {
                    Label("Delete Sidecar", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(12)
    }

    // MARK: - Filtering

    private var filteredNodes: [FileNode] {
        filterChildren(model.root)
    }

    private func filterChildren(_ nodes: [FileNode]) -> [FileNode] {
        nodes.compactMap { filterNode($0) }
    }

    private func filterNode(_ node: FileNode) -> FileNode? {
        if node.isDirectory {
            let filtered = node.children?.compactMap { filterNode($0) } ?? []
            if filtered.isEmpty { return nil }
            var copy = node
            copy.children = filtered
            return copy
        }

        // Name filter
        if !searchText.isEmpty && !node.name.localizedCaseInsensitiveContains(searchText) {
            return nil
        }
        // Status filter
        if let filter = statusFilter, node.sidecarStatus != filter {
            return nil
        }
        // AI summary filter
        if showAISummaryOnly && !node.hasAISummary {
            return nil
        }
        return node
    }

    // MARK: - Helpers

    private func findNode(path: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.path == path { return node }
            if let children = node.children, let found = findNode(path: path, in: children) {
                return found
            }
        }
        return nil
    }

    private func loadSidecarContent(for path: String?) {
        guard let path else {
            sidecarContent = nil
            return
        }
        sidecarContent = SidecarCLI.readSidecarFile(sourcePath: path)
    }

    // MARK: - Actions

    private func rescanFile(_ node: FileNode, summarize: Bool) {
        isRescanning = true
        let sidecarPath = node.path + ".sidecar.md"
        try? FileManager.default.removeItem(atPath: sidecarPath)

        let parentDir = (node.path as NSString).deletingLastPathComponent
        let cli = settings.cliPath
        let config = SidecarCLI.loadConfig(dir: parentDir)
        let provider = config?.provider ?? "claude"
        let apiKey = KeychainHelper.load(key: "apiKey-\(provider)")

        var opts = config ?? SidecarConfig()
        if summarize { opts.summarize = true }

        Task {
            // Clean cache for this folder so the file gets re-processed
            _ = try? SidecarCLI.clean(path: parentDir, cliPath: cli)

            for await _ in SidecarCLI.scan(path: parentDir, options: opts, apiKey: apiKey, cliPath: cli) {
                // consume events
            }
            await MainActor.run {
                isRescanning = false
                model.load(folderPath: folderPath)
                loadSidecarContent(for: node.path)
            }
        }
    }

    private func deleteSidecar(_ node: FileNode) {
        let sidecarPath = node.path + ".sidecar.md"
        try? FileManager.default.removeItem(atPath: sidecarPath)
        model.load(folderPath: folderPath)
        sidecarContent = nil
    }

    private func rescanStale() {
        isRescanning = true
        let cli = settings.cliPath
        let config = SidecarCLI.loadConfig(dir: folderPath)
        let provider = config?.provider ?? "claude"
        let apiKey = KeychainHelper.load(key: "apiKey-\(provider)")

        // Delete stale sidecar files so they get regenerated
        func deleteStale(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isDirectory {
                    deleteStale(node.children ?? [])
                } else if node.sidecarStatus == .stale {
                    try? FileManager.default.removeItem(atPath: node.path + ".sidecar.md")
                }
            }
        }
        deleteStale(model.root)

        Task {
            _ = try? SidecarCLI.clean(path: folderPath, cliPath: cli)
            for await _ in SidecarCLI.scan(path: folderPath, options: config, apiKey: apiKey, cliPath: cli) {}
            _ = try? SidecarCLI.index(paths: [folderPath], cliPath: cli)
            await MainActor.run {
                isRescanning = false
                model.load(folderPath: folderPath)
            }
        }
    }

    private func addAISummaries() {
        isRescanning = true
        let cli = settings.cliPath
        var config = SidecarCLI.loadConfig(dir: folderPath) ?? SidecarConfig()
        config.summarize = true
        let provider = config.provider ?? "claude"
        let apiKey = KeychainHelper.load(key: "apiKey-\(provider)")

        // Delete sidecar files that lack AI summaries
        func deleteMissingSummary(_ nodes: [FileNode]) {
            for node in nodes {
                if node.isDirectory {
                    deleteMissingSummary(node.children ?? [])
                } else if !node.hasAISummary && node.sidecarStatus != .missing {
                    try? FileManager.default.removeItem(atPath: node.path + ".sidecar.md")
                }
            }
        }
        deleteMissingSummary(model.root)

        Task {
            _ = try? SidecarCLI.clean(path: folderPath, cliPath: cli)
            for await _ in SidecarCLI.scan(path: folderPath, options: config, apiKey: apiKey, cliPath: cli) {}
            _ = try? SidecarCLI.index(paths: [folderPath], cliPath: cli)
            await MainActor.run {
                isRescanning = false
                model.load(folderPath: folderPath)
            }
        }
    }
}
