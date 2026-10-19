import CoreFoundation
import Foundation

/// macOS binds a bare press of the globe/fn key to Emoji & Symbols unless
/// Keyboard settings say otherwise. A double tap is two of those presses, so
/// the picker opens on the gesture typeROID uses for hands-free.
/// While typeROID is enabled, that action is set to Do Nothing. The previous
/// choice is restored when typeROID is turned off or quits. fn chords still
/// go through, because this does not eat the modifier.
enum GlobeKeyClaim {
    private static let domain = "com.apple.HIToolbox"
    private static let name = "AppleFnUsageType"
    private static let overrideKey = "typeroid_globe_override"
    private static let previousKey = "typeroid_globe_previous"
    /// Stored when the system key was absent. Absent means the macOS default,
    /// which is Show Emoji & Symbols.
    private static let absent = -1

    static func claim() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: overrideKey) {
            writeSystem(0)
            return
        }
        let current = readSystem()
        if current == 0 { return }
        defaults.set(true, forKey: overrideKey)
        defaults.set(current ?? absent, forKey: previousKey)
        writeSystem(0)
    }

    static func release() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: overrideKey) else { return }
        let previous = defaults.object(forKey: previousKey) as? Int
        if previous == nil || previous == absent {
            writeSystem(nil)
        } else if let previous {
            writeSystem(previous)
        }
        defaults.removeObject(forKey: overrideKey)
        defaults.removeObject(forKey: previousKey)
    }

    private static func readSystem() -> Int? {
        CFPreferencesAppSynchronize(domain as CFString)
        guard let value = CFPreferencesCopyAppValue(name as CFString, domain as CFString) else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func writeSystem(_ value: Int?) {
        let stored: CFPropertyList? = value.map { $0 as CFNumber }
        CFPreferencesSetValue(
            name as CFString,
            stored,
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesAppSynchronize(domain as CFString)
    }
}
