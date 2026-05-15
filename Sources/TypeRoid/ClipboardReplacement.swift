import AppKit
import Carbon
import Foundation

enum ClipboardReplacementError: LocalizedError {
    case copyFailed
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .copyFailed:
            return "Could not copy the current text."
        case .emptySelection:
            return "No text was selected for cleanup."
        }
    }
}

struct CapturedText {
    let text: String
}

enum ClipboardReplacement {
    static func captureCurrentLineBeforeTrigger(trigger: String) async throws -> CapturedText {
        let pasteboard = NSPasteboard.general
        let previous = PasteboardSnapshot.capture(from: pasteboard)

        // Remove the trigger, then select from the cursor to the beginning of the
        // current line/message. This is the POC fallback that works in many text
        // fields even when Accessibility text ranges are not exposed.
        for _ in trigger {
            key(.delete)
        }
        key(.leftArrow, flags: [.maskCommand, .maskShift])
        key("c", flags: [.maskCommand])
        try await Task.sleep(for: .milliseconds(120))

        guard let raw = pasteboard.string(forType: .string) else {
            previous.restore(to: pasteboard)
            throw ClipboardReplacementError.copyFailed
        }

        previous.restore(to: pasteboard)

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ClipboardReplacementError.emptySelection
        }
        return CapturedText(text: text)
    }

    static func replaceCurrentSelection(with text: String) {
        let pasteboard = NSPasteboard.general
        let previous = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        key("v", flags: [.maskCommand])

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            previous.restore(to: pasteboard)
        }
    }

    private static func key(_ specialKey: SpecialKey, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: specialKey.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: specialKey.rawValue, keyDown: false)
        else { return }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func key(_ character: String, flags: CGEventFlags = []) {
        guard let scalar = character.unicodeScalars.first else { return }
        let keyCode = keyCodeForLowercaseASCII(scalar)
        guard keyCode != 0 else { return }

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func keyCodeForLowercaseASCII(_ scalar: UnicodeScalar) -> CGKeyCode {
        switch scalar {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "v": return CGKeyCode(kVK_ANSI_V)
        default: return 0
        }
    }
}

private enum SpecialKey: CGKeyCode {
    case delete = 0x33
    case leftArrow = 0x7B
}

private struct PasteboardSnapshot {
    let string: String?

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        PasteboardSnapshot(string: pasteboard.string(forType: .string))
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let string {
            pasteboard.setString(string, forType: .string)
        }
    }
}
