import Testing
@testable import TypeRoidCore

@Test func triggerMonitorIgnoresHttpSchemeSlashes() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("http://")

    #expect(modes.isEmpty)
}

@Test func triggerMonitorIgnoresHttpsSchemeSlashes() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("https://")

    #expect(modes.isEmpty)
}

@Test func triggerMonitorFiresCleanForBareCleanTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("//")

    #expect(modes == [.clean])
}

@Test func triggerMonitorFiresCleanAfterNewline() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("first line\n//")

    #expect(modes == [.clean])
}

@Test func triggerMonitorFiresCleanForWhitespaceCleanTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters(" //")

    #expect(modes == [.clean])
}

@Test func triggerMonitorFiresVoiceBriefForVoiceTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        voiceTriggerProvider: { ",," },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters(",,")

    #expect(modes == [.smartBrevity])
}

@Test func triggerMonitorFiresVoiceTriggerAfterText() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        voiceTriggerProvider: { ",," },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("do not voice ,,")

    #expect(modes == [.smartBrevity])
}

@Test func triggerMonitorFiresScreenTriggerAfterText() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        screenTriggerProvider: { ">>" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("what is this error >>")

    #expect(modes == [.screen])
}

@Test func triggerMonitorScreenTriggerBeatsCustomCommand() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        screenTriggerProvider: { ">>" },
        customCommandsProvider: { [">>"] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("look here >>")

    #expect(modes == [.screen])
}

@Test func triggerMonitorStillFiresCleanTriggerAfterText() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("clean this //")

    #expect(modes == [.clean])
}

@Test func triggerMonitorKeepsTheTypedTextBeforeCleanTrigger() {
    var matches: [TypedTrigger] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { matches.append($0) }
    )

    monitor.handleTypedCharacters("fix this sentence //")

    #expect(matches.count == 1)
    #expect(matches[0].mode == .clean)
    #expect(matches[0].textBefore == "fix this sentence")
    #expect(matches[0].deleteCount == "fix this sentence //".count)
    #expect(!matches[0].bufferTruncated)
}

@Test func slashKeyCodeIsTheCleanTriggerCharacter() {
    #expect(TriggerMonitor.characterForKeyCode(0x2C, shifted: false) == "/")
    #expect(TriggerMonitor.characterForKeyCode(0x2C, shifted: true) == "?")
}

@Test func triggerMonitorCanFireCleanTriggerAfterUrlText() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0.mode) }
    )

    monitor.handleTypedCharacters("https://example.com clean this //")

    #expect(modes == [.clean])
}
