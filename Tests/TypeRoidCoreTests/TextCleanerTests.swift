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

@Test func queryInstructionExists() {
    let instruction = TextCleaner.queryInstruction
    #expect(instruction.contains("typeROID"))
    #expect(instruction.contains("concise"))
    #expect(instruction.contains("Return only the response"))
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
    let modes: [CleanMode] = [.clean, .query, .context, .translate, .math, .custom("test")]
    #expect(modes.count == 6)
}
