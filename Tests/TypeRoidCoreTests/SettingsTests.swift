import Testing
@testable import TypeRoidCore

@Suite(.serialized)
struct SettingsTests {
    @Test func defaultModelUsesNanoForLowLatencyCleanup() {
        #expect(Settings.defaultModel == "gpt-4.1-nano")
    }

    @Test func opensMenuAfterRewriteByDefault() {
        let previous = Settings.openMenuAfterRewrite
        defer { Settings.openMenuAfterRewrite = previous }

        Settings.openMenuAfterRewrite = true
        #expect(Settings.openMenuAfterRewrite == true)

        Settings.openMenuAfterRewrite = false
        #expect(Settings.openMenuAfterRewrite == false)
    }

    @Test func excludedBundleIDsCanBeToggled() {
        let previous = Settings.excludedBundleIDs
        defer { Settings.excludedBundleIDs = previous }

        Settings.excludedBundleIDs = []

        #expect(Settings.isExcluded(bundleID: "com.example.notes") == false)
        Settings.setExcluded(true, bundleID: "com.example.notes")
        #expect(Settings.isExcluded(bundleID: "com.example.notes") == true)

        Settings.setExcluded(false, bundleID: "com.example.notes")
        #expect(Settings.isExcluded(bundleID: "com.example.notes") == false)
    }

    @Test func emptyBundleIDsAreIgnored() {
        let previous = Settings.excludedBundleIDs
        defer { Settings.excludedBundleIDs = previous }

        Settings.excludedBundleIDs = []
        Settings.setExcluded(true, bundleID: "")

        #expect(Settings.excludedBundleIDs.isEmpty)
        #expect(Settings.isExcluded(bundleID: nil) == false)
    }

    @Test func resetExcludedBundleIDsRestoresSafetyDefaults() {
        let previous = Settings.excludedBundleIDs
        defer { Settings.excludedBundleIDs = previous }

        Settings.excludedBundleIDs = []
        #expect(Settings.isExcluded(bundleID: "com.apple.Terminal") == false)

        Settings.resetExcludedBundleIDsToDefaults()

        #expect(Settings.isExcluded(bundleID: "com.apple.Terminal") == true)
        #expect(Settings.isExcluded(bundleID: "com.googlecode.iterm2") == true)
        #expect(Settings.isExcluded(bundleID: "dev.warp.Warp-Stable") == true)
    }
}
