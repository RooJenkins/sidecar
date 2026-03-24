import SwiftUI

struct AIProvider: Identifiable {
    let id: String          // CLI name
    let displayName: String
    let icon: String
    let needsApiKey: Bool
    let needsApiUrl: Bool
    let defaultUrl: String
    let models: [String]
    let defaultModel: String
    let description: String
}

private let providers: [AIProvider] = [
    AIProvider(
        id: "claude", displayName: "Claude", icon: "brain.head.profile",
        needsApiKey: false, needsApiUrl: false, defaultUrl: "",
        models: ["claude-sonnet-4-5-20250929", "claude-3-opus-20250219", "claude-3-haiku-20240307"],
        defaultModel: "claude-sonnet-4-5-20250929",
        description: "Uses your Claude Code CLI (Max subscription). No API key needed."
    ),
    AIProvider(
        id: "ollama", displayName: "Ollama", icon: "desktopcomputer",
        needsApiKey: false, needsApiUrl: true, defaultUrl: "http://localhost:11434",
        models: ["llama3.2", "llama3.1", "mistral", "neural-chat", "codellama", "phi3"],
        defaultModel: "llama3.2",
        description: "Local models via Ollama. No API key needed."
    ),
    AIProvider(
        id: "openai-compatible", displayName: "OpenAI", icon: "globe",
        needsApiKey: true, needsApiUrl: true, defaultUrl: "https://api.openai.com/v1",
        models: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"],
        defaultModel: "gpt-4o-mini",
        description: "OpenAI or any compatible API. Requires API key."
    ),
]

struct ConfigView: View {
    let folderPath: String

    @State private var config = SidecarConfig()
    @State private var newInclude = ""
    @State private var newExclude = ""
    @State private var saveMessage: String?
    @State private var isLoaded = false
    @State private var apiKey = ""
    @State private var showApiKey = false
    @State private var customModel = ""

    private var selectedProvider: AIProvider {
        providers.first { $0.id == (config.provider ?? "claude") } ?? providers[0]
    }

    var body: some View {
        if folderPath.isEmpty {
            ContentUnavailableView("No Folder Selected", systemImage: "folder",
                description: Text("Select a folder in the Scan tab first."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(folderPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(12)

                Divider()

                Form {
                    Section("Include Patterns") {
                        patternList(patterns: Binding(
                            get: { config.include ?? [] },
                            set: { config.include = $0.isEmpty ? nil : $0 }
                        ))
                        HStack {
                            TextField("e.g. **/*.ts", text: $newInclude)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addInclude() }
                            Button("Add") { addInclude() }
                                .disabled(newInclude.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    Section("Exclude Patterns") {
                        patternList(patterns: Binding(
                            get: { config.exclude ?? [] },
                            set: { config.exclude = $0.isEmpty ? nil : $0 }
                        ))
                        HStack {
                            TextField("e.g. node_modules/**", text: $newExclude)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addExclude() }
                            Button("Add") { addExclude() }
                                .disabled(newExclude.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    Section("File Processing") {
                        HStack {
                            Text("Max file size")
                            Spacer()
                            TextField("e.g. 10mb", text: Binding(
                                get: { config.maxFileSize ?? "" },
                                set: { config.maxFileSize = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        }

                        Stepper("Concurrency: \(config.concurrency ?? 4)",
                                value: Binding(
                                    get: { config.concurrency ?? 4 },
                                    set: { config.concurrency = $0 }
                                ), in: 1...32)
                    }

                    Section("Output Location") {
                        Picker("Sidecar files", selection: Binding(
                            get: { config.outputDir != nil ? "separate" : "alongside" },
                            set: { val in
                                if val == "alongside" {
                                    config.outputDir = nil
                                } else if config.outputDir == nil {
                                    config.outputDir = ""
                                }
                            }
                        )) {
                            Text("Next to source files").tag("alongside")
                            Text("Separate folder").tag("separate")
                        }
                        .pickerStyle(.radioGroup)

                        if config.outputDir != nil {
                            HStack {
                                TextField("Output directory path", text: Binding(
                                    get: { config.outputDir ?? "" },
                                    set: { config.outputDir = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                                Button("Browse") { pickOutputDir() }
                                    .buttonStyle(.bordered)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                                Text("Sidecar files will be written to a mirrored folder structure inside this directory, keeping your source folders clean.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    aiSection
                }
                .formStyle(.grouped)

                Divider()

                HStack {
                    if let saveMessage {
                        Label(
                            saveMessage,
                            systemImage: saveMessage.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(saveMessage.contains("Error") ? .red : .green)
                    }
                    Spacer()
                    Button("Save Configuration") { saveConfig() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { loadConfig() }
        }
    }

    // MARK: - AI Summarization Section

    @ViewBuilder
    private var aiSection: some View {
        Section("AI Summarization") {
            Toggle("Enable summarization", isOn: Binding(
                get: { config.summarize ?? false },
                set: { config.summarize = $0 }
            ))

            // Provider picker with icons
            Picker("Provider", selection: Binding(
                get: { config.provider ?? "claude" },
                set: { newProvider in
                    config.provider = newProvider
                    let p = providers.first { $0.id == newProvider } ?? providers[0]
                    config.model = p.defaultModel
                    config.apiUrl = p.needsApiUrl ? p.defaultUrl : nil
                    customModel = ""
                    // Load API key for this provider
                    apiKey = KeychainHelper.load(key: "apiKey-\(newProvider)") ?? ""
                    showApiKey = false
                }
            )) {
                ForEach(providers) { p in
                    Label(p.displayName, systemImage: p.icon).tag(p.id)
                }
            }

            // Provider description
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text(selectedProvider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // API Key (only for providers that need it)
            if selectedProvider.needsApiKey {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API Key")
                        Spacer()
                        if !apiKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    HStack {
                        if showApiKey {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showApiKey.toggle()
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        Button("Save Key") {
                            let provider = config.provider ?? "claude"
                            if apiKey.isEmpty {
                                KeychainHelper.delete(key: "apiKey-\(provider)")
                            } else {
                                KeychainHelper.save(key: "apiKey-\(provider)", value: apiKey)
                            }
                            saveMessage = "API key saved to Keychain"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text("Stored securely in your macOS Keychain, not in .sidecarrc")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // API URL (for Ollama and OpenAI)
            if selectedProvider.needsApiUrl {
                HStack {
                    Text("API URL")
                    Spacer()
                    TextField(selectedProvider.defaultUrl, text: Binding(
                        get: { config.apiUrl ?? selectedProvider.defaultUrl },
                        set: { config.apiUrl = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                }
            }

            // Model picker + custom option
            modelPicker
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        let currentModel = config.model ?? selectedProvider.defaultModel
        let isCustom = !selectedProvider.models.contains(currentModel) && !currentModel.isEmpty

        VStack(alignment: .leading, spacing: 6) {
            Picker("Model", selection: Binding(
                get: {
                    if isCustom { return "__custom__" }
                    return currentModel
                },
                set: { newValue in
                    if newValue == "__custom__" {
                        customModel = config.model ?? ""
                    } else {
                        config.model = newValue
                        customModel = ""
                    }
                }
            )) {
                ForEach(selectedProvider.models, id: \.self) { model in
                    Text(model).tag(model)
                }
                Divider()
                Text("Custom...").tag("__custom__")
            }

            if isCustom || customModel == "__editing__" || (!customModel.isEmpty) {
                HStack {
                    TextField("Custom model name", text: Binding(
                        get: { isCustom ? currentModel : customModel },
                        set: { val in
                            config.model = val
                            customModel = val
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Pattern List

    @ViewBuilder
    private func patternList(patterns: Binding<[String]>) -> some View {
        if patterns.wrappedValue.isEmpty {
            Text("No patterns configured")
                .foregroundStyle(.tertiary)
                .font(.caption)
        } else {
            ForEach(patterns.wrappedValue, id: \.self) { pattern in
                HStack {
                    Text(pattern)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button(role: .destructive) {
                        patterns.wrappedValue.removeAll { $0 == pattern }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Actions

    private func addInclude() {
        let p = newInclude.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        var list = config.include ?? []
        list.append(p)
        config.include = list
        newInclude = ""
    }

    private func addExclude() {
        let p = newExclude.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        var list = config.exclude ?? []
        list.append(p)
        config.exclude = list
        newExclude = ""
    }

    private func pickOutputDir() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for sidecar output files"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            config.outputDir = url.path
        }
    }

    private func loadConfig() {
        guard !isLoaded else { return }
        if let loaded = SidecarCLI.loadConfig(dir: folderPath) {
            config = loaded
        }
        // Load API key for current provider
        let provider = config.provider ?? "claude"
        apiKey = KeychainHelper.load(key: "apiKey-\(provider)") ?? ""
        isLoaded = true
    }

    private func saveConfig() {
        do {
            try SidecarCLI.saveConfig(dir: folderPath, config: config)
            saveMessage = "Saved successfully"
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }
}
