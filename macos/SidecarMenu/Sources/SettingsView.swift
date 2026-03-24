import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = SettingsManager.shared
    @State private var newFolder = ""
    @State private var isRecordingHotkey = false
    @State private var cliVersion: String = "..."

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable hotkey injection", isOn: $settings.enabled)

                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Text("Start Sidecar Menu automatically when you log in")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-watch indexed folders", isOn: $settings.autoWatch)
                Text("Keep .sidecar.md files up to date as source files change")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("CLI Path", text: $settings.cliPath)
                    .textFieldStyle(.roundedBorder)

                Stepper("Max results: \(settings.maxResults)", value: $settings.maxResults, in: 1...20)
            }

            Section("Hotkey") {
                Picker("Trigger", selection: $settings.hotkeyType) {
                    ForEach(HotkeyType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }

                if settings.hotkeyType == .keyCombo {
                    HStack {
                        Text("Shortcut:")
                        Spacer()
                        HotkeyRecorderButton(
                            keyCode: $settings.hotkeyKeyCode,
                            modifiers: $settings.hotkeyModifiers,
                            isRecording: $isRecordingHotkey
                        )
                    }
                } else {
                    Text("Double-tap the Option key to trigger")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Current: \(settings.hotkeyDescription)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            }

            Section("Permissions") {
                PermissionRow(
                    label: "Accessibility",
                    granted: AXIsProcessTrusted(),
                    buttonLabel: "Open Accessibility",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )

                PermissionRow(
                    label: "Input Monitoring",
                    granted: Self.isInputMonitoringGranted(),
                    buttonLabel: "Open Input Monitoring",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                )

                Text("After granting Input Monitoring, restart the app for it to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Indexed Folders") {
                List {
                    ForEach(settings.indexedFolders, id: \.self) { folder in
                        Text(folder)
                            .font(.system(.body, design: .monospaced))
                    }
                    .onDelete { indexSet in
                        settings.indexedFolders.remove(atOffsets: indexSet)
                    }
                }
                .frame(minHeight: 100)

                HStack {
                    TextField("Add folder path…", text: $newFolder)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !settings.indexedFolders.contains(trimmed) {
                            settings.indexedFolders.append(trimmed)
                            newFolder = ""
                        }
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("CLI Version")
                    Spacer()
                    Text(cliVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Log File")
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(Logger.logFilePath, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
        }
        .task {
            let cli = settings.cliPath
            cliVersion = await Task.detached {
                SidecarCLI.version(cliPath: cli) ?? "Not found"
            }.value
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
    }
}

/// A button that records a key combo when clicked
struct HotkeyRecorderButton: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @Binding var isRecording: Bool

    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            if isRecording {
                Text("Press shortcut…")
                    .foregroundStyle(.red)
                    .frame(minWidth: 120)
            } else {
                Text(currentLabel)
                    .frame(minWidth: 120)
            }
        }
        .buttonStyle(.bordered)
        .background(
            isRecording ? HotkeyRecorderHelper(keyCode: $keyCode, modifiers: $modifiers, isRecording: $isRecording) : nil
        )
    }

    private var currentLabel: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
}

/// NSView-backed helper that captures key events while recording
struct HotkeyRecorderHelper: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onKeyRecorded = { code, mods in
            keyCode = code
            modifiers = mods.rawValue
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        // Become first responder to capture keys
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {}
}

final class RecorderView: NSView {
    var onKeyRecorded: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape cancels
        if event.keyCode == 0x35 {
            onCancel?()
            return
        }

        // Require at least one modifier
        guard !mods.isEmpty else { return }

        onKeyRecorded?(event.keyCode, mods)
    }
}

// MARK: - Permission helpers

extension SettingsView {
    /// Check Input Monitoring by probing whether a CGEvent tap can be created.
    static func isInputMonitoringGranted() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        ) else {
            return false
        }
        // Clean up the probe tap immediately
        CFMachPortInvalidate(tap)
        return true
    }
}

struct PermissionRow: View {
    let label: String
    let granted: Bool
    let buttonLabel: String
    let settingsURL: String

    var body: some View {
        HStack {
            Label(label, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(granted ? "Granted" : "Not Granted")
                .font(.caption)
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            Button(buttonLabel) {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
