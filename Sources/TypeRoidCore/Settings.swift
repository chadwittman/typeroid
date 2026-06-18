import Foundation

public enum Settings {
    // Keys
    private static let providerKey = "ai_provider"
    private static let modelKey = "ai_model"
    private static let triggerKey = "trigger"
    private static let rewriteTriggerKey = "rewrite_trigger"
    private static let excludedBundleIDsKey = "excluded_bundle_ids"
    private static let userConfiguredExcludedBundleIDsKey = "user_configured_excluded_bundle_ids"
    private static let openMenuAfterRewriteKey = "open_menu_after_rewrite"
    private static let onboardingCompleteKey = "onboarding_complete"
    private static let onboardingStepKey = "onboarding_step"
    private static let languageKey = "language"
    private static let contextTriggerKey = "context_trigger"
    private static let translateTriggerKey = "translate_trigger"
    private static let translateTargetKey = "translate_target"
    private static let mathTriggerKey = "math_trigger"
    private static let rephraseTriggerKey = "rephrase_trigger"
    private static let voiceTriggerKey = "voice_trigger"

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

    // MARK: - Provider
    public static var provider: AIProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: providerKey),
               let p = AIProvider(rawValue: raw) {
                return p
            }
            return .openai
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerKey)
        }
    }

    // MARK: - API Keys (per provider)
    public static func apiKey(for provider: AIProvider) -> String? {
        KeychainStore.read(account: provider.keychainAccount)
    }

    public static func setAPIKey(_ key: String?, for provider: AIProvider) {
        KeychainStore.write(key, account: provider.keychainAccount)
    }

    // Convenience: current provider's key
    public static var apiKey: String? {
        get { apiKey(for: provider) }
        set { setAPIKey(newValue, for: provider) }
    }

    // MARK: - Model
    public static var model: String {
        get {
            UserDefaults.standard.string(forKey: modelKey) ?? provider.defaultModel
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelKey)
        }
    }

    // MARK: - Triggers
    public static var trigger: String {
        get {
            let value = UserDefaults.standard.string(forKey: triggerKey) ?? "//"
            return value.isEmpty ? "//" : value
        }
        set {
            UserDefaults.standard.set(newValue.isEmpty ? "//" : newValue, forKey: triggerKey)
        }
    }

    public static var rewriteTrigger: String {
        get {
            let value = UserDefaults.standard.string(forKey: rewriteTriggerKey) ?? "\\\\"
            return value.isEmpty ? "\\\\" : value
        }
        set {
            UserDefaults.standard.set(newValue.isEmpty ? "\\\\" : newValue, forKey: rewriteTriggerKey)
        }
    }

    public static var contextTrigger: String {
        get {
            let value = UserDefaults.standard.string(forKey: contextTriggerKey) ?? "??"
            return value.isEmpty ? "??" : value
        }
        set {
            UserDefaults.standard.set(newValue.isEmpty ? "??" : newValue, forKey: contextTriggerKey)
        }
    }

    public static var translateTrigger: String {
        get { UserDefaults.standard.string(forKey: translateTriggerKey) ?? ";;" }
        set { UserDefaults.standard.set(newValue.isEmpty ? ";;" : newValue, forKey: translateTriggerKey) }
    }

    public static var mathTrigger: String {
        get { UserDefaults.standard.string(forKey: mathTriggerKey) ?? "==" }
        set { UserDefaults.standard.set(newValue.isEmpty ? "==" : newValue, forKey: mathTriggerKey) }
    }

    public static var rephraseTrigger: String {
        get { UserDefaults.standard.string(forKey: rephraseTriggerKey) ?? "||" }
        set { UserDefaults.standard.set(newValue.isEmpty ? "||" : newValue, forKey: rephraseTriggerKey) }
    }

    public static var voiceTrigger: String {
        get {
            let value = UserDefaults.standard.string(forKey: voiceTriggerKey) ?? ",,"
            return value.isEmpty ? ",," : value
        }
        set {
            UserDefaults.standard.set(newValue.isEmpty ? ",," : newValue, forKey: voiceTriggerKey)
        }
    }

    public static var translateTarget: String {
        get {
            let v = UserDefaults.standard.string(forKey: translateTargetKey) ?? "Spanish"
            // Migrate legacy "Chinese" → "Chinese (Simplified)"
            return v == "Chinese" ? "Chinese (Simplified)" : v
        }
        set { UserDefaults.standard.set(newValue, forKey: translateTargetKey) }
    }

    // MARK: - Language
    public static let supportedLanguages = [
        "English", "Spanish", "French", "German", "Portuguese", "Italian",
        "Dutch", "Japanese", "Korean", "Chinese (Simplified)", "Chinese (Traditional)",
        "Arabic", "Hindi", "Russian", "Polish", "Turkish", "Swedish", "Norwegian", "Danish",
    ]

    public static var language: String {
        get { UserDefaults.standard.string(forKey: languageKey) ?? "English" }
        set { UserDefaults.standard.set(newValue, forKey: languageKey) }
    }

    public static var languageLocaleIdentifier: String {
        switch language {
        case "Spanish": return "es-US"
        case "French": return "fr-FR"
        case "German": return "de-DE"
        case "Portuguese": return "pt-BR"
        case "Italian": return "it-IT"
        case "Dutch": return "nl-NL"
        case "Japanese": return "ja-JP"
        case "Korean": return "ko-KR"
        case "Chinese (Simplified)": return "zh-Hans"
        case "Chinese (Traditional)": return "zh-Hant"
        case "Arabic": return "ar-SA"
        case "Hindi": return "hi-IN"
        case "Russian": return "ru-RU"
        case "Polish": return "pl-PL"
        case "Turkish": return "tr-TR"
        case "Swedish": return "sv-SE"
        case "Norwegian": return "nb-NO"
        case "Danish": return "da-DK"
        default: return "en-US"
        }
    }

    // MARK: - Translation Proof
    private static let backTranslateKey = "back_translate_enabled"

    public static var backTranslateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: backTranslateKey) }
        set { UserDefaults.standard.set(newValue, forKey: backTranslateKey) }
    }

    // MARK: - Writing Style
    private static let useStyleKey = "use_writing_style"
    private static let webSearchKey = "web_search_enabled"

    public static let currentVersion = "0.2.17"
    public static let updateCheckURL = "https://raw.githubusercontent.com/typeroid/typeroid/main/version.txt"

    public static var webSearchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: webSearchKey) }
        set { UserDefaults.standard.set(newValue, forKey: webSearchKey) }
    }

    public static var useWritingStyle: Bool {
        get { UserDefaults.standard.bool(forKey: useStyleKey) }
        set { UserDefaults.standard.set(newValue, forKey: useStyleKey) }
    }

    public static var stylePath: String {
        NSHomeDirectory() + "/.typeroid/style.md"
    }

    public static func loadStyle() -> String? {
        guard FileManager.default.fileExists(atPath: stylePath) else { return nil }
        guard let content = try? String(contentsOfFile: stylePath, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip if it's just the template comments
        if trimmed.hasPrefix("# My Writing Style") && trimmed.count < 200 { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Onboarding
    public static var onboardingComplete: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingCompleteKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingCompleteKey) }
    }

    public static var onboardingStep: Int {
        get { UserDefaults.standard.integer(forKey: onboardingStepKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingStepKey) }
    }

    // MARK: - Other Settings
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
        if isExcluded { ids.insert(bundleID) } else { ids.remove(bundleID) }
        excludedBundleIDs = ids
    }

    public static func resetExcludedBundleIDsToDefaults() {
        excludedBundleIDs = defaultExcludedBundleIDs
    }

    // MARK: - Ollama
    private static let cachedOllamaModelsKey = "cached_ollama_models"

    public static var cachedOllamaModels: [String] {
        get { UserDefaults.standard.stringArray(forKey: cachedOllamaModelsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: cachedOllamaModelsKey) }
    }
}
