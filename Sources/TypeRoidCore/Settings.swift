import Foundation

public enum Settings {
    private static let apiKeyKey = "openai_api_key"
    private static let modelKey = "openai_model"
    private static let triggerKey = "trigger"
    private static let excludedBundleIDsKey = "excluded_bundle_ids"
    private static let userConfiguredExcludedBundleIDsKey = "user_configured_excluded_bundle_ids"
    private static let openMenuAfterRewriteKey = "open_menu_after_rewrite"

    public static let defaultModel = "gpt-4.1-nano"
    public static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable"
    ]
    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser"
    ]

    public static var apiKey: String? {
        get {
            KeychainStore.read(account: apiKeyKey)
        }
        set {
            KeychainStore.write(newValue, account: apiKeyKey)
        }
    }

    public static var model: String {
        UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
    }

    public static var trigger: String {
        get {
            let value = UserDefaults.standard.string(forKey: triggerKey) ?? "//"
            return value.isEmpty ? "//" : value
        }
        set {
            UserDefaults.standard.set(newValue.isEmpty ? "//" : newValue, forKey: triggerKey)
        }
    }

    public static var openMenuAfterRewrite: Bool {
        get {
            UserDefaults.standard.object(forKey: openMenuAfterRewriteKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: openMenuAfterRewriteKey)
        }
    }

    public static var excludedBundleIDs: Set<String> {
        get {
            guard UserDefaults.standard.bool(forKey: userConfiguredExcludedBundleIDsKey) else {
                return defaultExcludedBundleIDs
            }
            return Set(UserDefaults.standard.stringArray(forKey: excludedBundleIDsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: excludedBundleIDsKey)
            UserDefaults.standard.set(true, forKey: userConfiguredExcludedBundleIDsKey)
        }
    }

    public static func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    public static func setExcluded(_ isExcluded: Bool, bundleID: String) {
        guard !bundleID.isEmpty else { return }
        var ids = excludedBundleIDs
        if isExcluded {
            ids.insert(bundleID)
        } else {
            ids.remove(bundleID)
        }
        excludedBundleIDs = ids
    }

    public static func resetExcludedBundleIDsToDefaults() {
        excludedBundleIDs = defaultExcludedBundleIDs
    }
}
