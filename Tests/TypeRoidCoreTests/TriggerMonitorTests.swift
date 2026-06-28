import Testing
@testable import TypeRoidCore

@Test func triggerMonitorIgnoresHttpSchemeSlashes() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("http://")

    #expect(modes.isEmpty)
}

@Test func triggerMonitorIgnoresHttpsSchemeSlashes() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("https://")

    #expect(modes.isEmpty)
}

@Test func triggerMonitorFiresCleanForBareCleanTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("//")

    #expect(modes == [.clean])
}

@Test func triggerMonitorFiresCleanAfterNewline() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("first line\n//")

    #expect(modes == [.clean])
}

@Test func triggerMonitorFiresCleanForWhitespaceCleanTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
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
        onTrigger: { modes.append($0) }
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
        onTrigger: { modes.append($0) }
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
        onTrigger: { modes.append($0) }
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
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("look here >>")

    #expect(modes == [.screen])
}

@Test func triggerMonitorStillFiresCleanTriggerAfterText() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("clean this //")

    #expect(modes == [.clean])
}

@Test func triggerMonitorCanFireCleanTriggerAfterUrlText() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("https://example.com clean this //")

    #expect(modes == [.clean])
}
