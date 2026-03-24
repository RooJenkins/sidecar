import AppKit
import Carbon.HIToolbox

final class HotkeyMonitor {
    private let action: () -> Void
    private let settings: SettingsManager
    private var flagsMonitor: Any?
    private var lastOptionTap: Date?
    private let doubleTapThreshold: TimeInterval = 0.3
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    static var current: HotkeyMonitor?

    init(settings: SettingsManager, action: @escaping () -> Void) {
        self.settings = settings
        self.action = action
    }

    private static func log(_ msg: String) {
        Logger.log(msg, source: "Hotkey")
    }

    func fire() {
        HotkeyMonitor.log("fire() called!")
        action()
    }

    func start() {
        stop()
        HotkeyMonitor.current = self

        if settings.hotkeyType == .doubleTapOption {
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
            HotkeyMonitor.log("Started double-tap Option monitor")
        } else {
            startCGEventTap()
        }
    }

    func stop() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        stopCGEventTap()
        HotkeyMonitor.current = nil
    }

    // MARK: - CGEvent Tap (most reliable approach)

    private func startCGEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let monitor = HotkeyMonitor.current else {
                    return Unmanaged.passRetained(event)
                }

                if type.rawValue == CGEventType.RawValue(UInt32.max) {
                    HotkeyMonitor.log("Event tap was disabled, re-enabling")
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                let requiredKey = monitor.settings.hotkeyKeyCode
                let requiredMods = monitor.settings.modifierFlags

                // Check modifiers
                let hasCmd = flags.contains(.maskCommand)
                let hasShift = flags.contains(.maskShift)
                let hasCtrl = flags.contains(.maskControl)
                let hasOpt = flags.contains(.maskAlternate)

                let needCmd = requiredMods.contains(.command)
                let needShift = requiredMods.contains(.shift)
                let needCtrl = requiredMods.contains(.control)
                let needOpt = requiredMods.contains(.option)

                if keyCode == requiredKey &&
                   hasCmd == needCmd && hasShift == needShift &&
                   hasCtrl == needCtrl && hasOpt == needOpt {
                    HotkeyMonitor.log("Hotkey matched! keyCode=\(keyCode)")
                    DispatchQueue.main.async {
                        monitor.fire()
                    }
                    // Consume the event so it doesn't reach the active app
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            HotkeyMonitor.log("ERROR: Failed to create CGEvent tap")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        HotkeyMonitor.log("CGEvent tap created successfully for keyCode=\(settings.hotkeyKeyCode), hotkey=\(settings.hotkeyDescription)")
    }

    private func stopCGEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    // MARK: - Double-tap Option

    private func handleFlagsChanged(_ event: NSEvent) {
        let optionPressed = event.modifierFlags.contains(.option)
        guard !optionPressed else { return }

        let rawFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard rawFlags.isEmpty else { return }

        let now = Date()

        if let last = lastOptionTap, now.timeIntervalSince(last) < doubleTapThreshold {
            lastOptionTap = nil
            action()
        } else {
            lastOptionTap = now
        }
    }

    deinit {
        stop()
    }
}
