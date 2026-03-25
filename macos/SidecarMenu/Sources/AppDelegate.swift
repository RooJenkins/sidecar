import AppKit
import SwiftUI
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyMonitor: HotkeyMonitor?
    private var cmdJMonitor: HotkeyMonitor?
    private var cmdUMonitor: HotkeyMonitor?
    private let settings = SettingsManager.shared
    private let clipboardManager = ClipboardManager()
    private var settingsWindow: NSWindow?
    private var managementWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var voicePanel: VoiceAnswerPanel?
    private var activeToast: ToastWindow?
    private var tikaStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("App launching (v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))")

        // Show onboarding if any permission is missing
        let trusted = AXIsProcessTrusted()
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        Logger.log("Permissions: accessibility=\(trusted) mic=\(micGranted)")

        if !trusted || !micGranted {
            showOnboarding()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Sidecar")
        }

        buildMenu()

        // Cmd+J: tap=open chat, hold=voice
        let cmdJ = HotkeyMonitor(
            settings: settings,
            keyCode: 0x26, // J key
            modifiers: .command,
            mode: .tapOrHold,
            action: { [weak self] in self?.handleVoiceKeyDown() },
            onRelease: { [weak self] in self?.handleVoiceKeyUp() },
            onTap: { [weak self] in self?.handleVoiceOpenChat() },
            holdThreshold: 0.3
        )
        cmdJ.start()
        cmdJMonitor = cmdJ

        // Cmd+U: inject window context into chat
        let cmdU = HotkeyMonitor(
            settings: settings,
            keyCode: 0x20, // U key
            modifiers: .command,
            mode: .tap,
            action: { [weak self] in self?.performContextInjection() }
        )
        cmdU.start()
        cmdUMonitor = cmdU
        Logger.log("Hotkeys started (⌘J=chat/voice, ⌘U=inject context)")

        // Request microphone permission early so it's ready for voice Q&A
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Logger.log("Microphone permission: \(granted ? "granted" : "denied")")
        }

        // Pre-load WhisperKit model in background so voice Q&A is instant
        VoiceQA.shared.preloadModel()

        // Auto-watch indexed folders
        if settings.autoWatch && !settings.indexedFolders.isEmpty {
            for folder in settings.indexedFolders {
                WatchManager.shared.startWatching(path: folder, cliPath: settings.cliPath)
            }
            Logger.log("Auto-watching \(settings.indexedFolders.count) folder(s)")
        }

        // Auto-start Tika if any indexed folder has it enabled
        autoStartTikaIfNeeded()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = settings.enabled ? .on : .off
        menu.addItem(enabledItem)

        let watchCount = WatchManager.shared.activeCount
        if watchCount > 0 {
            let watchItem = NSMenuItem(title: "Watching \(watchCount) folder\(watchCount == 1 ? "" : "s")", action: nil, keyEquivalent: "")
            watchItem.isEnabled = false
            watchItem.image = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "Watching")
            menu.addItem(watchItem)
        }

        menu.addItem(NSMenuItem.separator())

        let managementItem = NSMenuItem(title: "Open Sidecar…", action: #selector(openManagement), keyEquivalent: "o")
        managementItem.target = self
        menu.addItem(managementItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Sidecar Menu", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        buildMenu()
    }

    private func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView {
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        }
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sidecar Setup"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sidecar Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    @objc private func openManagement() {
        if let window = managementWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let managementView = ManagementView()
        let hostingView = NSHostingView(rootView: managementView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sidecar"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.managementWindow = window
    }

    @objc private func quitApp() {
        WatchManager.shared.stopAll()
        // Stop Tika if we started it
        if tikaStarted {
            do {
                try SidecarCLI.tikaStop(cliPath: settings.cliPath)
                Logger.log("Tika stopped on quit")
            } catch {
                Logger.log("Failed to stop Tika: \(error)", source: "Tika")
            }
        }
        NSApp.terminate(nil)
    }

    private func autoStartTikaIfNeeded() {
        let folders = settings.indexedFolders
        let needsTika = folders.contains { folder in
            SidecarCLI.loadConfig(dir: folder)?.tikaUrl != nil
        }
        guard needsTika else { return }

        DispatchQueue.global(qos: .utility).async { [self] in
            do {
                try SidecarCLI.tikaStart(cliPath: settings.cliPath)
                tikaStarted = true
                Logger.log("Tika auto-started on launch")
            } catch {
                Logger.log("Failed to auto-start Tika: \(error)", source: "Tika")
            }
        }
    }

    @MainActor
    private func ensurePanel() {
        if voicePanel == nil {
            voicePanel = VoiceAnswerPanel()
        }
        voicePanel?.show()
    }

    @MainActor
    private func handleVoiceOpenChat() {
        guard settings.enabled else { return }
        ensurePanel()
        let voiceQA = VoiceQA.shared
        if case .idle = voiceQA.state {
            voiceQA.state = .done(answer: "", sources: [], knowledgeBlocks: [])
        }
        voiceQA.focusTrigger += 1
    }

    @MainActor
    private func handleVoiceKeyDown() {
        guard settings.enabled else { return }
        ensurePanel()
        VoiceQA.shared.startRecording()
    }

    @MainActor
    private func handleVoiceKeyUp() {
        VoiceQA.shared.stopRecording()
    }

    @MainActor
    private func performContextInjection() {
        guard settings.enabled else {
            Logger.log("Context injection skipped: disabled", source: "Inject")
            return
        }

        guard AXIsProcessTrusted() else {
            Logger.log("Context injection skipped: no accessibility permission", source: "Inject")
            activeToast?.dismiss()
            activeToast = ToastWindow(message: "⚠ Accessibility permission required.\nGrant in System Settings → Privacy → Accessibility.")
            activeToast?.show()
            return
        }

        Logger.log("Starting context injection...", source: "Inject")

        // Find the target app (skip ourselves)
        let myPID = ProcessInfo.processInfo.processIdentifier
        let frontApp = NSWorkspace.shared.frontmostApplication
        let targetPID: pid_t
        if let frontApp = frontApp, frontApp.processIdentifier != myPID {
            targetPID = frontApp.processIdentifier
            Logger.log("Reading from: \(frontApp.localizedName ?? "unknown") (pid \(targetPID))", source: "Inject")
        } else {
            // Frontmost is us — find the most recent regular app that isn't us
            let candidates = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != myPID && !$0.isTerminated }
            // macOS orders these by launch time, not recency, so try to use the menu bar order
            // Fall back to the first visible app
            guard let target = candidates.first(where: { $0.isActive }) ?? candidates.first else {
                activeToast?.dismiss()
                activeToast = ToastWindow(message: "No app window to read from.")
                activeToast?.show()
                return
            }
            targetPID = target.processIdentifier
            Logger.log("Frontmost is us, reading from: \(target.localizedName ?? "unknown") (pid \(targetPID))", source: "Inject")
        }

        // Grab the text in the focused input field (what the user was typing)
        let inputText = AccessibilityReader.readFocusedElementText(fromPID: targetPID)
        if let inputText = inputText {
            Logger.log("Focused input text: \(inputText.count) chars", source: "Inject")
        }

        // Read full window text via Accessibility API from the target app
        var axText = AccessibilityReader.readWindowText(fromPID: targetPID) ?? ""
        Logger.log("AX returned \(axText.count) chars", source: "Inject")

        // Strip the input box text from window text so it doesn't appear in context
        if let inputText = inputText, !inputText.isEmpty, axText.contains(inputText) {
            axText = axText.replacingOccurrences(of: inputText, with: "")
        }

        // If AX returned very little (just titles), fall back to clipboard method
        if axText.count < 50 {
            Logger.log("AX text too short, using clipboard fallback", source: "Inject")
            clipboardInject(targetPID: targetPID)
            return
        }

        // Inject context first (opens panel), then set pendingInput so onChange fires
        injectText(axText)
        if let inputText = inputText, !inputText.isEmpty {
            // Small delay so the panel/view is rendered before setting pendingInput
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                VoiceQA.shared.pendingInput = inputText
            }
        }
    }

    /// Clean raw text, inject into VoiceQA, open panel, show toast.
    @MainActor
    private func injectText(_ rawText: String) {
        // Strip previously injected sidecar context blocks
        var clean = rawText
        while let s = clean.range(of: "<company_context>"),
              let e = clean.range(of: "</company_context>") {
            clean.removeSubrange(s.lowerBound..<e.upperBound)
        }
        while let s = clean.range(of: "<context from=\"sidecar\">"),
              let e = clean.range(of: "</context>") {
            clean.removeSubrange(s.lowerBound..<e.upperBound)
        }
        let context = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !context.isEmpty else {
            activeToast?.dismiss()
            activeToast = ToastWindow(message: "No text found in window.")
            activeToast?.show()
            return
        }

        VoiceQA.shared.injectedContext = context
        Logger.log("Injected \(context.count) chars of window context", source: "Inject")

        ensurePanel()
        let voiceQA = VoiceQA.shared
        if case .idle = voiceQA.state {
            voiceQA.state = .done(answer: "", sources: [], knowledgeBlocks: [])
        }
        voiceQA.focusTrigger += 1

        let charCount = context.count > 1000 ? "\(context.count / 1000)K" : "\(context.count)"
        activeToast?.dismiss()
        activeToast = ToastWindow(message: "Context loaded (\(charCount) chars)")
        activeToast?.show()
    }

    /// Clipboard-based fallback: activate target app, Cmd+A/C, read clipboard.
    @MainActor
    private func clipboardInject(targetPID: pid_t) {
        let delay: UInt64 = 100_000_000 // 100ms

        Task { @MainActor in
            let saved = clipboardManager.save()

            // Activate the target app so key events go to it
            if let targetApp = NSRunningApplication(processIdentifier: targetPID) {
                targetApp.activate()
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms for app to focus
            }

            // Select all and copy
            clipboardManager.simulateKeyCombo(key: .a, flags: .maskCommand)
            try? await Task.sleep(nanoseconds: delay)
            clipboardManager.simulateKeyCombo(key: .c, flags: .maskCommand)
            try? await Task.sleep(nanoseconds: delay)

            let copiedText = NSPasteboard.general.string(forType: .string) ?? ""
            Logger.log("Clipboard fallback got \(copiedText.count) chars", source: "Inject")

            // Deselect — right arrow
            clipboardManager.simulateKeyCombo(key: 0x7C, flags: [])
            try? await Task.sleep(nanoseconds: 50_000_000)

            // Restore clipboard
            clipboardManager.restore(saved)

            guard !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                activeToast?.dismiss()
                activeToast = ToastWindow(message: "No text found in window.")
                activeToast?.show()
                return
            }

            injectText(copiedText)
        }
    }
}
