import AppKit
import SwiftUI

/// NSPanel subclass that accepts clicks without stealing focus from the active app.
private class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Make this panel key so buttons work, but don't activate our app
        makeKey()
    }
}

final class ToastWindow {
    private let message: String
    private let isLoading: Bool
    private var panel: NSPanel?
    private var autoDismissWork: DispatchWorkItem?

    init(message: String, loading: Bool = false) {
        self.message = message
        self.isLoading = loading
    }

    @MainActor
    func show(duration: TimeInterval = 3) {
        guard let screen = NSScreen.main else { return }

        let panel = ClickablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostView = NSHostingView(rootView: ToastContentView(
            message: message,
            isLoading: isLoading,
            onClose: { [weak self] in
                self?.dismiss()
            }
        ))
        panel.contentView = hostView

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 200
        let y = screenFrame.maxY - 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.orderFrontRegardless()
        self.panel = panel

        // Auto-dismiss (loading toasts stay until manually dismissed)
        if !isLoading {
            let work = DispatchWorkItem { [weak self] in
                self?.dismiss()
            }
            autoDismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    @MainActor
    func dismiss() {
        autoDismissWork?.cancel()
        autoDismissWork = nil
        panel?.close()
        panel = nil
    }
}

private struct ToastContentView: View {
    let message: String
    let isLoading: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
            }

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.85))
        )
        .frame(maxWidth: 400)
    }
}
