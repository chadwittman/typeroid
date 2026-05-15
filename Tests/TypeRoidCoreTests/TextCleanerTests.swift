import Foundation
import Testing
@testable import TypeRoidCore

@Test func requestBodyPreservesTypeRoidContract() throws {
    let input = "hey john i saw the thing come through looks good but can we move meeting to tmrw im slammed today"
    let body = try TextCleaner.makeRequestBody(text: input, model: "test-model")
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(json["model"] as? String == "test-model")
    #expect(json["temperature"] as? Double == 0.1)

    let messages = try #require(json["input"] as? [[String: Any]])
    #expect(messages.count == 2)

    let systemContent = try #require(messages[0]["content"] as? [[String: Any]])
    let systemText = try #require(systemContent[0]["text"] as? String)

    #expect(systemText.contains("Fix spelling, grammar, punctuation, and capitalization."))
    #expect(systemText.contains("Preserve the writer's voice"))
    #expect(systemText.contains("Do not add ideas."))
    #expect(systemText.contains("Do not add jargon."))
    #expect(systemText.contains("Do not make it corporate."))
    #expect(systemText.contains("Do not make it sound like AI."))
    #expect(systemText.contains("Do not over-polish."))
    #expect(systemText.contains("Return only the corrected text."))

    let userContent = try #require(messages[1]["content"] as? [[String: Any]])
    #expect(userContent[0]["text"] as? String == input)
}

@Test func parsesOutputTextResponse() throws {
    let data = #"{"output_text":" Hey John, can we move the meeting to tomorrow? "}"#.data(using: .utf8)!
    let parsed = try TextCleaner.parseResponse(data)
    #expect(parsed == "Hey John, can we move the meeting to tomorrow?")
}

@Test func parsesNestedResponsesOutput() throws {
    let data = """
    {
      "output": [
        {
          "content": [
            {
              "type": "output_text",
              "text": "Hey John, I saw the thing come through."
            }
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    let parsed = try TextCleaner.parseResponse(data)
    #expect(parsed == "Hey John, I saw the thing come through.")
}

@Test func rejectsEmptyResponses() throws {
    let data = #"{"output_text":"   "}"#.data(using: .utf8)!
    #expect(throws: TextCleanerError.invalidResponse) {
        _ = try TextCleaner.parseResponse(data)
    }
}
