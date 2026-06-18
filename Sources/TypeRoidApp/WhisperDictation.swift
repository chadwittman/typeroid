import AVFoundation
import Foundation

enum WhisperDictationError: LocalizedError {
    case microphoneDenied
    case missingRuntime
    case missingModel
    case noSpeech
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off."
        case .missingRuntime:
            return "Local Whisper is not installed."
        case .missingModel:
            return "Local Whisper model is missing."
        case .noSpeech:
            return "No speech was detected."
        case .failed(let message):
            return message
        }
    }
}

final class WhisperDictation {
    static var runtimeURL: URL? {
        let paths = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp"
        ]
        return paths.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var modelURL: URL? {
        let candidates = [
            NSHomeDirectory() + "/.typeroid/models/ggml-tiny.en.bin",
            NSHomeDirectory() + "/.typeroid/models/ggml-base.en.bin",
            NSHomeDirectory() + "/.typeroid/models/ggml-small.en.bin"
        ]
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var isConfigured: Bool {
        runtimeURL != nil && modelURL != nil
    }

    func transcribe(maxDuration: TimeInterval = 14, silenceAfter: TimeInterval = 1.4) async throws -> String {
        guard await VoiceDictation.requestMicrophonePermission() else {
            throw WhisperDictationError.microphoneDenied
        }
        guard let runtimeURL = Self.runtimeURL else {
            throw WhisperDictationError.missingRuntime
        }
        guard let modelURL = Self.modelURL else {
            throw WhisperDictationError.missingModel
        }

        let recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typeroid-voice-\(UUID().uuidString).wav")
        let outputBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("typeroid-whisper-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            try? FileManager.default.removeItem(at: outputBaseURL.appendingPathExtension("txt"))
        }

        try await record(to: recordingURL, maxDuration: maxDuration, silenceAfter: silenceAfter)
        return try runWhisper(runtimeURL: runtimeURL, modelURL: modelURL, audioURL: recordingURL, outputBaseURL: outputBaseURL)
    }

    private func record(to url: URL, maxDuration: TimeInterval, silenceAfter: TimeInterval) async throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        defer {
            recorder.stop()
        }

        let started = Date()
        var lastVoiceTime = Date()
        var heardVoice = false

        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(120))
            recorder.updateMeters()
            if recorder.averagePower(forChannel: 0) > -42 {
                heardVoice = true
                lastVoiceTime = Date()
            }
            if Date().timeIntervalSince(started) >= maxDuration {
                break
            }
            if heardVoice && Date().timeIntervalSince(lastVoiceTime) >= silenceAfter {
                break
            }
        }

        guard heardVoice else {
            throw WhisperDictationError.noSpeech
        }
    }

    private func runWhisper(runtimeURL: URL, modelURL: URL, audioURL: URL, outputBaseURL: URL) throws -> String {
        let process = Process()
        process.executableURL = runtimeURL
        process.arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-otxt",
            "-of", outputBaseURL.path,
            "-nt",
            "-np"
        ]

        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()

        let outputURL = outputBaseURL.appendingPathExtension("txt")
        if process.terminationStatus == 0,
           let transcript = try? String(contentsOf: outputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !transcript.isEmpty {
            return transcript
        }

        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Whisper transcription failed."
        throw WhisperDictationError.failed(errorText)
    }
}
