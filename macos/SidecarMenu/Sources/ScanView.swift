import SwiftUI
import UniformTypeIdentifiers

struct FileEntry: Identifiable {
    let id = UUID()
    let fileName: String
    let sourcePath: String
    let extractor: String
    let mimeType: String
    let status: String  // "processed", "skipped", "error"
    let reason: String?
    let message: String?
}

struct ScanView: View {
    @Binding var folderPath: String
    private let settings = SettingsManager.shared
    @State private var watchManager = WatchManager.shared

    @State private var phase: String = "idle"  // "idle", "scanning", "complete"
    @State private var processedCount = 0
    @State private var skippedCount = 0
    @State private var errorCount = 0
    @State private var elapsedSeconds: Double?
    @State private var files: [FileEntry] = []
    @State private var scanTask: Task<Void, Never>?
    @State private var selectedFile: FileEntry?
    @State private var sidecarContent: String?
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            folderPicker
                .padding(12)

            if phase == "scanning" || phase == "complete" {
                progressBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            if phase == "idle" && files.isEmpty {
                idlePlaceholder
            } else {
                fileList
            }

            if phase == "complete", let elapsed = elapsedSeconds {
                Divider()
                Text(String(format: "Completed in %.1fs", elapsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(dragOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
        .sheet(item: $selectedFile) { file in
            sidecarSheet(file)
        }
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Choose a folder or drag one here to scan")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var dragOverlay: some View {
        if isDragOver {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.blue, lineWidth: 3)
                .background(.blue.opacity(0.1))
                .padding(4)
        }
    }

    private var folderPicker: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                TextField("Folder path or drag here...", text: $folderPath)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(.background)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: 1)
            )

            Button("Browse") { pickFolder() }
                .buttonStyle(.bordered)

            if phase == "idle" || phase == "complete" {
                Button("Scan") { startScan() }
                    .disabled(folderPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Stop") {
                    scanTask?.cancel()
                    phase = "complete"
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Divider()
                .frame(height: 20)

            watchToggle
        }
    }

    private var watchToggle: some View {
        let path = folderPath.trimmingCharacters(in: .whitespaces)
        let isWatching = watchManager.isWatching(path)

        return Button {
            if isWatching {
                watchManager.stopWatching(path: path)
            } else {
                watchManager.startWatching(path: path, cliPath: settings.cliPath)
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isWatching ? .green : .gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(isWatching ? "Watching" : "Watch")
            }
        }
        .buttonStyle(.bordered)
        .disabled(path.isEmpty)
    }

    private var progressBar: some View {
        HStack(spacing: 16) {
            Label("\(processedCount)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Label("\(skippedCount)", systemImage: "minus.circle.fill")
                .foregroundStyle(.yellow)
            Label("\(errorCount)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
            Spacer()
            if phase == "scanning" {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.callout)
    }

    private var fileList: some View {
        List(files) { file in
            HStack(spacing: 8) {
                statusIcon(file.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .fontWeight(.medium)
                    Text(file.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !file.extractor.isEmpty {
                    Text(file.extractor)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showSidecar(file) }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func statusIcon(_ status: String) -> some View {
        switch status {
        case "processed":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "skipped":
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.yellow)
        default:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func sidecarSheet(_ file: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.headline)
                    Text(file.sourcePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { selectedFile = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            if let content = sidecarContent {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                ContentUnavailableView("No Sidecar File", systemImage: "doc.text",
                    description: Text("No .sidecar.md file found for this source."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 550, minHeight: 400)
    }

    private func pickFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to scan"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            if let data = data as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                DispatchQueue.main.async {
                    folderPath = url.path
                }
            }
        }
        return true
    }

    private func showSidecar(_ file: FileEntry) {
        sidecarContent = SidecarCLI.readSidecarFile(sourcePath: file.sourcePath)
        selectedFile = file
    }

    private func startScan() {
        let path = folderPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        phase = "scanning"
        processedCount = 0
        skippedCount = 0
        errorCount = 0
        elapsedSeconds = nil
        files = []

        let cli = settings.cliPath
        let config = SidecarCLI.loadConfig(dir: path)
        let provider = config?.provider ?? "claude"
        let apiKey = KeychainHelper.load(key: "apiKey-\(provider)")

        scanTask = Task {
            for await event in SidecarCLI.scan(path: path, options: config, apiKey: apiKey, cliPath: cli) {
                await MainActor.run {
                    handleEvent(event)
                }
            }
            // Auto-rebuild search index after scan completes
            let indexPath = path
            let indexCli = cli
            do {
                _ = try SidecarCLI.index(paths: [indexPath], cliPath: indexCli)
                await MainActor.run {
                    Logger.log("Index rebuilt after scan of \(indexPath)", source: "Scan")
                }
            } catch {
                await MainActor.run {
                    Logger.log("Index rebuild failed: \(error)", source: "Scan")
                }
            }
            await MainActor.run {
                phase = "complete"
            }
        }
    }

    private func handleEvent(_ event: ScanEvent) {
        switch event.event {
        case "file":
            processedCount += 1
            if let name = event.fileName, let path = event.sourcePath {
                files.append(FileEntry(
                    fileName: name,
                    sourcePath: path,
                    extractor: event.extractor ?? "unknown",
                    mimeType: event.mimeType ?? "",
                    status: "processed",
                    reason: nil,
                    message: nil
                ))
            }
        case "skip":
            skippedCount += 1
            if let name = event.fileName, let path = event.sourcePath {
                files.append(FileEntry(
                    fileName: name,
                    sourcePath: path,
                    extractor: event.extractor ?? "",
                    mimeType: event.mimeType ?? "",
                    status: "skipped",
                    reason: event.reason,
                    message: nil
                ))
            }
        case "error":
            errorCount += 1
            if let name = event.fileName, let path = event.sourcePath {
                files.append(FileEntry(
                    fileName: name,
                    sourcePath: path,
                    extractor: event.extractor ?? "",
                    mimeType: "",
                    status: "error",
                    reason: nil,
                    message: event.message
                ))
            }
        case "summary", "done":
            if let p = event.processed { processedCount = p }
            if let s = event.skipped { skippedCount = s }
            if let e = event.errors { errorCount = e }
            if let elapsed = event.elapsed_seconds { elapsedSeconds = elapsed }
        default:
            break
        }
    }
}
