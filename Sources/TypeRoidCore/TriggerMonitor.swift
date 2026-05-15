import AppKit
import Carbon
import Foundation

public final class TriggerMonitor {
    private let onTrigger: () -> Void
    private let triggerProvider: () -> String
    private let onDebugEvent: (TriggerMonitorDebugEvent) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recentCharacters = ""
    private(set) public var isActive = false
    private(set) public var lastCharacters = ""
    private(set) public var keypressCount = 0

    public init(
        triggerProvider: @escaping () -> String,
        onDebugEvent: @escaping (TriggerMonitorDebugEvent) -> Void = { _ in },
        onTrigger: @escaping () -> Void
    ) {
        self.triggerProvider = triggerProvider
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
        for character in string {
            if character.isNewline {
                recentCharacters.removeAll()
            } else {
                recentCharacters.append(character)
                recentCharacters = String(recentCharacters.suffix(max(triggerProvider().count, 1)))
            }
        }
        keypressCount += 1
        lastCharacters = recentCharacters
        onDebugEvent(.key(recentCharacters))

        if recentCharacters == triggerProvider() {
            recentCharacters.removeAll()
            lastCharacters = ""
            onDebugEvent(.triggerMatched)
            onTrigger()
        }
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
}
