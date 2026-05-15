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
