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
