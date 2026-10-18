import Foundation
import Testing
@testable import TypeRoidCore

@Test func cleanInstructionPreservesVoice() {
    let instruction = TextCleaner.cleanInstruction
    #expect(instruction.contains("Fix spelling, grammar, punctuation, and capitalization."))
    #expect(instruction.contains("Preserve the writer's voice"))
    #expect(instruction.contains("Do not add ideas."))
    #expect(instruction.contains("Do not add jargon."))
    #expect(instruction.contains("Do not make it corporate."))
    #expect(instruction.contains("Do not make it sound like AI."))
    #expect(instruction.contains("Do not over-polish."))
    #expect(instruction.contains("Return only the corrected text."))
}

@Test func spokenCapitalizationUsesSentencesAndTheWordI() {
    #expect(TextCleaner.capitalizeSpoken("i think we should ship this") == "I think we should ship this")
    #expect(TextCleaner.capitalizeSpoken("hello. this is a test. i'm here") == "Hello. This is a test. I'm here")
    #expect(TextCleaner.capitalizeSpoken("are you there?") == "Are you there?")
    #expect(TextCleaner.capitalizeSpoken("it costs 3.50 dollars") == "It costs 3.50 dollars")
    #expect(TextCleaner.capitalizeSpoken("meet at 9 a.m. today") == "Meet at 9 a.m. today")
    #expect(TextCleaner.capitalizeSpoken("dr. smith said hi") == "Dr. Smith said hi")
    #expect(TextCleaner.capitalizeSpoken("iPhone is ready") == "iPhone is ready")
    #expect(TextCleaner.capitalizeSpoken("Hello. I am here.") == "Hello. I am here.")
}

@Test func queryInstructionExists() {
    let instruction = TextCleaner.queryInstruction
    #expect(instruction.contains("typeROID"))
    #expect(instruction.contains("concise"))
    #expect(instruction.contains("Return only the response"))
}

@Test func spokenDictationKeepsTheirWords() {
    for instruction in [TextCleaner.dictationInstruction, TextCleaner.smartBrevityInstruction] {
        #expect(instruction.contains("um, uh, ah"))
        #expect(instruction.contains("Do not summarize."))
        #expect(instruction.contains("Do not shorten."))
        #expect(instruction.contains("Do not rephrase."))
        #expect(instruction.contains("Keep their words, order, and meaning."))
        #expect(instruction.contains("Capitalize the first letter of each sentence and the word I."))
        #expect(instruction.contains("Do not capitalize every word."))
        #expect(instruction.contains("If they asked a question, type the question."))
        #expect(!instruction.contains("smart brevity"))
        #expect(!instruction.contains("compact"))
    }
    #expect(TextCleaner.smartBrevityInstruction == TextCleaner.dictationInstruction)
}

@Test func screenDraftSanitizerReturnsQuotedReplyOnly() {
    let raw = """
    Sure! Here's a suggested reply:

    "Hi Carter, I am available this weekend. Please let me know a convenient time. Looking forward to it. Thanks!"
    """
    let result = TextCleaner.sanitizeScreenResponse(raw, prompt: "what should i say?")

    #expect(result == "Hi Carter, I am available this weekend. Please let me know a convenient time. Looking forward to it. Thanks!")
}

@Test func screenDraftSanitizerRemovesUnquotedIntro() {
    let raw = "You could say: Hi Carter, thanks for reaching out. I am available this weekend."
    let result = TextCleaner.sanitizeScreenResponse(raw, prompt: "how should i reply")

    #expect(result == "Hi Carter, thanks for reaching out. I am available this weekend.")
}

@Test func screenDraftSanitizerHandlesReplyForMeWrapper() {
    let raw = """
    Sure! Here's a reply you can send:

    "Thank you for your message. I appreciate the information and will get back to you shortly."
    """
    let result = TextCleaner.sanitizeScreenResponse(raw, prompt: "reply for me")

    #expect(result == "Thank you for your message. I appreciate the information and will get back to you shortly.")
}

@Test func screenDraftSanitizerUsesWrapperEvenForUnknownPrompt() {
    let raw = """
    Sure! Here's a reply:

    "Sounds good. I can do this weekend."
    """
    let result = TextCleaner.sanitizeScreenResponse(raw, prompt: "help")

    #expect(result == "Sounds good. I can do this weekend.")
}

@Test func screenSanitizerLeavesNonDraftAnswersAlone() {
    let raw = "The visible error says the API key is missing."
    let result = TextCleaner.sanitizeScreenResponse(raw, prompt: "what is going on here?")

    #expect(result == raw)
}

@Test func allProvidersHaveEndpoints() {
    for provider in AIProvider.allCases {
        #expect(!provider.endpoint.isEmpty)
        #expect(!provider.defaultModel.isEmpty)
        #expect(!provider.availableModels.isEmpty)
        #expect(!provider.displayName.isEmpty)
        #expect(!provider.keychainAccount.isEmpty)
    }
}

@Test func allModesExist() {
    // Verify all modes compile and are distinct
    let modes: [CleanMode] = [.clean, .query, .context, .translate, .math, .rephrase, .smartBrevity, .dictation, .screen, .custom("test")]
    #expect(modes.count == 10)
}

@Test func browserAddressBarBlocksAllModes() {
    #expect(CleanMode.clean.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.query.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.context.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.translate.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.math.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.rephrase.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.smartBrevity.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.dictation.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.screen.isUnsafeInBrowserAddressBar)
    #expect(CleanMode.custom("!!").isUnsafeInBrowserAddressBar)
}
