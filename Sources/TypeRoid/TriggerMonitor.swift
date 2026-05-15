import AppKit
import Carbon
import Foundation

final class TriggerMonitor {
    private let onTrigger: () -> Void
    private let triggerProvider: () -> String
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recentCharacters = ""

    init(triggerProvider: @escaping () -> String, onTrigger: @escaping () -> Void) {
        self.triggerProvider = triggerProvider
        self.onTrigger = onTrigger
    }

    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard type == .keyDown, let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<TriggerMonitor>.fromOpaque(refcon).takeUnretainedValue()
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

        guard let eventTap else { return }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
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

        if recentCharacters == triggerProvider() {
            recentCharacters.removeAll()
            onTrigger()
        }
    }

    private func isCommandShortcut(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return flags.contains(.maskCommand) || flags.contains(.maskControl)
    }
}
