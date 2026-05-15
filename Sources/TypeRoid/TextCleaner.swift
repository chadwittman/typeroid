import Foundation

enum TextCleanerError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI API key."
        case .invalidResponse:
            return "The API response could not be read."
        case .apiError(let message):
            return message
        }
    }
}

enum TextCleaner {
    static func clean(_ text: String) async throws -> String {
        guard let apiKey = Settings.apiKey, !apiKey.isEmpty else {
            throw TextCleanerError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ResponsesRequest(
            model: Settings.model,
            input: [
                ResponsesMessage(
                    role: "system",
                    content: [
                        ResponsesContent(
                            type: "input_text",
                            text: """
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
                        )
                    ]
                ),
                ResponsesMessage(
                    role: "user",
                    content: [
                        ResponsesContent(type: "input_text", text: text)
                    ]
                )
            ],
            temperature: 0.1
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "OpenAI API error"
            throw TextCleanerError.apiError(body)
        }

        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        if let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !outputText.isEmpty {
            return outputText
        }

        for item in decoded.output ?? [] {
            for content in item.content ?? [] {
                if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return text
                }
            }
        }

        throw TextCleanerError.invalidResponse
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: [ResponsesMessage]
    let temperature: Double
}

private struct ResponsesMessage: Encodable {
    let role: String
    let content: [ResponsesContent]
}

private struct ResponsesContent: Encodable {
    let type: String
    let text: String
}

private struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [ResponsesOutput]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct ResponsesOutput: Decodable {
    let content: [ResponsesOutputContent]?
}

private struct ResponsesOutputContent: Decodable {
    let text: String?
}
