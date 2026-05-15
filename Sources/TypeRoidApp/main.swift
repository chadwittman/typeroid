import AppKit
import ApplicationServices
import Carbon
import Foundation
import TypeRoidCore

@MainActor
final class TypeRoidApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var triggerMonitor: TriggerMonitor?
    private var isEnabled = true
    private var lastReplacement: ReplacementRecord?
    private var monitorStatus = "starting"
    private var keypressCount = 0
    private var lastTriggerDebug = "none"
    private var statusMenuItem: NSMenuItem?
    private var debugMenuItem: NSMenuItem?
    private var countMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        ensureAccessibilityTrust()

        triggerMonitor = TriggerMonitor(
            triggerProvider: { Settings.trigger },
            onDebugEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleDebugEvent(event)
                }
            }
        ) { [weak self] in
            Task { @MainActor in
                self?.handleTrigger()
            }
        }
        triggerMonitor?.start()
    }

    private func buildMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        statusItem.button?.title = "TypeRoid"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Type like hell. Send like a pro.", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.state = isEnabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)

        let apiKey = NSMenuItem(title: "Set API Key...", action: #selector(setAPIKey), keyEquivalent: "")
        apiKey.target = self
        menu.addItem(apiKey)

        let pasteAPIKey = NSMenuItem(title: "Import API Key from Clipboard", action: #selector(importAPIKeyFromClipboard), keyEquivalent: "")
        pasteAPIKey.target = self
        menu.addItem(pasteAPIKey)

        let trigger = NSMenuItem(title: "Set Trigger... (\(Settings.trigger))", action: #selector(setTrigger), keyEquivalent: "")
        trigger.target = self
        menu.addItem(trigger)

        let undo = NSMenuItem(title: "Undo Last Rewrite", action: #selector(undoLastRewrite), keyEquivalent: "z")
        undo.target = self
        menu.addItem(undo)

        menu.addItem(NSMenuItem.separator())

        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let statusMenuItem {
            menu.addItem(statusMenuItem)
        }

        debugMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let debugMenuItem {
            menu.addItem(debugMenuItem)
        }

        countMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let countMenuItem {
            menu.addItem(countMenuItem)
        }

        let testAlert = NSMenuItem(title: "Show Debug Status", action: #selector(showDebugStatus), keyEquivalent: "")
        testAlert.target = self
        menu.addItem(testAlert)

        menu.addItem(NSMenuItem.separator())

        let permissions = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        let inputPermissions = NSMenuItem(title: "Open Input Monitoring Settings", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inputPermissions.target = self
        menu.addItem(inputPermissions)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit TypeRoid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        refreshDebugMenuItems()
    }

    private func ensureAccessibilityTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        statusItem.button?.title = isEnabled ? "TypeRoid" : "TypeRoid Off"
    }

    @objc private func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "OpenAI API Key"
        alert.informativeText = "Stored in your macOS Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = "sk-..."
        field.stringValue = Settings.apiKey ?? ""
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.apiKey = value.isEmpty ? nil : value
    }

    @objc private func importAPIKeyFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            notify("Clipboard does not contain an API key.")
            return
        }

        Settings.apiKey = value
        notify("API key imported from clipboard.")
    }

    @objc private func setTrigger() {
        let alert = NSAlert()
        alert.messageText = "Trigger"
        alert.informativeText = "Type this after messy text to clean and replace it."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "//"
        field.stringValue = Settings.trigger
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.trigger = value.isEmpty ? "//" : value
        buildMenu()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showDebugStatus() {
        notify("""
        Monitor: \(monitorStatus)
        Keys seen: \(keypressCount)
        Last keys: \(lastTriggerDebug)
        Trigger: \(Settings.trigger)
        Accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no")
        """)
    }

    @objc private func undoLastRewrite() {
        guard let record = lastReplacement else { return }
        ClipboardReplacement.replaceCurrentSelection(with: record.original)
        lastReplacement = nil
    }

    private func handleDebugEvent(_ event: TriggerMonitorDebugEvent) {
        switch event {
        case .tapStarted:
            monitorStatus = "active"
        case .tapCreationFailed:
            monitorStatus = "blocked"
            notify("Keyboard monitor could not start. Enable TypeRoid in Input Monitoring, then quit and reopen it.")
        case .tapReenabled:
            monitorStatus = "re-enabled"
        case .key(let keys):
            keypressCount += 1
            lastTriggerDebug = keys.isEmpty ? "empty" : keys
            statusItem.button?.title = isEnabled ? "TypeRoid" : "TypeRoid Off"
        case .triggerMatched:
            lastTriggerDebug = "trigger matched"
            statusItem.button?.title = "TypeRoid!"
        }
        refreshDebugMenuItems()
    }

    private func refreshDebugMenuItems() {
        statusMenuItem?.title = "Monitor: \(monitorStatus)"
        debugMenuItem?.title = "Last keys: \(lastTriggerDebug)"
        countMenuItem?.title = "Keys seen: \(keypressCount)"
    }

    private func handleTrigger() {
        guard isEnabled else { return }
        guard AXIsProcessTrusted() else {
            notify("TypeRoid needs Accessibility permission.")
            ensureAccessibilityTrust()
            return
        }
        guard Settings.apiKey != nil else {
            notify("Set your OpenAI API key from the TypeRoid menu.")
            return
        }

        Task { @MainActor in
            do {
                statusItem.button?.title = "TypeRoid..."
                defer { statusItem.button?.title = isEnabled ? "TypeRoid" : "TypeRoid Off" }

                let trigger = Settings.trigger
                try await Task.sleep(for: .milliseconds(80))
                let captured = try await ClipboardReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
                let cleaned = try await TextCleaner.clean(captured.text)

                guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    ClipboardReplacement.replaceCurrentSelection(with: captured.text)
                    return
                }

                ClipboardReplacement.replaceCurrentSelection(with: cleaned)
                lastReplacement = ReplacementRecord(original: captured.text, replacement: cleaned)
            } catch {
                notify("TypeRoid failed: \(error.localizedDescription)")
            }
        }
    }

    private func notify(_ message: String) {
        statusItem.button?.title = "TypeRoid !"

        let alert = NSAlert()
        alert.messageText = "TypeRoid"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        statusItem.button?.title = isEnabled ? "TypeRoid" : "TypeRoid Off"
    }
}

struct ReplacementRecord {
    let original: String
    let replacement: String
}

let app = NSApplication.shared
let delegate = TypeRoidApp()
app.delegate = delegate
app.run()
