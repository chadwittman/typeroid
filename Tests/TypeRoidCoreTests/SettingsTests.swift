import Testing
@testable import TypeRoidCore

@Suite(.serialized)
struct SettingsTests {
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
}
