import SwiftUI

struct StatusView: View {
    let folderPath: String
    private let settings = SettingsManager.shared

    @State private var status: StatusResult?
    @State private var error: String?
    @State private var isLoading = false
    @State private var showCleanConfirm = false
    @State private var cleanMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if folderPath.isEmpty {
                ContentUnavailableView("No Folder Selected", systemImage: "folder",
                    description: Text("Select a folder in the Scan tab first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView("Loading status...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                    description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Folder path header
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text(folderPath)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.bottom, 4)

                        statsGrid(status)
                        diskUsageSection(status)
                        extractorSection(status)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("No Data", systemImage: "chart.bar",
                    description: Text("Tap Refresh to load status."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                Button {
                    loadStatus()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(folderPath.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    showCleanConfirm = true
                } label: {
                    Label("Clean All", systemImage: "trash")
                }
                .disabled(folderPath.isEmpty)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clean All Sidecar Data?", isPresented: $showCleanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) { performClean() }
        } message: {
            Text("This will remove all .sidecar.md files, index data, and cache for this folder.")
        }
        .alert("Clean Complete", isPresented: .init(
            get: { cleanMessage != nil },
            set: { if !$0 { cleanMessage = nil } }
        )) {
            Button("OK") { cleanMessage = nil }
        } message: {
            Text(cleanMessage ?? "")
        }
        .task { loadStatus() }
    }

    private func statsGrid(_ s: StatusResult) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatCard(label: "Total Files", value: "\(s.totalFiles)", icon: "doc", color: .primary)
            StatCard(label: "Tracked", value: "\(s.trackedFiles)", icon: "checkmark.circle", color: .green)
            StatCard(label: "Missing", value: "\(s.missingFiles)", icon: "questionmark.circle", color: .orange)
            StatCard(label: "Stale", value: "\(s.staleFiles)", icon: "clock", color: .red)
        }
    }

    private func diskUsageSection(_ s: StatusResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Sidecar files", systemImage: "doc.text")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(s.sidecarDiskBytes), countStyle: .file))
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }
                Divider()
                HStack {
                    Label("Cache", systemImage: "internaldrive")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(s.cacheDiskBytes), countStyle: .file))
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Disk Usage", systemImage: "externaldrive")
                .font(.headline)
        }
    }

    private func extractorSection(_ s: StatusResult) -> some View {
        GroupBox {
            if s.byExtractor.isEmpty {
                Text("No extractors found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(s.byExtractor.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("By Extractor", systemImage: "list.bullet")
                .font(.headline)
        }
    }

    private func loadStatus() {
        guard !folderPath.isEmpty else { return }
        isLoading = true
        error = nil
        let cli = settings.cliPath
        let folder = folderPath
        Task.detached {
            do {
                let result = try SidecarCLI.status(path: folder, cliPath: cli)
                await MainActor.run {
                    status = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func performClean() {
        let cli = settings.cliPath
        let folder = folderPath
        Task.detached {
            do {
                let result = try SidecarCLI.clean(path: folder, cliPath: cli)
                let freed = ByteCountFormatter.string(fromByteCount: Int64(result.bytesFreed), countStyle: .file)
                await MainActor.run {
                    cleanMessage = "Removed \(result.sidecarFiles) sidecar files, \(result.indexFiles) index files. Freed \(freed)."
                    loadStatus()
                }
            } catch {
                await MainActor.run {
                    cleanMessage = "Clean failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
