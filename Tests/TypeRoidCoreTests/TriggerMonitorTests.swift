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

@Test func triggerMonitorFiresVoiceBriefForBareCleanTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("//")

    #expect(modes == [.smartBrevity])
}

@Test func triggerMonitorFiresVoiceBriefAfterNewline() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters("first line\n//")

    #expect(modes == [.smartBrevity])
}

@Test func triggerMonitorFiresVoiceBriefForWhitespaceCleanTrigger() {
    var modes: [CleanMode] = []
    let monitor = TriggerMonitor(
        triggerProvider: { "//" },
        customCommandsProvider: { [] },
        onTrigger: { modes.append($0) }
    )

    monitor.handleTypedCharacters(" //")

    #expect(modes == [.smartBrevity])
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
