import Foundation

enum Settings {
    private static let apiKeyKey = "openai_api_key"
    private static let modelKey = "openai_model"

    static var apiKey: String? {
        get {
            UserDefaults.standard.string(forKey: apiKeyKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
        }
    }

    static var model: String {
        UserDefaults.standard.string(forKey: modelKey) ?? "gpt-4.1-mini"
    }
}
