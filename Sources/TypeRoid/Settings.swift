import Foundation

enum Settings {
    private static let apiKeyKey = "openai_api_key"
    private static let modelKey = "openai_model"
    private static let triggerKey = "trigger"

    static var apiKey: String? {
        get {
            KeychainStore.read(account: apiKeyKey)
        }
        set {
            KeychainStore.write(newValue, account: apiKeyKey)
        }
    }

    static var model: String {
        UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4.1-mini"
    }

    static var trigger: String {
        get {
            let value = UserDefaults.standard.string(forKey: triggerKey) ?? "//"
            return value.isEmpty ? "//" : value
        }
        set {
            UserDefaults.standard.set(newValue.isEmpty ? "//" : newValue, forKey: triggerKey)
        }
    }
}
