import Testing
@testable import TypeRoidCore

@Test func juiceCueRestsWhenTheMenuBarClears() {
    #expect(JuiceCue.from(status: "") == .rest)
    #expect(JuiceCue.rest.label == "hold fn")
}

@Test func juiceCueTracksDictation() {
    #expect(JuiceCue.from(status: "fn listening...") == .juicing)
    #expect(JuiceCue.from(status: "listening...") == .juicing)
    #expect(JuiceCue.from(status: "fn on. tap fn to stop") == .openSet)
    #expect(JuiceCue.from(status: "fn cooking...") == .cooking)
    #expect(JuiceCue.from(status: "fn done") == .gains)
    #expect(JuiceCue.from(status: "Hold fn to talk") == .hint)
    #expect(JuiceCue.from(status: "Cancelled") == .spit)
    #expect(JuiceCue.from(status: "fn won't touch password fields") == .spit)
    #expect(JuiceCue.from(status: "fn needs Input Monitoring") == .access)
    #expect(JuiceCue.from(status: "fn needs Accessibility permission") == .access)
    #expect(JuiceCue.from(status: ",, done") == .gains)
    #expect(JuiceCue.from(status: "Ollama isn't running. Start it with: ollama serve") == .spit)
    #expect(JuiceCue.from(status: "Ollama not running — start with: ollama serve") == .spit)
    #expect(JuiceCue.from(status: "// needs keychain access") == .spit)
}

@Test func juiceCueKeepsTheJokeShort() {
    let labels = [
        JuiceCue.rest, .benched, .juicing, .openSet, .cooking, .gains, .spit, .hint, .access
    ].map(\.label)
    #expect(labels.allSatisfy { $0.count <= 12 })
    #expect(JuiceCue.openSet.label == "hands-free")
    #expect(JuiceCue.gains.label == "grown-up")
}
