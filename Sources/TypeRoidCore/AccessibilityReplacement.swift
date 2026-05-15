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

    public static func captureCurrentMessageBeforeTrigger(trigger: String) throws -> AccessibilityCapturedText {
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

        let plan = try replacementPlan(in: value, trigger: trigger)

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

    public static func replaceCapturedText(_ captured: AccessibilityCapturedText, with replacement: String) throws {
        var updated = captured.fullValue
        updated.replaceSubrange(captured.replaceRange, with: replacement)

        let result = AXUIElementSetAttributeValue(
            captured.element,
            kAXValueAttribute as CFString,
            updated as CFTypeRef
        )
        guard result == .success else {
            throw AccessibilityReplacementError.replacementFailed
        }
    }

    static func currentMessageRange(in value: String, endingAt end: String.Index) -> Range<String.Index> {
        let prefix = value[..<end]
        if let paragraphBreak = prefix.range(of: "\n\n", options: .backwards) {
            return paragraphBreak.upperBound..<end
        }
        return value.startIndex..<end
    }

    static func replacementPlan(in value: String, trigger: String) throws -> AccessibilityReplacementPlan {
        guard let triggerRange = value.range(of: trigger, options: .backwards) else {
            throw AccessibilityReplacementError.triggerNotFound
        }

        let messageRange = currentMessageRange(in: value, endingAt: triggerRange.lowerBound)
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
