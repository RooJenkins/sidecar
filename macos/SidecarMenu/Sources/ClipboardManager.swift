import AppKit

final class ClipboardManager {
    struct SavedClipboard {
        let items: [NSPasteboardItem]
    }

    func save() -> SavedClipboard {
        let pasteboard = NSPasteboard.general
        var items: [NSPasteboardItem] = []

        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            items.append(copy)
        }

        return SavedClipboard(items: items)
    }

    func restore(_ saved: SavedClipboard) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !saved.items.isEmpty {
            pasteboard.writeObjects(saved.items)
        }
    }

    func simulateKeyCombo(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// Common key codes
extension CGKeyCode {
    static let a: CGKeyCode = 0x00
    static let c: CGKeyCode = 0x08
    static let v: CGKeyCode = 0x09
    static let escape: CGKeyCode = 0x35
    static let tab: CGKeyCode = 0x30
    static let upArrow: CGKeyCode = 0x7E
}
