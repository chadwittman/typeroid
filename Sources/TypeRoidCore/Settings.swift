import Foundation

public enum Settings {
    private static let apiKeyKey = "openai_api_key"
    private static let modelKey = "openai_model"
    private static let triggerKey = "trigger"
    private static let excludedBundleIDsKey = "excluded_bundle_ids"

    public static var apiKey: String? {
        get {
            KeychainStore.read(account: apiKeyKey)
        }
        set {
            KeychainStore.write(newValue, account: apiKeyKey)
        }
    }

    public static var model: String {
        UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4.1-mini"
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

    public static var excludedBundleIDs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: excludedBundleIDsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: excludedBundleIDsKey)
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
}
