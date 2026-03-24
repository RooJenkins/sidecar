import SwiftUI

struct SearchView: View {
    private let settings = SettingsManager.shared

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedFile: String?
    @State private var sidecarContent: String?
    @State private var isSearching = false
    @State private var isIndexing = false
    @State private var error: String?
    @State private var indexMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(12)

            if let error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { self.error = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            if let indexMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(indexMessage)
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            Divider()

            if results.isEmpty && !isSearching {
                ContentUnavailableView("Search Sidecar Docs", systemImage: "magnifyingglass",
                    description: Text("Enter a query above to search your indexed sidecar documents."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    resultsList
                        .frame(minWidth: 260, idealWidth: 320)
                    detailPanel
                        .frame(minWidth: 280, idealWidth: 380)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search query...", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(6)
            .background(.background)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: 1)
            )

            Button("Search") { performSearch() }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                .buttonStyle(.borderedProminent)

            Button {
                rebuildIndex()
            } label: {
                Label("Rebuild Index", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isIndexing)
            .buttonStyle(.bordered)
        }
    }

    private var resultsList: some View {
        List(results, id: \.file, selection: $selectedFile) { result in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    scoreIndicator(result.score)
                    Text(result.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                Text(result.file)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !result.topics.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(result.topics.prefix(3), id: \.self) { topic in
                            Text(topic)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                        }
                    }
                }
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
        .onChange(of: selectedFile) { _, newFile in
            if let file = newFile {
                loadSidecarContent(for: file)
            } else {
                sidecarContent = nil
            }
        }
    }

    private var detailPanel: some View {
        Group {
            if let content = sidecarContent {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else if selectedFile != nil {
                ProgressView("Loading sidecar file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a Result", systemImage: "doc.text",
                    description: Text("Click a search result to view its sidecar content."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func scoreIndicator(_ score: Double) -> some View {
        let color: Color = score >= 0.7 ? .green : score >= 0.4 ? .yellow : .gray
        let pct = Int(score * 100)
        return Text("\(pct)%")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    private func loadSidecarContent(for file: String) {
        sidecarContent = nil
        Task.detached {
            let content = SidecarCLI.readSidecarFile(sourcePath: file)
            await MainActor.run {
                sidecarContent = content ?? "No sidecar file found."
            }
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        error = nil
        let cli = settings.cliPath
        let maxResults = settings.maxResults
        Task.detached {
            do {
                let found = try SidecarCLI.search(query: q, maxResults: maxResults, cliPath: cli)
                await MainActor.run {
                    results = found
                    selectedFile = nil
                    sidecarContent = nil
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func rebuildIndex() {
        let folders = settings.indexedFolders
        guard !folders.isEmpty else {
            indexMessage = "No indexed folders configured in Hotkey Settings."
            return
        }
        isIndexing = true
        indexMessage = nil
        let cli = settings.cliPath
        Task.detached {
            do {
                let result = try SidecarCLI.index(paths: folders, cliPath: cli)
                await MainActor.run {
                    indexMessage = "Index rebuilt: \(result.documentCount) documents at \(result.indexPath)"
                    isIndexing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isIndexing = false
                }
            }
        }
    }
}
