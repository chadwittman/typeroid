import AppKit
import Carbon
import Foundation

public final class TriggerMonitor {
    private let onTrigger: (CleanMode) -> Void
    private let triggerProvider: () -> String           // //
    private let contextTriggerProvider: () -> String    // \\ (clipboard context)
    private let queryTriggerProvider: () -> String      // ?? (ask AI)
    private let translateTriggerProvider: () -> String  // ;; (translate)
    private let mathTriggerProvider: () -> String       // == (math)
    private let rephraseTriggerProvider: () -> String   // || (rephrase/de-corp)
    private let voiceTriggerProvider: () -> String      // ,, (voice brief)
    private let customCommandsProvider: () -> [String]  // available ..commands
    private let onDebugEvent: (TriggerMonitorDebugEvent) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recentCharacters = ""
    private(set) public var isActive = false
    private(set) public var lastCharacters = ""
    private(set) public var keypressCount = 0

    public init(
        triggerProvider: @escaping () -> String,
        contextTriggerProvider: @escaping () -> String = { Settings.rewriteTrigger },
        queryTriggerProvider: @escaping () -> String = { Settings.contextTrigger },
        translateTriggerProvider: @escaping () -> String = { Settings.translateTrigger },
        mathTriggerProvider: @escaping () -> String = { Settings.mathTrigger },
        rephraseTriggerProvider: @escaping () -> String = { Settings.rephraseTrigger },
        voiceTriggerProvider: @escaping () -> String = { Settings.voiceTrigger },
        customCommandsProvider: @escaping () -> [String] = { TextCleaner.availableCommands() },
        onDebugEvent: @escaping (TriggerMonitorDebugEvent) -> Void = { _ in },
        onTrigger: @escaping (CleanMode) -> Void
    ) {
        self.triggerProvider = triggerProvider
        self.contextTriggerProvider = contextTriggerProvider
        self.queryTriggerProvider = queryTriggerProvider
        self.translateTriggerProvider = translateTriggerProvider
        self.mathTriggerProvider = mathTriggerProvider
        self.rephraseTriggerProvider = rephraseTriggerProvider
        self.voiceTriggerProvider = voiceTriggerProvider
        self.customCommandsProvider = customCommandsProvider
        self.onDebugEvent = onDebugEvent
        self.onTrigger = onTrigger
    }

    public func start() {
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TriggerMonitor>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap = monitor.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                monitor.onDebugEvent(.tapReenabled)
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            monitor.handle(event)
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            isActive = false
            onDebugEvent(.tapCreationFailed)
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isActive = true
        onDebugEvent(.tapStarted)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        isActive = false
    }

    private func handle(_ event: CGEvent) {
        guard !isCommandShortcut(event) else {
            recentCharacters.removeAll()
            return
        }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return }

        let string = String(utf16CodeUnits: chars, count: length)
        handleTypedCharacters(string)
    }

    func handleTypedCharacters(_ string: String) {
        let cleanTrigger = triggerProvider()
        let contextTrigger = contextTriggerProvider()     // \\
        let queryTrigger = queryTriggerProvider()         // ??
        let translateTrigger = translateTriggerProvider() // ;;
        let mathTrigger = mathTriggerProvider()           // ==
        let rephraseTrigger = rephraseTriggerProvider()   // ||
        let voiceTrigger = voiceTriggerProvider()         // ,,
        let customCommands = customCommandsProvider()
        let maxCustomLen = (customCommands.map { $0.count }.max() ?? 0) + 2  // +2 for ".."
        let maxLen = max(cleanTrigger.count, contextTrigger.count, queryTrigger.count, translateTrigger.count, mathTrigger.count, rephraseTrigger.count, voiceTrigger.count, maxCustomLen, 1) + 256

        for character in string {
            if character.isNewline {
                recentCharacters.removeAll()
            } else {
                recentCharacters.append(character)
                recentCharacters = String(recentCharacters.suffix(maxLen))
            }
        }
        keypressCount += 1
        lastCharacters = String(repeating: ".", count: recentCharacters.count)
        onDebugEvent(.key("\(recentCharacters.count) buffered"))

        // Check custom commands - filename IS the trigger, longest first
        for cmd in customCommands.sorted(by: { $0.count > $1.count }) {
            if recentCharacters.hasSuffix(cmd) {
                recentCharacters.removeAll()
                lastCharacters = ""
                onDebugEvent(.triggerMatchedContext)
                onTrigger(.custom(cmd))
                return
            }
        }

        // Check rephrase trigger (||)
        if recentCharacters.hasSuffix(rephraseTrigger) {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatched)
            onTrigger(.rephrase)
            return
        }

        // Check math trigger (==)
        if recentCharacters.hasSuffix(mathTrigger) {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatchedTranslate)  // reuse event for now
            onTrigger(.math)
            return
        }

        // Check translate trigger (;;)
        if recentCharacters.hasSuffix(translateTrigger) {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatchedTranslate)
            onTrigger(.translate)
            return
        }

        // Check context trigger (\\) - read screen
        if recentCharacters.hasSuffix(contextTrigger) {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatchedContext)
            onTrigger(.context)
            return
        }

        // Check query trigger (??) - ask AI
        if recentCharacters.hasSuffix(queryTrigger) {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatchedRewrite)
            onTrigger(.query)
            return
        }

        // Check voice-only trigger (,,). This intentionally fires anywhere so
        // app composers with stale/inaccessible line state can still start voice.
        if recentCharacters.hasSuffix(voiceTrigger) {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatchedVoice)
            onTrigger(.smartBrevity)
            return
        }

        // Check clean trigger (//)
        if recentCharacters.hasSuffix(cleanTrigger) {
            guard shouldFireCleanTrigger(cleanTrigger) else { return }
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatched)
            onTrigger(.clean)
        }
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
}
