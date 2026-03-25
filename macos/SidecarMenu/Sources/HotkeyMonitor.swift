import AppKit
import Carbon.HIToolbox

final class HotkeyMonitor {
    enum Mode {
        case tap        // Fire action on keyDown only
        case hold       // Fire action on keyDown, onRelease on keyUp
        case tapOrHold  // Short press = onTap, long press = action + onRelease
    }

    private let mode: Mode
    private let action: () -> Void
    private let onRelease: (() -> Void)?
    private let settings: SettingsManager
    private var usesSharedTap = false

    private let customKeyCode: UInt16?
    private let customModifiers: NSEvent.ModifierFlags?

    var onTap: (() -> Void)?
    var holdThreshold: TimeInterval
    var holdTimer: Timer?
    var isHolding = false
    var tapOrHoldActive = false  // True when we consumed a keyDown and are waiting for keyUp

    private static var activeMonitors: [HotkeyMonitor] = []
    private static var sharedEventTap: CFMachPort?
    private static var sharedRunLoopSource: CFRunLoopSource?

    init(settings: SettingsManager, keyCode: UInt16? = nil, modifiers: NSEvent.ModifierFlags? = nil, mode: Mode = .tap, action: @escaping () -> Void, onRelease: (() -> Void)? = nil, onTap: (() -> Void)? = nil, holdThreshold: TimeInterval = 0.3) {
        self.settings = settings
        self.customKeyCode = keyCode
        self.customModifiers = modifiers
        self.mode = mode
        self.action = action
        self.onRelease = onRelease
        self.onTap = onTap
        self.holdThreshold = holdThreshold
    }

    static func log(_ msg: String) {
        Logger.log(msg, source: "Hotkey")
    }

    func fire() { action() }

    var effectiveKeyCode: UInt16 { customKeyCode ?? settings.hotkeyKeyCode }
    var effectiveModifiers: NSEvent.ModifierFlags { customModifiers ?? settings.modifierFlags }

    func start() {
        stop()
        usesSharedTap = true
        HotkeyMonitor.activeMonitors.append(self)
        HotkeyMonitor.ensureSharedTap()
        HotkeyMonitor.log("Registered hotkey: keyCode=\(effectiveKeyCode) mode=\(mode)")
    }

    func stop() {
        holdTimer?.invalidate()
        holdTimer = nil
        if usesSharedTap {
            HotkeyMonitor.activeMonitors.removeAll { $0 === self }
            usesSharedTap = false
            if HotkeyMonitor.activeMonitors.isEmpty {
                HotkeyMonitor.tearDownSharedTap()
            }
        }
    }

    // MARK: - Shared CGEvent Tap

    static func ensureSharedTap() {
        guard sharedEventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard !HotkeyMonitor.activeMonitors.isEmpty else {
                    return Unmanaged.passRetained(event)
                }

                if type.rawValue == CGEventType.RawValue(UInt32.max) {
                    if let tap = HotkeyMonitor.sharedEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                // Pass through flagsChanged events
                if type == .flagsChanged {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                let isKeyUp = type == .keyUp
                let isRepeat = !isKeyUp && event.getIntegerValueField(.keyboardEventAutorepeat) != 0

                let hasCmd = flags.contains(.maskCommand)
                let hasShift = flags.contains(.maskShift)
                let hasCtrl = flags.contains(.maskControl)
                let hasOpt = flags.contains(.maskAlternate)

                for monitor in HotkeyMonitor.activeMonitors {
                    let requiredKey = monitor.effectiveKeyCode
                    let requiredMods = monitor.effectiveModifiers

                    let needCmd = requiredMods.contains(.command)
                    let needShift = requiredMods.contains(.shift)
                    let needCtrl = requiredMods.contains(.control)
                    let needOpt = requiredMods.contains(.option)

                    let modsMatch = isKeyUp || (hasCmd == needCmd && hasShift == needShift &&
                                                hasCtrl == needCtrl && hasOpt == needOpt)

                    if keyCode == requiredKey && modsMatch {
                        if isKeyUp {
                            if monitor.mode == .hold, let release = monitor.onRelease {
                                HotkeyMonitor.log("Hold released: keyCode=\(keyCode)")
                                DispatchQueue.main.async { release() }
                                return nil
                            }
                            if monitor.mode == .tapOrHold && monitor.tapOrHoldActive {
                                monitor.tapOrHoldActive = false
                                DispatchQueue.main.async {
                                    monitor.holdTimer?.invalidate()
                                    monitor.holdTimer = nil
                                    if monitor.isHolding {
                                        monitor.isHolding = false
                                        HotkeyMonitor.log("TapOrHold: hold end keyCode=\(keyCode)")
                                        monitor.onRelease?()
                                    } else {
                                        HotkeyMonitor.log("TapOrHold: tap keyCode=\(keyCode)")
                                        monitor.onTap?()
                                    }
                                }
                                return nil
                            }
                        } else if isRepeat {
                            if monitor.mode == .hold || monitor.mode == .tapOrHold { return nil }
                        } else {
                            if monitor.mode == .tapOrHold {
                                monitor.tapOrHoldActive = true
                                DispatchQueue.main.async {
                                    monitor.holdTimer?.invalidate()
                                    monitor.isHolding = false
                                    monitor.holdTimer = Timer.scheduledTimer(withTimeInterval: monitor.holdThreshold, repeats: false) { _ in
                                        monitor.isHolding = true
                                        HotkeyMonitor.log("TapOrHold: hold start keyCode=\(keyCode)")
                                        monitor.fire()
                                    }
                                }
                                return nil
                            }
                            HotkeyMonitor.log("Hotkey down: keyCode=\(keyCode)")
                            DispatchQueue.main.async { monitor.fire() }
                            return nil
                        }
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            log("ERROR: Failed to create shared CGEvent tap")
            return
        }

        sharedEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        sharedRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("Shared CGEvent tap created")
    }

    private static func tearDownSharedTap() {
        if let source = sharedRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            sharedRunLoopSource = nil
        }
        if let tap = sharedEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            sharedEventTap = nil
        }
    }

    deinit { stop() }
}

