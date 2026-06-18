import AppKit
import ApplicationServices
import Foundation

public enum AccessibilityReplacementError: LocalizedError, Sendable {
    case missingFocusedElement
    case unsupportedElement
    case secureTextField
    case triggerNotFound
    case emptyMessage
    case replacementFailed

    public var errorDescription: String? {
        switch self {
        case .missingFocusedElement:
            return "No focused text field was found."
        case .unsupportedElement:
            return "The focused text field does not expose editable text."
        case .secureTextField:
            return "TypeRoid will not run in secure text fields."
        case .triggerNotFound:
            return "The trigger was not found in the focused text."
        case .emptyMessage:
            return "No message was found before the trigger."
        case .replacementFailed:
            return "The focused text could not be replaced through Accessibility."
        }
    }
}

public struct AccessibilityCapturedText {
    public let text: String

    fileprivate let element: AXUIElement
    fileprivate let fullValue: String
    fileprivate let replaceRange: Range<String.Index>
}

struct AccessibilityReplacementPlan {
    let text: String
    let replaceRange: Range<String.Index>
}

public enum AccessibilityReplacement {
    public static func focusedElementIsSecureTextEntry() -> Bool {
        guard let element = try? focusedElement() else { return false }
        return isSecureTextEntry(element)
    }

    public static func focusedElementLooksLikeBrowserAddressBar(bundleID: String?) -> Bool {
        guard let bundleID, Settings.browserBundleIDs.contains(bundleID),
              let element = try? focusedElement()
        else { return false }

        let metadata = focusedElementMetadata(element)
            .map { $0.lowercased() }
            .joined(separator: " ")

        let blockedPhrases = [
            "address and search",
            "address bar",
            "location bar",
            "smart search",
            "omnibox",
            "url"
        ]
        return blockedPhrases.contains { metadata.contains($0) }
    }

    public static func capturedTextLooksLikeBrowserAddressBar(_ captured: AccessibilityCapturedText, bundleID: String?) -> Bool {
        guard let bundleID, Settings.browserBundleIDs.contains(bundleID) else { return false }
        let metadata = focusedElementMetadata(captured.element)
            .map { $0.lowercased() }
            .joined(separator: " ")
        let blockedPhrases = [
            "address and search",
            "address bar",
            "location bar",
            "smart search",
            "omnibox",
            "url"
        ]
        return blockedPhrases.contains { metadata.contains($0) }
    }

    public static func captureCurrentMessageBeforeTrigger(trigger: String, fullCapture: Bool = false) throws -> AccessibilityCapturedText {
        let element = try focusedElement()
        guard !isSecureTextEntry(element) else {
            throw AccessibilityReplacementError.secureTextField
        }

        var valueObject: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueObject
        )
        guard valueResult == .success, let value = valueObject as? String else {
            throw AccessibilityReplacementError.unsupportedElement
        }

        let plan = try replacementPlan(in: value, trigger: trigger, fullCapture: fullCapture)

        return AccessibilityCapturedText(
            text: plan.text,
            element: element,
            fullValue: value,
            replaceRange: plan.replaceRange
        )
    }

    private static func focusedElement() throws -> AXUIElement {
        let system = AXUIElementCreateSystemWide()
        var focusedObject: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusedResult == .success, let focusedObject else {
            throw AccessibilityReplacementError.missingFocusedElement
        }

        return focusedObject as! AXUIElement
    }

    private static func isSecureTextEntry(_ element: AXUIElement) -> Bool {
        var roleObject: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObject) == .success,
           let role = roleObject as? String,
           role.localizedCaseInsensitiveContains("secure") {
            return true
        }

        var subroleObject: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleObject) == .success,
           let subrole = subroleObject as? String,
           subrole.localizedCaseInsensitiveContains("secure") {
            return true
        }

        return false
    }

    private static func focusedElementMetadata(_ element: AXUIElement) -> [String] {
        [
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXRoleDescriptionAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute
        ].compactMap { attribute in
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
                return nil
            }
            return value as? String
        }
    }

    public static func replaceCapturedText(_ captured: AccessibilityCapturedText, with replacement: String, selectReplacement: Bool = false) throws {
        var updated = captured.fullValue
        updated.replaceSubrange(captured.replaceRange, with: replacement)

        let result = AXUIElementSetAttributeValue(
            captured.element,
            kAXValueAttribute as CFString,
            updated as CFTypeRef
        )

        if result == .success {
            if selectReplacement && !replacement.isEmpty {
                let start = captured.fullValue.distance(from: captured.fullValue.startIndex, to: captured.replaceRange.lowerBound)
                var cfRange = CFRange(location: start, length: replacement.count)
                if let axVal = AXValueCreate(AXValueType.cfRange, &cfRange) {
                    AXUIElementSetAttributeValue(captured.element, kAXSelectedTextRangeAttribute as CFString, axVal)
                }
            }
        } else {
            // AX write blocked (browser contenteditable: Twitter, Notion, Linear, etc.)
            // Fall back to keyboard simulation: select back over the original text, then paste.
            let selectCount = captured.fullValue.distance(
                from: captured.replaceRange.lowerBound,
                to: captured.replaceRange.upperBound
            )
            try keyboardSimulationReplace(selectCount: selectCount, replacement: replacement)
        }
    }

    public static func replaceCapturedTextWithKeyboard(_ captured: AccessibilityCapturedText, with replacement: String) throws {
        let selectCount = captured.fullValue.distance(
            from: captured.replaceRange.lowerBound,
            to: captured.replaceRange.upperBound
        )
        try keyboardSimulationReplace(selectCount: selectCount, replacement: replacement)
    }

    public static func replaceCurrentFieldWithKeyboard(_ replacement: String) {
        let pb = NSPasteboard.general
        let savedContents = pasteboardContents(from: pb)
        key("a", flags: [.maskCommand])
        usleep(60_000)
        pasteText(replacement)
        restorePasteboard(contents: savedContents, after: 0.35)
    }

    /// Select `selectCount` chars to the left, paste `replacement` via clipboard.
    /// Used as a fallback when AX write is unavailable (browser contenteditable).
    private static func keyboardSimulationReplace(selectCount: Int, replacement: String) throws {
        let src = CGEventSource(stateID: .hidSystemState)

        // Save current clipboard so we can restore it after paste
        let pb = NSPasteboard.general
        let savedContents = pasteboardContents(from: pb)

        // Select the characters to replace (Shift+Left × selectCount)
        for _ in 0..<selectCount {
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x7B, keyDown: true)  // Left arrow
            let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x7B, keyDown: false)
            down?.flags = .maskShift
            up?.flags   = .maskShift
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }

        pasteText(replacement)

        restorePasteboard(contents: savedContents, after: 0.35)
    }

    private static func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)   // V
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    private static func pasteboardContents(from pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []
    }

    private static func restorePasteboard(contents: [(NSPasteboard.PasteboardType, Data)], after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            for (type, data) in contents {
                pasteboard.setData(data, forType: type)
            }
        }
    }

    private static func key(_ character: String, flags: CGEventFlags = []) {
        guard let scalar = character.unicodeScalars.first else { return }
        let keyCode: CGKeyCode
        switch scalar {
        case "a": keyCode = 0x00
        default: return
        }

        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Captures the current cursor position as an empty replace range so callers can
    /// pass the result to `startInlineLoading` / `replaceCapturedText` without any
    /// pre-existing text to replace.
    public static func captureAtCursor() throws -> AccessibilityCapturedText {
        let element = try focusedElement()

        var rangeObj: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeObj) == .success,
              let axRangeVal = rangeObj else { throw AccessibilityReplacementError.unsupportedElement }

        var cfRange = CFRange(location: 0, length: 0)
        AXValueGetValue(axRangeVal as! AXValue, AXValueType.cfRange, &cfRange)

        var valueObj: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj) == .success,
              let currentValue = valueObj as? String else { throw AccessibilityReplacementError.unsupportedElement }

        let cursorOffset = min(cfRange.location, currentValue.count)
        let cursorIdx = currentValue.index(currentValue.startIndex, offsetBy: cursorOffset)
        // Empty range at cursor — replaceCapturedText will insert at this position
        return AccessibilityCapturedText(
            text: "",
            element: element,
            fullValue: currentValue,
            replaceRange: cursorIdx..<cursorIdx
        )
    }

    /// Captures the trigger itself as the replace range. Used when a trigger with
    /// no preceding message should become an insertion workflow, such as voice mode.
    public static func captureTriggerOnly(trigger: String) throws -> AccessibilityCapturedText {
        let element = try focusedElement()
        guard !isSecureTextEntry(element) else {
            throw AccessibilityReplacementError.secureTextField
        }

        var valueObject: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueObject
        )
        guard valueResult == .success, let value = valueObject as? String else {
            throw AccessibilityReplacementError.unsupportedElement
        }
        guard let triggerRange = value.range(of: trigger, options: .backwards) else {
            throw AccessibilityReplacementError.triggerNotFound
        }

        return AccessibilityCapturedText(
            text: "",
            element: element,
            fullValue: value,
            replaceRange: triggerRange
        )
    }

    static func currentMessageRange(in value: String, endingAt end: String.Index, fullCapture: Bool = false) -> Range<String.Index> {
        if fullCapture {
            return value.startIndex..<end
        }
        let prefix = value[..<end]
        if let paragraphBreak = prefix.range(of: "\n\n", options: .backwards) {
            return paragraphBreak.upperBound..<end
        }
        if let lineBreak = prefix.range(of: "\n", options: .backwards) {
            return lineBreak.upperBound..<end
        }
        return value.startIndex..<end
    }

    static func replacementPlan(in value: String, trigger: String, fullCapture: Bool = false) throws -> AccessibilityReplacementPlan {
        guard let triggerRange = value.range(of: trigger, options: .backwards) else {
            throw AccessibilityReplacementError.triggerNotFound
        }

        // Don't fire // inside URL schemes (http://, https://, ftp://, etc.)
        // The character immediately before // would be ':' in any URL scheme.
        if trigger == "//" {
            let before = value[..<triggerRange.lowerBound]
            if before.last == ":" {
                throw AccessibilityReplacementError.triggerNotFound
            }
        }

        // Don't fire == when it looks like a code equality check:
        // preceded by a non-space char and followed by another '=' or space+value
        // (simple guard: skip if the char before == is alphanumeric or ) or ]  )
        if trigger == "==" {
            let before = value[..<triggerRange.lowerBound]
            if let lastChar = before.last, lastChar.isLetter || lastChar.isNumber || lastChar == ")" || lastChar == "]" {
                // Could be code — only proceed if there's meaningful prose before it
                // (i.e. there's a space somewhere in the last 20 chars, suggesting natural language)
                let context = String(before.suffix(20))
                if !context.contains(" ") {
                    throw AccessibilityReplacementError.triggerNotFound
                }
            }
        }

        let messageRange = currentMessageRange(in: value, endingAt: triggerRange.lowerBound, fullCapture: fullCapture)
        let message = String(value[messageRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            throw AccessibilityReplacementError.emptyMessage
        }

        let leadingWhitespace = value[messageRange].prefix { $0.isWhitespace }
        let adjustedStart = value.index(messageRange.lowerBound, offsetBy: leadingWhitespace.count)
        return AccessibilityReplacementPlan(
            text: message,
            replaceRange: adjustedStart..<triggerRange.upperBound
        )
    }
}
