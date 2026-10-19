import AVFoundation
import Foundation
import Speech
import TypeRoidCore

enum VoiceDictationError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off."
        case .speechDenied:
            return "Speech recognition access is off."
        case .recognizerUnavailable:
            return "Turn on Dictation in macOS Keyboard settings, then try again."
        case .noSpeech:
            return "No speech was detected."
        }
    }
}

final class VoiceDictation: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var lastVoiceTime = Date()
    private var bestTranscript = ""
    private var recognitionError: Error?
    private var recognitionFinished = false

    func transcribe(
        maxDuration: TimeInterval = 180,
        silenceAfter: TimeInterval = 2.2,
        control: DictationControl? = nil,
        onRecordingFinished: (@MainActor () -> Void)? = nil
    ) async throws -> String {
        try await Self.requestPermissions()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Settings.languageLocaleIdentifier)),
              recognizer.isAvailable else {
            throw VoiceDictationError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        bestTranscript = ""
        recognitionError = nil
        recognitionFinished = false
        lastVoiceTime = Date()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if Self.containsVoice(buffer) {
                self.lastVoiceTime = Date()
            }
            for level in Self.waveLevels(buffer) {
                MicWave.shared.push(linear: level)
            }
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        defer { stop() }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] (result: SFSpeechRecognitionResult?, error: Error?) in
            if let result {
                self?.bestTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self?.recognitionFinished = true
                }
            }
            if let error {
                self?.recognitionError = error
                self?.recognitionFinished = true
            }
        }

        let started = Date()
        let poll: Duration = control == nil ? .milliseconds(200) : .milliseconds(60)
        while !Task.isCancelled {
            try await Task.sleep(for: poll)
            if control?.isCancelRequested == true {
                throw CancellationError()
            }
            if let recognitionError {
                throw recognitionError
            }

            let trimmed = bestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if control?.isStopRequested == true {
                return try await finishStoppedRecognition(onRecordingFinished: onRecordingFinished)
            }
            if recognitionFinished {
                guard !trimmed.isEmpty else { throw VoiceDictationError.noSpeech }
                await onRecordingFinished?()
                return trimmed
            }
            if Date().timeIntervalSince(started) >= maxDuration {
                guard !trimmed.isEmpty else { throw VoiceDictationError.noSpeech }
                await onRecordingFinished?()
                return trimmed
            }
            if !trimmed.isEmpty && Date().timeIntervalSince(lastVoiceTime) >= silenceAfter {
                await onRecordingFinished?()
                return trimmed
            }
        }

        throw CancellationError()
    }

    private func finishStoppedRecognition(
        onRecordingFinished: (@MainActor () -> Void)?
    ) async throws -> String {
        recognitionRequest?.endAudio()
        let deadline = Date().addingTimeInterval(0.7)
        while bestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Date() < deadline {
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(50))
        }
        let trimmed = bestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceDictationError.noSpeech }
        await onRecordingFinished?()
        return trimmed
    }

    private func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var speechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var voicePermissionsAuthorized: Bool {
        microphoneAuthorized && speechAuthorized
    }

    static var systemDictationEnabled: Bool {
        UserDefaults(suiteName: "com.apple.speech.recognition.AppleSpeechRecognition.prefs")?
            .bool(forKey: "DictationIMMasterDictationEnabled") == true
    }

    static var voiceReady: Bool {
        voicePermissionsAuthorized && systemDictationEnabled
    }

    static func requestPermissions() async throws {
        let microphoneAllowed = await requestMicrophonePermission()
        guard microphoneAllowed else { throw VoiceDictationError.microphoneDenied }

        let speechStatus = await requestSpeechPermission()
        guard speechStatus == .authorized else { throw VoiceDictationError.speechDenied }
    }

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    static func requestSpeechPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func containsVoice(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return false }

        var sum: Float = 0
        for frame in 0..<frameLength {
            let sample = channelData[frame]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        return rms > 0.015
    }

    /// A few peaks from one buffer, so the pill wave has a shape inside each chunk.
    private static func waveLevels(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let buckets = 3
        let size = max(1, frames / buckets)
        var levels: [Float] = []
        levels.reserveCapacity(buckets)
        for bucket in 0..<buckets {
            let start = bucket * size
            let end = min(frames, start + size)
            var peak: Float = 0
            var index = start
            while index < end {
                peak = max(peak, abs(channel[index]))
                index += 4
            }
            levels.append(peak)
        }
        return levels
    }
}

/// Shared stop/cancel flag for hold-to-talk and hands-free recording.
final class DictationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopRequested = false
    private var cancelRequested = false

    func stop() {
        lock.lock()
        stopRequested = true
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        stopRequested = true
        cancelRequested = true
        lock.unlock()
    }

    var isStopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    var isCancelRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }
}
