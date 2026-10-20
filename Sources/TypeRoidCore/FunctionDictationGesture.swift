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
/// press, after that second tap is released, stops hands-free and pastes.
public struct FunctionDictationGesture: Sendable {
    public var holdStart: TimeInterval = 0.22
    public var tapCeiling: TimeInterval = 0.45
    public var doubleTapGap: TimeInterval = 0.45

    public enum Phase: Equatable, Sendable {
        case idle
        case pressed(at: TimeInterval)
        case pushToTalk(downAt: TimeInterval)
        case armingDoubleTap(upAt: TimeInterval, recording: Bool)
        /// The second tap is still down. Another down is the same press, not a stop.
        case handsFreeHeld(startedAt: TimeInterval)
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
            phase = .handsFreeHeld(startedAt: time)
            return recording ? [.promoteToHandsFree] : [.begin(.handsFree)]
        case .handsFree:
            phase = .idle
            return [.end]
        case .pressed, .pushToTalk, .handsFreeHeld:
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
        case .handsFreeHeld(let startedAt):
            phase = .handsFree(startedAt: startedAt)
            return []
        case .idle, .armingDoubleTap, .handsFree:
            return []
        }
    }

    /// An arrow key, page key, or F key arrived. Drop a press those keys just
    /// faked, including a hands-free that their taps just started.
    public mutating func voidRecentPress(at time: TimeInterval) -> [FunctionDictationAction] {
        switch phase {
        case .pressed, .armingDoubleTap, .handsFreeHeld:
            phase = .idle
            return [.discard]
        case .pushToTalk(let downAt) where time - downAt <= tapCeiling:
            phase = .idle
            return [.discard]
        case .handsFree(let startedAt) where time - startedAt <= doubleTapGap + tapCeiling:
            phase = .idle
            return [.discard]
        case .idle, .pushToTalk, .handsFree:
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
        case .handsFreeHeld:
            phase = .idle
            return [.discard]
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

/// macOS reports the globe key as down for more than the globe key.
/// `keyState(0x3F)` and `maskSecondaryFn` are both set by the arrow keys,
/// page keys, forward delete, and the F keys. Up was still starting the
/// microphone through that shared state. Only a key event whose code is
/// 0x3F is the globe key.
public enum FunctionFlag {
    public static let globeKeyCode: Int64 = 0x3F

    /// Keys that make the globe key's state and the function modifier look down.
    public static let nonGlobeFunctionKeyCodes: Set<Int64> = [
        0x72, 0x73, 0x74, 0x75, 0x77, 0x79,
        0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x67, 0x6D, 0x6F, 0x76, 0x78, 0x7A,
        0x7B, 0x7C, 0x7D, 0x7E,
    ]
}

public enum GlobeKeyDecision: Sendable, Equatable {
    case none
    case globeDown
    case globeUp
    case void
}

/// Decides whether a keyboard event is the globe key. The poll cannot start
/// a press: Up sets the same key state the poll used to trust.
public struct GlobeKeyFilter: Sendable {
    public static let settle: TimeInterval = 0.35

    private var blockUntil: TimeInterval = -.infinity
    private var down = false

    public init() {}

    public mutating func key(code: Int64, isDown: Bool, at time: TimeInterval) -> GlobeKeyDecision {
        if FunctionFlag.nonGlobeFunctionKeyCodes.contains(code) {
            blockUntil = time + Self.settle
            down = false
            return .void
        }
        guard code == FunctionFlag.globeKeyCode else { return .none }
        if time < blockUntil {
            down = false
            return .void
        }
        guard isDown != down else { return .none }
        down = isDown
        return isDown ? .globeDown : .globeUp
    }

    public mutating func poll(globeDown: Bool, otherFunctionKeyDown: Bool, at time: TimeInterval) -> GlobeKeyDecision {
        if otherFunctionKeyDown {
            blockUntil = time + Self.settle
            down = false
            return .void
        }
        if time < blockUntil {
            if down {
                down = false
                return .void
            }
            return .none
        }
        // A missed key-up can end a press the globe key already started.
        // This never begins one.
        if down && !globeDown {
            down = false
            return .globeUp
        }
        return .none
    }
}

/// One fn edge stream. The menu-bar app hears the key from a poll and from
/// the event tap, and the tap callback can arrive late. A late copy of an
/// earlier press must not count as the next tap.
public struct FunctionKeySignals: Sendable {
    private var down = false
    private var lastTime: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    public mutating func edge(down next: Bool, at time: TimeInterval) -> FunctionKeyEdge? {
        guard time > lastTime || (time == lastTime && next == down) else { return nil }
        if time > lastTime {
            lastTime = time
        }
        guard next != down else { return nil }
        down = next
        return next ? .down(time) : .up(time)
    }

    public func isStale(_ time: TimeInterval) -> Bool {
        time < lastTime
    }
}
