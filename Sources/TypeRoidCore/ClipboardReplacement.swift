import AppKit
import Carbon
import Foundation

public enum ClipboardReplacementError: LocalizedError, Sendable {
    case copyFailed
    case emptySelection

    public var errorDescription: String? {
        switch self {
        case .copyFailed:
            return "Could not copy the current text."
        case .emptySelection:
            return "No text was selected for cleanup."
        }
    }
}

public struct CapturedText: Sendable {
    public let text: String
}

public enum ClipboardReplacement {
    public static func textBeforeTrigger(from raw: String, trigger: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(trigger) else { return trimmed }
        return String(trimmed.dropLast(trigger.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func currentMessage(from raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.components(separatedBy: "\n\n")
        return (paragraphs.last ?? normalized).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func captureCurrentMessageBeforeTrigger(trigger: String) async throws -> CapturedText {
        let pasteboard = NSPasteboard.general
        let previous = PasteboardSnapshot.capture(from: pasteboard)

        // Remove the trigger, then select from the cursor to the beginning of the
        // current paragraph/message. Try paragraph selection first; if the focused
        // app ignores it, collapse back to the cursor and try single-line selection.
        for _ in trigger {
            key(.delete)
        }

        var raw = try await copiedSelection(
            pasteboard: pasteboard,
            select: {
                key(.upArrow, flags: [.maskAlternate, .maskShift])
            }
        )
        if raw == nil {
            raw = try await copiedSelection(
                pasteboard: pasteboard,
                select: {
                    key(.rightArrow)
                    key(.leftArrow, flags: [.maskCommand, .maskShift])
                }
            )
        }

        guard let raw else {
            previous.restore(to: pasteboard)
            throw ClipboardReplacementError.emptySelection
        }

        previous.restore(to: pasteboard)

        let text = currentMessage(from: textBeforeTrigger(from: raw, trigger: trigger))
        guard !text.isEmpty else {
            throw ClipboardReplacementError.emptySelection
        }
        return CapturedText(text: text)
    }

    private static func copiedSelection(pasteboard: NSPasteboard, select: () -> Void) async throws -> String? {
        pasteboard.clearContents()
        select()
        key("c", flags: [.maskCommand])
        try await Task.sleep(for: .milliseconds(120))

        guard let raw = pasteboard.string(forType: .string) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : raw
    }

    public static func replaceCurrentSelection(with text: String) {
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
    case rightArrow = 0x7C
    case upArrow = 0x7E
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
