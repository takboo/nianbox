import AppKit
import Carbon.HIToolbox
import SwiftUI

struct QuickCaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = QuickCaptureShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    static let supportedModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    static let modifierKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var isValid: Bool {
        keyCode < 128 && !Self.modifierKeys.contains(keyCode)
            && modifiers & ~Self.supportedModifiers == 0
            && modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) throws {
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: flags)
        guard isValid else { throw ShortcutError.invalid }
    }

    var keyName: String {
        let special: [UInt32: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
            117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘",
            116: "⇞", 121: "⇟", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let name = special[keyCode] { return name }
        // Resolve physical key codes using the current keyboard layout, including non-US layouts.
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            if UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                characters.count, &length, &characters) == noErr, length > 0 {
                return String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return "Key \(keyCode)"
    }

    var displayName: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName
    }

    var menuShortcut: KeyboardShortcut? {
        var flags: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        let specials: [UInt32: KeyEquivalent] = [49: .space, 36: .return, 48: .tab, 53: .escape,
            51: .delete, 117: .deleteForward, 123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow]
        if let key = specials[keyCode] { return KeyboardShortcut(key, modifiers: flags) }
        let name = keyName.lowercased()
        guard name.count == 1, let character = name.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
    }
}

enum ShortcutError: LocalizedError {
    case invalid
    case registration(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalid: "Include Command, Option or Control with a key. Escape cancels recording."
        case .registration(let status): "This shortcut is unavailable (macOS \(status)). Choose another combination. Your previous setting is retained."
        }
    }
}
