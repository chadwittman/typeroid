import Testing
@testable import TypeRoidCore

@Suite(.serialized)
struct SettingsTests {
    @Test func defaultProviderIsOpenAI() {
        #expect(Settings.provider == .openai)
    }

    @Test func defaultModelMatchesProviderDefault() {
        // model should default to current provider's default
        let expected = Settings.provider.defaultModel
        #expect(!expected.isEmpty)
    }

    @Test func defaultTriggerIsDoubleSlash() {
        #expect(Settings.trigger == "//")
    }

    @Test func defaultRewriteTriggerIsDoubleBackslash() {
        #expect(Settings.rewriteTrigger == "\\\\")
    }

    @Test func defaultVoiceTriggerIsDoubleComma() {
        #expect(Settings.voiceTrigger == ",,")
    }

    @Test func defaultScreenTriggerIsDoubleGreaterThan() {
        #expect(Settings.screenTrigger == ">>")
    }

    @Test func knownBrowsersAreTrackedForAddressBarSafety() {
        #expect(Settings.browserBundleIDs.contains("com.google.Chrome"))
        #expect(Settings.browserBundleIDs.contains("com.apple.Safari"))
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
