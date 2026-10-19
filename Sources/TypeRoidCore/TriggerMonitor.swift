import AppKit
import Carbon
import Foundation

private struct TapOwner: @unchecked Sendable {
    let raw: UnsafeMutableRawPointer
    init(_ raw: UnsafeMutableRawPointer) { self.raw = raw }
}

public final class TriggerMonitor {
    private let onTrigger: (TypedTrigger) -> Void
    private let triggerProvider: () -> String           // //
    private let contextTriggerProvider: () -> String    // \\ (clipboard context)
    private let queryTriggerProvider: () -> String      // ?? (ask AI)
    private let translateTriggerProvider: () -> String  // ;; (translate)
    private let mathTriggerProvider: () -> String       // == (math)
    private let rephraseTriggerProvider: () -> String   // || (rephrase/de-corp)
    private let voiceTriggerProvider: () -> String      // ,, (voice brief)
    private let screenTriggerProvider: () -> String     // >> (prompt with screenshot)
    private let customCommandsProvider: () -> [String]  // available ..commands
    private let onFunctionKey: (FunctionKeyEdge) -> Void
    private let shouldSwallowGlobe: () -> Bool
    private let shouldSwallowEscape: () -> Bool
    private let onDebugEvent: (TriggerMonitorDebugEvent) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var recentCharacters = ""
    private var bufferTruncated = false
    private var functionIsDown = false
    private(set) public var isActive = false
    private(set) public var lastCharacters = ""
    private(set) public var keypressCount = 0

    private static let globeKeyCode: Int64 = 0x3F
    private static let escapeKeyCode: Int64 = 0x35

    public init(
        triggerProvider: @escaping () -> String,
        contextTriggerProvider: @escaping () -> String = { Settings.rewriteTrigger },
        queryTriggerProvider: @escaping () -> String = { Settings.contextTrigger },
        translateTriggerProvider: @escaping () -> String = { Settings.translateTrigger },
        mathTriggerProvider: @escaping () -> String = { Settings.mathTrigger },
        rephraseTriggerProvider: @escaping () -> String = { Settings.rephraseTrigger },
        voiceTriggerProvider: @escaping () -> String = { Settings.voiceTrigger },
        screenTriggerProvider: @escaping () -> String = { Settings.screenTrigger },
        customCommandsProvider: @escaping () -> [String] = { TextCleaner.availableCommands() },
        onFunctionKey: @escaping (FunctionKeyEdge) -> Void = { _ in },
        shouldSwallowGlobe: @escaping () -> Bool = { false },
        shouldSwallowEscape: @escaping () -> Bool = { false },
        onDebugEvent: @escaping (TriggerMonitorDebugEvent) -> Void = { _ in },
        onTrigger: @escaping (TypedTrigger) -> Void
    ) {
        self.triggerProvider = triggerProvider
        self.contextTriggerProvider = contextTriggerProvider
        self.queryTriggerProvider = queryTriggerProvider
        self.translateTriggerProvider = translateTriggerProvider
        self.mathTriggerProvider = mathTriggerProvider
        self.rephraseTriggerProvider = rephraseTriggerProvider
        self.voiceTriggerProvider = voiceTriggerProvider
        self.screenTriggerProvider = screenTriggerProvider
        self.customCommandsProvider = customCommandsProvider
        self.onFunctionKey = onFunctionKey
        self.shouldSwallowGlobe = shouldSwallowGlobe
        self.shouldSwallowEscape = shouldSwallowEscape
        self.onDebugEvent = onDebugEvent
        self.onTrigger = onTrigger
    }

    public func start() {
        guard tapThread == nil else { return }
        // The tap used to live on the main run loop. The onboarding shader and
        // the juice-bar timer stall that loop long enough for macOS to disable
        // the tap, and a later tapEnable does not bring the keys back. A
        // dedicated thread keeps // and fn listening while the UI is busy.
        let owner = TapOwner(Unmanaged.passUnretained(self).toOpaque())
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let monitor = Unmanaged<TriggerMonitor>.fromOpaque(owner.raw).takeUnretainedValue()
            monitor.installTap()
            ready.signal()
            if monitor.isActive {
                CFRunLoopRun()
            }
        }
        thread.name = "typeroid-keys"
        tapThread = thread
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
    }

    private func installTap() {
        tapRunLoop = CFRunLoopGetCurrent()
        let keyDown = 1 << CGEventType.keyDown.rawValue
        let keyUp = 1 << CGEventType.keyUp.rawValue
        let flagsChanged = 1 << CGEventType.flagsChanged.rawValue
        let tapTimeout = 1 << CGEventType.tapDisabledByTimeout.rawValue
        let tapUser = 1 << CGEventType.tapDisabledByUserInput.rawValue
        let mask = CGEventMask(keyDown | keyUp | flagsChanged | tapTimeout | tapUser)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TriggerMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handleTap(type: type, event: event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        // An active tap can swallow the globe key so macOS does not also open
        // emoji or Apple Dictation. Listen-only is the fallback when that tap
        // is not permitted; dictation still sees fn, but the key is not eaten.
        let placements: [(CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions)] = [
            (.cghidEventTap, .headInsertEventTap, .defaultTap),
            (.cgSessionEventTap, .headInsertEventTap, .defaultTap),
            (.cgSessionEventTap, .tailAppendEventTap, .listenOnly)
        ]
        for (tap, place, options) in placements {
            eventTap = CGEvent.tapCreate(
                tap: tap,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            )
            if eventTap != nil { break }
        }

        guard let eventTap else {
            isActive = false
            onDebugEvent(.tapCreationFailed)
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isActive = true
        onDebugEvent(.tapStarted)
    }

    deinit {
        if let tapRunLoop {
            CFRunLoopStop(tapRunLoop)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        isActive = false
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            onDebugEvent(.tapReenabled)
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            noteFunction(down: event.flags.contains(.maskSecondaryFn))
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown || type == .keyUp, keyCode == Self.globeKeyCode {
            noteFunction(down: type == .keyDown)
            return shouldSwallowGlobe() ? nil : Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        if keyCode == Self.escapeKeyCode, shouldSwallowEscape() {
            onFunctionKey(.escape)
            return nil
        }
        if functionIsDown {
            onFunctionKey(.otherKey(Self.monotonicNow()))
        }
        handle(event)
        return Unmanaged.passUnretained(event)
    }

    private func noteFunction(down: Bool) {
        guard down != functionIsDown else { return }
        functionIsDown = down
        let time = Self.monotonicNow()
        onFunctionKey(down ? .down(time) : .up(time))
    }

    private static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func handle(_ event: CGEvent) {
        guard !isCommandShortcut(event) else {
            recentCharacters.removeAll()
            return
        }

        let string = Self.typedString(from: event)
        guard !string.isEmpty else { return }
        handleTypedCharacters(string)
    }

    /// The tap sometimes delivers a key code and an empty unicode string.
    /// The two-character tools are punctuation, so recover those from the code.
    static func characterForKeyCode(_ keyCode: Int64, shifted: Bool) -> String? {
        switch keyCode {
        case 0x2C: return shifted ? "?" : "/"
        case 0x18: return shifted ? "+" : "="
        case 0x2B: return shifted ? "<" : ","
        case 0x29: return shifted ? ":" : ";"
        case 0x2A: return shifted ? "|" : "\\"
        case 0x2F: return shifted ? ">" : "."
        default: return nil
        }
    }

    private static func typedString(from event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        if length > 0 {
            return String(utf16CodeUnits: chars, count: length)
        }
        let flags = event.flags
        if flags.contains(.maskAlternate) || flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return ""
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return characterForKeyCode(keyCode, shifted: flags.contains(.maskShift)) ?? ""
    }

    func handleTypedCharacters(_ string: String) {
        let cleanTrigger = triggerProvider()
        let contextTrigger = contextTriggerProvider()     // \\
        let queryTrigger = queryTriggerProvider()         // ??
        let translateTrigger = translateTriggerProvider() // ;;
        let mathTrigger = mathTriggerProvider()           // ==
        let rephraseTrigger = rephraseTriggerProvider()   // ||
        let voiceTrigger = voiceTriggerProvider()         // ,,
        let screenTrigger = screenTriggerProvider()       // >>
        let customCommands = customCommandsProvider()
        let maxCustomLen = (customCommands.map { $0.count }.max() ?? 0) + 2  // +2 for ".."
        let maxLen = max(cleanTrigger.count, contextTrigger.count, queryTrigger.count, translateTrigger.count, mathTrigger.count, rephraseTrigger.count, voiceTrigger.count, screenTrigger.count, maxCustomLen, 1) + 256

        for character in string {
            if character.isNewline {
                recentCharacters.removeAll()
                bufferTruncated = false
            } else {
                recentCharacters.append(character)
                if recentCharacters.count > maxLen {
                    bufferTruncated = true
                    recentCharacters = String(recentCharacters.suffix(maxLen))
                }
            }
        }
        keypressCount += 1
        lastCharacters = String(repeating: ".", count: recentCharacters.count)
        onDebugEvent(.key("\(recentCharacters.count) buffered"))

        // Check screen trigger (>>) before custom commands so the built-in
        // visual context workflow is reserved.
        if recentCharacters.hasSuffix(screenTrigger) {
            fire(.screen, trigger: screenTrigger, debug: .triggerMatchedScreen)
            return
        }

        // Check custom commands - filename IS the trigger, longest first
        for cmd in customCommands.sorted(by: { $0.count > $1.count }) {
            if recentCharacters.hasSuffix(cmd) {
                fire(.custom(cmd), trigger: cmd, debug: .triggerMatchedContext)
                return
            }
        }

        // Check rephrase trigger (||)
        if recentCharacters.hasSuffix(rephraseTrigger) {
            fire(.rephrase, trigger: rephraseTrigger, debug: .triggerMatched)
            return
        }

        // Check math trigger (==)
        if recentCharacters.hasSuffix(mathTrigger) {
            fire(.math, trigger: mathTrigger, debug: .triggerMatchedTranslate)
            return
        }

        // Check translate trigger (;;)
        if recentCharacters.hasSuffix(translateTrigger) {
            fire(.translate, trigger: translateTrigger, debug: .triggerMatchedTranslate)
            return
        }

        // Check context trigger (\\) - read screen
        if recentCharacters.hasSuffix(contextTrigger) {
            fire(.context, trigger: contextTrigger, debug: .triggerMatchedContext)
            return
        }

        // Check query trigger (??) - ask AI
        if recentCharacters.hasSuffix(queryTrigger) {
            fire(.query, trigger: queryTrigger, debug: .triggerMatchedRewrite)
            return
        }

        // Check voice-only trigger (,,). This intentionally fires anywhere so
        // app composers with stale/inaccessible line state can still start voice.
        if recentCharacters.hasSuffix(voiceTrigger) {
            fire(.smartBrevity, trigger: voiceTrigger, debug: .triggerMatchedVoice)
            return
        }

        // Check clean trigger (//)
        if recentCharacters.hasSuffix(cleanTrigger) {
            guard shouldFireCleanTrigger(cleanTrigger) else { return }
            fire(.clean, trigger: cleanTrigger, debug: .triggerMatched)
        }
    }

    private func fire(_ mode: CleanMode, trigger: String, debug: TriggerMonitorDebugEvent) {
        let before: String
        if recentCharacters.hasSuffix(trigger) {
            before = String(recentCharacters.dropLast(trigger.count))
        } else {
            before = recentCharacters
        }
        let match = TypedTrigger(
            mode: mode,
            textBefore: before.trimmingCharacters(in: .whitespacesAndNewlines),
            deleteCount: recentCharacters.count,
            bufferTruncated: bufferTruncated
        )
        recentCharacters.removeAll()
        lastCharacters = ""
        bufferTruncated = false
        onDebugEvent(debug)
        onTrigger(match)
    }

    private func shouldFireCleanTrigger(_ trigger: String) -> Bool {
        guard trigger == "//" else { return true }
        let beforeTrigger = recentCharacters.dropLast(trigger.count)
        return beforeTrigger.last != ":"
    }

    private func isCommandShortcut(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return flags.contains(.maskCommand) || flags.contains(.maskControl)
    }
}

public struct TypedTrigger: Sendable, Equatable {
    public let mode: CleanMode
    public let textBefore: String
    /// Characters just typed, including the trigger. Safe to backspace when
    /// the buffer was not truncated.
    public let deleteCount: Int
    public let bufferTruncated: Bool
}

public enum FunctionKeyEdge: Sendable {
    case down(TimeInterval)
    case up(TimeInterval)
    case otherKey(TimeInterval)
    case escape
}

public enum TriggerMonitorDebugEvent: Sendable {
    case tapStarted
    case tapCreationFailed
    case tapReenabled
    case key(String)
    case triggerMatched
    case triggerMatchedRewrite
    case triggerMatchedContext
    case triggerMatchedTranslate
    case triggerMatchedVoice
    case triggerMatchedScreen
}
