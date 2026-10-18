import Testing
@testable import TypeRoidCore

@Test func accessibilityCurrentMessageRangeUsesLastParagraph() {
    let value = """
    Earlier note.

    hey john can we move this to tmrw //
    """
    let end = value.range(of: "//")!.lowerBound

    let range = AccessibilityReplacement.currentMessageRange(in: value, endingAt: end)

    #expect(String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines) == "hey john can we move this to tmrw")
}

@Test func accessibilityCurrentMessageRangeUsesWholeValueWithoutParagraphBreak() {
    let value = "hey john can we move this to tmrw //"
    let end = value.range(of: "//")!.lowerBound

    let range = AccessibilityReplacement.currentMessageRange(in: value, endingAt: end)

    #expect(String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines) == "hey john can we move this to tmrw")
}

@Test func accessibilityReplacementPlanRemovesTriggerAndLeadingWhitespace() throws {
    let value = """
    Earlier note.

       hey john can we move this to tmrw //
    """

    let plan = try AccessibilityReplacement.replacementPlan(in: value, trigger: "//")
    var updated = value
    updated.replaceSubrange(plan.replaceRange, with: "Hey John, can we move this to tomorrow?")

    #expect(plan.text == "hey john can we move this to tmrw")
    #expect(updated.contains("Earlier note."))
    #expect(updated.contains("Hey John, can we move this to tomorrow?"))
    #expect(!updated.contains("//"))
}

@Test func focusedMessagePlanUsesTheParagraphAtTheCursor() throws {
    let value = "Earlier note.\n\nhey john can we move this to tmrw"
    let plan = try AccessibilityReplacement.focusedMessagePlan(in: value, cursor: value.endIndex, selection: nil)
    #expect(plan.text == "hey john can we move this to tmrw")
}

@Test func focusedMessagePlanUsesASelection() throws {
    let value = "keep this, fix only this part"
    let selection = value.range(of: "fix only this part")!
    let plan = try AccessibilityReplacement.focusedMessagePlan(in: value, cursor: value.endIndex, selection: selection)
    #expect(plan.text == "fix only this part")
    #expect(plan.replaceRange == selection)
}

@Test func terminalReplacementKeepsThePasteOnOneLine() {
    let pasted = AccessibilityReplacement.terminalReplacement("Hello\r\nworld\nagain\r")
    #expect(pasted == "Hello world again ")
    #expect(!pasted.contains("\n"))
}
