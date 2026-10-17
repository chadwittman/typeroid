import Foundation

public enum FunctionDictationMode: String, Sendable, Equatable {
    case pushToTalk
    case handsFree
}

public enum FunctionDictationAction: Sendable, Equatable {
    case begin(FunctionDictationMode)
    case promoteToHandsFree
    case end
    case discard
    case cancel
    case hintHold
}

/// Fn behavior modeled on Wispr Flow.
///
/// Hold fn to talk, then release to stop. A press shorter than `tapCeiling`
/// is a tap. Two taps inside `doubleTapGap` turn hands-free on. The next fn
/// press stops hands-free, and a third tap inside `cancelWindow` cancels.
public struct FunctionDictationGesture: Sendable {
    public var holdStart: TimeInterval = 0.22
    public var tapCeiling: TimeInterval = 0.45
    public var doubleTapGap: TimeInterval = 0.45
    public var cancelWindow: TimeInterval = 0.50

    public enum Phase: Equatable, Sendable {
        case idle
        case pressed(at: TimeInterval)
        case pushToTalk(downAt: TimeInterval)
        case armingDoubleTap(upAt: TimeInterval, recording: Bool)
        case handsFree(startedAt: TimeInterval)
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public mutating func reset() {
        phase = .idle
    }

    public mutating func fnDown(at time: TimeInterval) -> [FunctionDictationAction] {
        switch phase {
        case .idle:
            phase = .pressed(at: time)
            return []
        case .armingDoubleTap(_, let recording):
            phase = .handsFree(startedAt: time)
            return recording ? [.promoteToHandsFree] : [.begin(.handsFree)]
        case .handsFree(let startedAt):
            phase = .idle
            return time - startedAt < cancelWindow ? [.cancel] : [.end]
        case .pressed, .pushToTalk:
            return []
        }
    }

    public mutating func fnUp(at time: TimeInterval) -> [FunctionDictationAction] {
        switch phase {
        case .pressed(let downAt):
            if time - downAt <= tapCeiling {
                phase = .armingDoubleTap(upAt: time, recording: false)
                return []
            }
            phase = .idle
            return []
        case .pushToTalk(let downAt):
            if time - downAt <= tapCeiling {
                phase = .armingDoubleTap(upAt: time, recording: true)
                return []
            }
            phase = .idle
            return [.end]
        case .idle, .armingDoubleTap, .handsFree:
            return []
        }
    }

    /// A non-fn key arrived while fn was down. Chords such as fn+F1 must not dictate.
    public mutating func otherKey(at time: TimeInterval) -> [FunctionDictationAction] {
        switch phase {
        case .pressed:
            phase = .idle
            return []
        case .pushToTalk(let downAt):
            guard time - downAt <= tapCeiling else { return [] }
            phase = .idle
            return [.discard]
        case .armingDoubleTap(_, let recording):
            phase = .idle
            return recording ? [.discard] : []
        case .idle, .handsFree:
            return []
        }
    }

    public mutating func holdElapsed(at time: TimeInterval) -> [FunctionDictationAction] {
        guard case .pressed(let downAt) = phase else { return [] }
        guard time - downAt + 0.02 >= holdStart else { return [] }
        phase = .pushToTalk(downAt: downAt)
        return [.begin(.pushToTalk)]
    }

    public mutating func secondTapWindowElapsed(at time: TimeInterval) -> [FunctionDictationAction] {
        guard case .armingDoubleTap(let upAt, let recording) = phase else { return [] }
        guard time - upAt + 0.02 >= doubleTapGap else { return [] }
        phase = .idle
        return recording ? [.discard, .hintHold] : [.hintHold]
    }
}
