import SwiftUI
import AVFoundation

/// First-launch permissions onboarding. Shows which permissions are granted
/// and provides one-click buttons to open each System Settings pane.
struct OnboardingView: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var inputMonitoringGranted = checkInputMonitoring()
    @State private var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var refreshTimer: Timer?

    let onDone: () -> Void

    private var allGranted: Bool {
        accessibilityGranted && inputMonitoringGranted && microphoneGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                Text("Sidecar Setup")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Grant these permissions to enable all features")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Permission rows
            VStack(spacing: 12) {
                PermissionOnboardingRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Read window text to find relevant documents",
                    granted: accessibilityGranted,
                    action: {
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                )

                PermissionOnboardingRow(
                    icon: "keyboard.fill",
                    title: "Input Monitoring",
                    description: "Detect hotkeys (⌘J for chat/voice, ⌘U for context)",
                    granted: inputMonitoringGranted,
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )

                PermissionOnboardingRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Record voice for voice Q&A",
                    granted: microphoneGranted,
                    action: {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Footer
            HStack {
                if allGranted {
                    Label("All set!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Text("Grant permissions above, then click Done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(allGranted ? "Get Started" : "Done") {
                    refreshTimer?.invalidate()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .onAppear {
            // Poll permission status every 2 seconds
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                DispatchQueue.main.async {
                    accessibilityGranted = AXIsProcessTrusted()
                    inputMonitoringGranted = Self.checkInputMonitoring()
                    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }

    private static func checkInputMonitoring() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }
}

private func checkInputMonitoring() -> Bool {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, _, event, _ in Unmanaged.passRetained(event) },
        userInfo: nil
    ) else { return false }
    CFMachPortInvalidate(tap)
    return true
}

struct PermissionOnboardingRow: View {
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : icon)
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
