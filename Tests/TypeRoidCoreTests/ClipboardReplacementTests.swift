import Testing
@testable import TypeRoidCore

@Test func stripsConfiguredTriggerFromInput() {
    let raw = "hey john can we move this to tmrw im slammed //"
    let text = ClipboardReplacement.textBeforeTrigger(from: raw, trigger: "//")
    #expect(text == "hey john can we move this to tmrw im slammed")
}

@Test func leavesTextWithoutTriggerUntouched() {
    let raw = "hey john can we move this"
    let text = ClipboardReplacement.textBeforeTrigger(from: raw, trigger: "//")
    #expect(text == raw)
}

@Test func extractsCurrentParagraphFromCopiedText() {
    let raw = """
    Old paragraph that should not be touched.

    hey john i saw the thing come through looks good
    but can we move meeting to tmrw im slammed
    """

    let text = ClipboardReplacement.currentMessage(from: raw)
    #expect(text == "hey john i saw the thing come through looks good\nbut can we move meeting to tmrw im slammed")
}

@Test func handlesWindowsLineEndings() {
    let raw = "First paragraph\r\n\r\nsecond paragraph"
    let text = ClipboardReplacement.currentMessage(from: raw)
    #expect(text == "second paragraph")
}
