import Foundation

public enum TextCleanerError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case unsupportedProvider

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key set for the selected provider."
        case .invalidResponse: return "The API response could not be read."
        case .apiError(let msg): return msg
        case .unsupportedProvider: return "Unsupported AI provider."
        }
    }
}

public enum CleanMode: Sendable, Equatable {
    case clean      // // fix grammar, spelling, punctuation
    case query      // ?? ask AI, get a response inline
    case context    // \\ use clipboard as context, draft a response
    case translate  // ;; translate to target language
    case math       // == calculate or convert
    case rephrase   // || rewrite canned/corporate text in your own voice
    case smartBrevity // // at empty cursor: spoken draft to concise written text
    case custom(String) // ..commandname, user-defined commands

    public var isUnsafeInBrowserAddressBar: Bool {
        true
    }
}

public enum AIProvider: String, CaseIterable, Sendable {
    case openai = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case groq = "groq"
    case ollama = "ollama"

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .google: return "Google (Gemini)"
        case .groq: return "Groq"
        case .ollama: return "Ollama (local)"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4.1-nano"
        case .anthropic: return "claude-haiku-4-5-20251001"
        case .google: return "gemini-2.0-flash"
        case .groq: return "llama-3.1-8b-instant"
        case .ollama: return "llama3:latest"
        }
    }

    public var endpoint: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/responses"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .google: return "https://generativelanguage.googleapis.com/v1beta/models"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        }
    }

    public var keychainAccount: String {
        return "\(rawValue)_api_key"
    }

    public var keyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .google: return "AIza..."
        case .groq: return "gsk_..."
        case .ollama: return "(no key needed)"
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        default: return true
        }
    }

    /// cheapest model options for each provider
    public var availableModels: [String] {
        switch self {
        case .openai: return ["gpt-4.1-nano", "gpt-4.1-mini", "gpt-4o-mini"]
        case .anthropic: return ["claude-haiku-4-5-20251001", "claude-sonnet-4-5-20250514"]
        case .google: return ["gemini-2.0-flash", "gemini-2.0-flash-lite"]
        case .groq: return ["llama-3.1-8b-instant", "llama-3.3-70b-versatile"]
        case .ollama: return Settings.cachedOllamaModels.isEmpty ? ["llama3:latest"] : Settings.cachedOllamaModels
        }
    }

    /// Fast model used for ?? queries — separate from the text-cleaning model.
    /// Needs to handle factual questions well and support web search where applicable.
    public var queryModel: String {
        switch self {
        case .openai: return "gpt-4.1-mini"      // nano doesn't reliably support web_search_preview
        case .anthropic: return "claude-haiku-4-5-20251001"  // already the fastest
        case .google: return "gemini-2.0-flash"   // fast + built-in search
        case .groq: return "llama-3.3-70b-versatile"  // much better factual recall than 8b
        case .ollama: return Settings.model        // use whatever model the user picked
        }
    }
}

public enum TextCleaner {
    static let cleanInstruction = """
    You are TypeRoid, a restrained cleanup tool.

    Fix spelling, grammar, punctuation, and capitalization.
    Preserve the writer's voice, wording, bluntness, and intent as much as possible.
    Do not add ideas.
    Do not add jargon.
    Do not make it corporate.
    Do not make it sound like AI.
    Do not over-polish.
    Keep contractions and natural phrasing.
    If the original is blunt, keep it blunt, just readable.
    Return only the corrected text.
    """

    static let queryInstruction = """
    You are typeROID, an AI assistant embedded in whatever app the user is typing in.

    The user typed a question or request directly into a text field and wants a response.
    Your answer will replace what they typed, inline.

    Be concise and direct. Answer in plain text.
    No markdown. No bullet points. No headers.
    Write like a knowledgeable human texting back.
    If they asked a question, just answer it.
    If they gave an instruction, do what they asked.
    Keep it short unless the question requires detail.
    Return only the response.
    """

    static let contextInstruction = """
    You are typeROID in context mode. The user copied text (a thread, email, document) to their clipboard and wants help.

    Return ONLY valid JSON — no markdown, no code fences, nothing else:
    {
      "summary": "One or two sentences max. What's happening and the bottom line.",
      "reply": "A ready-to-send draft reply. Match the tone. Keep it tight."
    }
    """

    static let mathInstruction = """
    You are typeROID in math mode.

    The user typed a math expression, unit conversion, or calculation.
    Compute the answer and return ONLY the result.
    For simple math: just the number.
    For conversions: the converted value with unit.
    For percentages: the computed value.
    No explanation. No steps. Just the answer.
    Examples: "15% of 340" -> "51", "5ft 11in in cm" -> "180.3 cm", "234 * 17" -> "3,978"
    """

    public static func processWithContext(_ request: String, threadContext: String, mode: CleanMode = .context) async throws -> String {
        let provider = Settings.provider
        let apiKey = Settings.apiKey(for: provider)
        if provider.requiresAPIKey {
            guard let apiKey, !apiKey.isEmpty else {
                throw TextCleanerError.missingAPIKey
            }
        }

        // Sensitive data check on thread context
        if SensitiveFilter.containsSensitiveData(threadContext) || SensitiveFilter.containsSensitiveData(request) {
            throw TextCleanerError.apiError("Blocked: sensitive data detected. typeROID won't send this to any API.")
        }

        var fullInstruction = contextInstruction
        fullInstruction += "\nRespond in \(Settings.language)."
        if Settings.useWritingStyle, let style = Settings.loadStyle() {
            fullInstruction += "\n\nThe user's writing style for reference:\n\(style)"
        }
        let fullPrompt = """
        THREAD CONTEXT:
        \(threadContext)

        USER REQUEST:
        \(request.isEmpty ? "Summarize this thread and suggest a response." : request)
        """

        let model = Settings.model
        switch provider {
        case .openai: return try await callOpenAI(text: fullPrompt, instruction: fullInstruction, model: model, apiKey: apiKey ?? "")
        case .anthropic: return try await callAnthropic(text: fullPrompt, instruction: fullInstruction, model: model, apiKey: apiKey ?? "")
        case .google: return try await callGoogle(text: fullPrompt, instruction: fullInstruction, model: model, apiKey: apiKey ?? "")
        case .groq: return try await callGroq(text: fullPrompt, instruction: fullInstruction, model: model, apiKey: apiKey ?? "")
        case .ollama: return try await callOllama(text: fullPrompt, instruction: fullInstruction, model: model)
        }
    }

    static let rephraseInstruction = """
    You are typeROID in rephrase mode.

    The user pasted text that sounds canned, corporate, or generic and wants it rewritten.
    Same meaning. Different delivery. Sound like a real person said it.
    Kill the buzzwords. Kill the filler. Kill the passive voice.
    Keep it direct, confident, and appropriately casual.
    Do not add ideas or change the meaning.
    Return only the rewritten text.
    """

    static let smartBrevityInstruction = """
    You are typeROID in voice brief mode.

    The user dictated a rough spoken statement, note, or request.
    Your job is to compact the user's original message into smart brevity.
    Do not answer the user.
    Do not respond to the content.
    Do not solve requests or explain anything.
    If the transcript contains a question, preserve it as a concise question.
    If the transcript contains an instruction, preserve it as a concise instruction.
    Keep the user's intent, point of view, and audience.
    Remove filler, false starts, throat-clearing, repetition, and hedging.
    Make the message concise, clear, and useful.
    Prefer short paragraphs or bullets only when bullets make the message easier to scan.
    Do not add facts, claims, or ideas.
    Do not make it sound corporate.
    Return only the compacted message.
    """

    static let translateInstruction = """
    You are typeROID in translate mode.

    The user typed in one language and wants it translated.
    Translate naturally. Not word-for-word. Sound like a native speaker.
    Preserve the tone (casual, formal, etc.)
    Return only the translated text.
    """

    /// Load a custom command's system prompt from ~/.typeroid/commands/
    public static func loadCustomCommand(_ name: String) -> String? {
        let path = NSHomeDirectory() + "/.typeroid/commands/\(name).txt"
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// List all available custom command names (only 2-character symbol triggers)
    public static func availableCommands() -> [String] {
        let dir = NSHomeDirectory() + "/.typeroid/commands"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files
            .filter { $0.hasSuffix(".txt") }
            .map { String($0.dropLast(4)) }
            .filter { $0.count == 2 } // only two-symbol triggers
            .sorted()
    }

    public static func process(_ text: String, mode: CleanMode = .clean, translateTarget: String? = nil) async throws -> String {
        let provider = Settings.provider
        let apiKey = Settings.apiKey(for: provider)
        if provider.requiresAPIKey {
            guard let apiKey, !apiKey.isEmpty else {
                throw TextCleanerError.missingAPIKey
            }
        }

        let targetLang = translateTarget ?? Settings.translateTarget

        let instruction: String
        switch mode {
        case .clean:
            instruction = cleanInstruction
        case .query:
            instruction = queryInstruction
        case .context:
            instruction = contextInstruction
        case .translate:
            instruction = translateInstruction + "\nTranslate to \(targetLang)."
        case .math:
            instruction = mathInstruction
        case .rephrase:
            instruction = rephraseInstruction
        case .smartBrevity:
            instruction = smartBrevityInstruction
        case .custom(let name):
            guard let customPrompt = loadCustomCommand(name) else {
                throw TextCleanerError.apiError("No command for '\(name)'. Create ~/.typeroid/commands/\(name).txt with your prompt.")
            }
            instruction = customPrompt + "\nReturn only the result. No explanation."
        }

        // Sensitive data check
        if SensitiveFilter.containsSensitiveData(text) {
            throw TextCleanerError.apiError("Blocked: sensitive data detected (SSN, credit card, password, or API key). typeROID won't send this to any API.")
        }

        var fullInstruction = instruction
        // Pin response language for all non-translate modes so the AI doesn't mirror locale
        if mode != .translate {
            fullInstruction += "\nRespond in \(Settings.language)."
        }
        if Settings.useWritingStyle, let style = Settings.loadStyle() {
            fullInstruction += "\n\nThe user's writing style for reference:\n\(style)"
        }

        // ?? uses its own fast model; all other modes use the user-configured model
        let model = (mode == .query) ? provider.queryModel : Settings.model
        let useWebSearch = (mode == .query) && Settings.webSearchEnabled
            && (provider == .openai || provider == .google)
        let timeout: TimeInterval = (provider == .ollama) ? 120 : (mode == .query) ? 12 : 30

        switch provider {
        case .openai:
            return try await callOpenAI(text: text, instruction: fullInstruction, model: model, apiKey: apiKey ?? "", webSearch: useWebSearch, timeout: timeout)
        case .anthropic:
            return try await callAnthropic(text: text, instruction: fullInstruction, model: model, apiKey: apiKey ?? "", timeout: timeout)
        case .google:
            return try await callGoogle(text: text, instruction: fullInstruction, model: model, apiKey: apiKey ?? "", webSearch: useWebSearch, timeout: timeout)
        case .groq:
            return try await callGroq(text: text, instruction: fullInstruction, model: model, apiKey: apiKey ?? "", timeout: timeout)
        case .ollama:
            return try await callOllama(text: text, instruction: fullInstruction, model: model, timeout: timeout)
        }
    }

    // Keep backward compat
    public static func clean(_ text: String) async throws -> String {
        try await process(text, mode: .clean)
    }

    // MARK: - OpenAI (Responses API)
    private static func callOpenAI(text: String, instruction: String, model: String, apiKey: String, webSearch: Bool = false, timeout: TimeInterval = requestTimeout) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "input": [
                ["role": "system", "content": [["type": "input_text", "text": instruction]]],
                ["role": "user", "content": [["type": "input_text", "text": text]]]
            ]
        ]
        if webSearch {
            body["tools"] = [["type": "web_search_preview"]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let outputText = json?["output_text"] as? String, !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let output = json?["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for c in content {
                        if let t = c["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return t.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
            }
        }
        throw TextCleanerError.invalidResponse
    }

    // MARK: - Anthropic (Messages API)
    private static func callAnthropic(text: String, instruction: String, model: String, apiKey: String, timeout: TimeInterval = requestTimeout) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": instruction,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let content = json?["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TextCleanerError.invalidResponse
    }

    // MARK: - Google (Gemini)
    private static func callGoogle(text: String, instruction: String, model: String, apiKey: String, webSearch: Bool = false, timeout: TimeInterval = requestTimeout) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": instruction]]],
            "contents": [["parts": [["text": text]]]],
            "generationConfig": ["temperature": 0.1]
        ]
        if webSearch {
            body["tools"] = [["google_search": [:]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let candidates = json?["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let part = parts.first,
           let text = part["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TextCleanerError.invalidResponse
    }

    // MARK: - Groq (OpenAI-compatible Chat API)
    private static func callGroq(text: String, instruction: String, model: String, apiKey: String, timeout: TimeInterval = requestTimeout) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let choices = json?["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let text = message["content"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TextCleanerError.invalidResponse
    }

    // MARK: - Ollama (local, OpenAI-compatible)
    private static func callOllama(text: String, instruction: String, model: String, timeout: TimeInterval = 120) async throws -> String {
        var request = URLRequest(url: URL(string: "http://localhost:11434/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "stream": false,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw TextCleanerError.apiError("Ollama returned error \(http.statusCode). Is the model downloaded? Run: ollama pull \(model)")
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let choices = json?["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let text = message["content"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            throw TextCleanerError.invalidResponse
        } catch let error as TextCleanerError {
            throw error
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw TextCleanerError.apiError("Ollama timed out. The model may still be loading — try again in a moment.")
            }
            throw TextCleanerError.apiError("Ollama isn't running. Start it with: ollama serve")
        }
    }

    /// Fetch available model names from the local Ollama server.
    public static func fetchOllamaModels() async -> [String] {
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// Returns true if Ollama is reachable.
    public static func isOllamaRunning() async -> Bool {
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        request.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    // MARK: - Helpers
    private static let requestTimeout: TimeInterval = 30

    private static func configureRequest(_ request: inout URLRequest) {
        request.timeoutInterval = requestTimeout
    }

    private static func checkHTTPStatus(_ response: URLResponse, data: Data) throws {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            // Sanitize: don't expose full API response body to user
            let code = http.statusCode
            let hint: String
            switch code {
            case 401: hint = "Invalid API key. Check your key in Settings."
            case 403: hint = "Access denied. Your key may not have the right permissions."
            case 429: hint = "Rate limited. Wait a moment and try again."
            case 500...599: hint = "Provider is having issues. Try again shortly."
            default: hint = "Request failed (status \(code))."
            }
            throw TextCleanerError.apiError(hint)
        }
    }
}
