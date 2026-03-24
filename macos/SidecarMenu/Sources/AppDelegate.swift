import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyMonitor: HotkeyMonitor?
    private let settings = SettingsManager.shared
    private let clipboardManager = ClipboardManager()
    private var settingsWindow: NSWindow?
    private var managementWindow: NSWindow?
    private var pickerPanel: ResultPickerPanel?
    private var activeToast: ToastWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("App launching (v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))")

        // Prompt for Accessibility if not granted
        let trusted = AXIsProcessTrusted()
        Logger.log("AXIsProcessTrusted = \(trusted)")

        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            Logger.log("Prompted user for Accessibility permission")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Try custom sidecar icon from multiple locations
            let icon: NSImage? = {
                // SPM resource bundle
                if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") {
                    return NSImage(contentsOf: url)
                }
                // Direct in Resources/
                let resourcePath = Bundle.main.bundlePath + "/Contents/Resources/MenuBarIcon.png"
                if FileManager.default.fileExists(atPath: resourcePath) {
                    return NSImage(contentsOfFile: resourcePath)
                }
                return nil
            }()

            if let icon {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "Sidecar")
            }
        }

        buildMenu()

        let monitor = HotkeyMonitor(settings: settings) { [weak self] in
            Logger.log("Hotkey triggered!", source: "Hotkey")
            self?.performInjection()
        }
        monitor.start()
        hotkeyMonitor = monitor
        Logger.log("Hotkey monitor started. Type: \(settings.hotkeyType.rawValue), key: \(settings.hotkeyDescription)")

        // Auto-watch indexed folders
        if settings.autoWatch && !settings.indexedFolders.isEmpty {
            for folder in settings.indexedFolders {
                WatchManager.shared.startWatching(path: folder, cliPath: settings.cliPath)
            }
            Logger.log("Auto-watching \(settings.indexedFolders.count) folder(s)")
        }
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
        NSApp.terminate(nil)
    }

    @MainActor
    private func performInjection() {
        guard settings.enabled else {
            Logger.log("Injection skipped: disabled", source: "Inject")
            return
        }

        guard AXIsProcessTrusted() else {
            Logger.log("Injection skipped: no accessibility permission", source: "Inject")
            activeToast?.dismiss()
            activeToast = ToastWindow(message: "⚠ Accessibility permission required.\nGrant in System Settings → Privacy → Accessibility.")
            activeToast?.show()
            return
        }

        Logger.log("Starting injection...", source: "Inject")

        let delay: UInt64 = 80_000_000 // 80ms between key combos

        Task { @MainActor in
            do {
                let savedClipboard = clipboardManager.save()

                // ── Read conversation history via Accessibility API ──────
                // This reads the full window text without any keyboard tricks
                let windowText = AccessibilityReader.readWindowText() ?? ""
                Logger.log("AX window text: \(windowText.count) chars", source: "Inject")

                // ── Grab input box text via Cmd+A/C ─────────────────────
                clipboardManager.simulateKeyCombo(key: .a, flags: .maskCommand)
                try await Task.sleep(nanoseconds: delay)
                clipboardManager.simulateKeyCombo(key: .c, flags: .maskCommand)
                try await Task.sleep(nanoseconds: delay)

                let inputText = NSPasteboard.general.string(forType: .string) ?? ""
                Logger.log("Input box text: \(inputText.count) chars", source: "Inject")

                // Deselect — move cursor to end
                clipboardManager.simulateKeyCombo(key: 0x7C, flags: []) // right arrow
                try await Task.sleep(nanoseconds: delay)

                // Combine: window text (conversation) + input box text
                let fullContext: String
                if !windowText.isEmpty && windowText.count > inputText.count {
                    // Strip previously injected context blocks
                    var clean = windowText
                    while let s = clean.range(of: "<company_context>"),
                          let e = clean.range(of: "</company_context>") {
                        clean.removeSubrange(s.lowerBound..<e.upperBound)
                    }
                    while let s = clean.range(of: "<context from=\"sidecar\">"),
                          let e = clean.range(of: "</context>") {
                        clean.removeSubrange(s.lowerBound..<e.upperBound)
                    }
                    fullContext = clean.trimmingCharacters(in: .whitespacesAndNewlines)
                    Logger.log("Using AX window text: \(fullContext.count) chars", source: "Inject")
                } else if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fullContext = inputText
                    Logger.log("Using input box text only: \(fullContext.count) chars", source: "Inject")
                } else {
                    clipboardManager.restore(savedClipboard)
                    self.activeToast?.dismiss()
                    self.activeToast = ToastWindow(message: "No text found.")
                    self.activeToast?.show()
                    return
                }

                // Restore clipboard before any UI
                clipboardManager.restore(savedClipboard)

                // ── Phase 1: Instant BM25 results ────────────────────────
                let queryText = String(fullContext.suffix(500))
                let bm25Results = try SidecarCLI.search(
                    query: queryText,
                    maxResults: settings.maxResults * 3,
                    cliPath: settings.cliPath
                )

                guard !bm25Results.isEmpty else {
                    self.activeToast?.dismiss()
                    self.activeToast = ToastWindow(message: "No matching documents found.")
                    self.activeToast?.show()
                    return
                }

                // Show picker immediately with BM25 candidates
                self.activeToast?.dismiss()
                let picker = ResultPickerPanel(
                    results: Array(bm25Results.prefix(settings.maxResults)),
                    onDismiss: { [weak self] in self?.pickerPanel = nil }
                )
                self.pickerPanel = picker
                picker.setRefining(true)
                picker.show()

                Logger.log("Showing \(bm25Results.count) BM25 candidates, refining with AI...", source: "Inject")

                // ── Phase 2: AI refinement in background ─────────────────
                let conversation = String(fullContext.suffix(8000))
                let maxResults = settings.maxResults
                let cliPath = settings.cliPath

                let aiResults = try await SidecarCLI.smartSearch(
                    conversation: conversation,
                    maxResults: maxResults,
                    cliPath: cliPath
                )

                // Update picker with AI-filtered results
                if aiResults.isEmpty {
                    picker.updateResults([])
                    picker.dismiss()
                    self.activeToast = ToastWindow(message: "No relevant documents found.")
                    self.activeToast?.show()
                } else {
                    Logger.log("AI refined to \(aiResults.count) results", source: "Inject")
                    picker.updateResults(aiResults)
                }
            } catch {
                self.activeToast?.dismiss()
                Logger.log("Injection error: \(error)", source: "Inject")
                self.activeToast = ToastWindow(message: "⚠ Injection failed: \(error.localizedDescription)")
                self.activeToast?.show()
            }
        }
    }
}
