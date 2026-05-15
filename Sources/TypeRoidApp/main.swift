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
    private var lastRewriteStatus = "none"
    private var lastCapturedPreview = "none"
    private var lastTypingAppName: String?
    private var lastTypingBundleID: String?
    private var statusMenuItem: NSMenuItem?
    private var debugMenuItem: NSMenuItem?
    private var countMenuItem: NSMenuItem?
    private var rewriteStatusMenuItem: NSMenuItem?
    private var capturedPreviewMenuItem: NSMenuItem?
    private var exclusionMenuItem: NSMenuItem?

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

        let testCleanup = NSMenuItem(title: "Test Cleanup API", action: #selector(testCleanupAPI), keyEquivalent: "")
        testCleanup.target = self
        menu.addItem(testCleanup)

        let trigger = NSMenuItem(title: "Set Trigger... (\(Settings.trigger))", action: #selector(setTrigger), keyEquivalent: "")
        trigger.target = self
        menu.addItem(trigger)

        let undo = NSMenuItem(title: "Undo Last Rewrite", action: #selector(undoLastRewrite), keyEquivalent: "z")
        undo.target = self
        menu.addItem(undo)

        exclusionMenuItem = NSMenuItem(title: "", action: #selector(toggleLastTypingAppExclusion), keyEquivalent: "")
        exclusionMenuItem?.target = self
        if let exclusionMenuItem {
            menu.addItem(exclusionMenuItem)
        }

        let clearExclusions = NSMenuItem(title: "Clear App Exclusions", action: #selector(clearAppExclusions), keyEquivalent: "")
        clearExclusions.target = self
        menu.addItem(clearExclusions)

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

        rewriteStatusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let rewriteStatusMenuItem {
            menu.addItem(rewriteStatusMenuItem)
        }

        capturedPreviewMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let capturedPreviewMenuItem {
            menu.addItem(capturedPreviewMenuItem)
        }

        let testAlert = NSMenuItem(title: "Show Debug Status", action: #selector(showDebugStatus), keyEquivalent: "")
        testAlert.target = self
        menu.addItem(testAlert)

        let copyDebug = NSMenuItem(title: "Copy Debug Status", action: #selector(copyDebugStatus), keyEquivalent: "")
        copyDebug.target = self
        menu.addItem(copyDebug)

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

    @objc private func testCleanupAPI() {
        guard Settings.apiKey != nil else {
            notify("Set your OpenAI API key from the TypeRoid menu first.")
            return
        }

        Task { @MainActor in
            do {
                statusItem.button?.title = "TypeRoid..."
                defer { statusItem.button?.title = isEnabled ? "TypeRoid" : "TypeRoid Off" }

                let sample = "hey john i saw the thing come through looks good but can we move meeting to tmrw im slammed today"
                let cleaned = try await TextCleaner.clean(sample)
                notify("API cleanup works:\n\n\(cleaned)")
            } catch {
                notify("API cleanup failed: \(error.localizedDescription)")
            }
        }
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
        notify(debugStatusText())
    }

    @objc private func copyDebugStatus() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(debugStatusText(), forType: .string)
        notify("Debug status copied.")
    }

    @objc private func undoLastRewrite() {
        guard let record = lastReplacement else { return }
        if let accessibilityCaptured = record.accessibilityCaptured {
            try? AccessibilityReplacement.replaceCapturedText(accessibilityCaptured, with: record.original)
        } else {
            ClipboardReplacement.replaceCurrentSelection(with: record.original)
        }
        lastReplacement = nil
    }

    @objc private func toggleLastTypingAppExclusion() {
        guard let bundleID = lastTypingBundleID else {
            notify("Type somewhere first, then open this menu to exclude that app.")
            return
        }

        let shouldExclude = !Settings.isExcluded(bundleID: bundleID)
        Settings.setExcluded(shouldExclude, bundleID: bundleID)
        refreshDebugMenuItems()

        let appName = lastTypingAppName ?? bundleID
        notify(shouldExclude ? "TypeRoid disabled in \(appName)." : "TypeRoid enabled in \(appName).")
    }

    @objc private func clearAppExclusions() {
        Settings.excludedBundleIDs = []
        refreshDebugMenuItems()
        notify("App exclusions cleared.")
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
            updateLastTypingApplication()
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
        rewriteStatusMenuItem?.title = "Last rewrite: \(lastRewriteStatus)"
        capturedPreviewMenuItem?.title = "Captured: \(lastCapturedPreview)"
        if let bundleID = lastTypingBundleID {
            let appName = lastTypingAppName ?? bundleID
            let title = Settings.isExcluded(bundleID: bundleID) ? "Enable in \(appName)" : "Exclude \(appName)"
            exclusionMenuItem?.title = title
            exclusionMenuItem?.isEnabled = true
        } else {
            exclusionMenuItem?.title = "Exclude Current App"
            exclusionMenuItem?.isEnabled = false
        }
    }

    private func updateLastTypingApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastTypingAppName = app.localizedName
        lastTypingBundleID = app.bundleIdentifier
    }

    private func handleTrigger() {
        guard isEnabled else { return }
        setRewriteStatus("triggered")
        updateLastTypingApplication()
        guard !Settings.isExcluded(bundleID: lastTypingBundleID) else {
            setRewriteStatus("excluded app")
            statusItem.button?.title = "TypeRoid Excluded"
            return
        }
        guard AXIsProcessTrusted() else {
            setRewriteStatus("needs accessibility")
            notify("TypeRoid needs Accessibility permission.")
            ensureAccessibilityTrust()
            return
        }
        guard Settings.apiKey != nil else {
            setRewriteStatus("missing API key")
            notify("Set your OpenAI API key from the TypeRoid menu.")
            return
        }

        Task { @MainActor in
            do {
                statusItem.button?.title = "TypeRoid..."
                defer { statusItem.button?.title = isEnabled ? "TypeRoid" : "TypeRoid Off" }

                let trigger = Settings.trigger
                try await Task.sleep(for: .milliseconds(80))
                if try await handleTriggerWithAccessibility(trigger: trigger) {
                    return
                }

                setRewriteStatus("capturing")
                let captured = try await ClipboardReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
                lastCapturedPreview = preview(captured.text)
                setRewriteStatus("cleaning")
                let cleaned = try await TextCleaner.clean(captured.text)

                guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    setRewriteStatus("unchanged")
                    ClipboardReplacement.replaceCurrentSelection(with: captured.text)
                    return
                }

                setRewriteStatus("replacing")
                ClipboardReplacement.replaceCurrentSelection(with: cleaned)
                lastReplacement = ReplacementRecord(
                    original: captured.text,
                    replacement: cleaned,
                    accessibilityCaptured: nil
                )
                setRewriteStatus("replaced")
            } catch {
                setRewriteStatus("failed: \(error.localizedDescription)")
                notify("TypeRoid failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleTriggerWithAccessibility(trigger: String) async throws -> Bool {
        do {
            setRewriteStatus("capturing via accessibility")
            let captured = try AccessibilityReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
            lastCapturedPreview = preview(captured.text)

            setRewriteStatus("cleaning")
            let cleaned = try await TextCleaner.clean(captured.text)

            guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                setRewriteStatus("unchanged")
                try AccessibilityReplacement.replaceCapturedText(captured, with: captured.text)
                return true
            }

            setRewriteStatus("replacing via accessibility")
            try AccessibilityReplacement.replaceCapturedText(captured, with: cleaned)
            lastReplacement = ReplacementRecord(
                original: captured.text,
                replacement: cleaned,
                accessibilityCaptured: captured
            )
            setRewriteStatus("replaced")
            return true
        } catch let error as AccessibilityReplacementError {
            setRewriteStatus("accessibility fallback: \(error.localizedDescription)")
            return false
        }
    }

    private func setRewriteStatus(_ status: String) {
        lastRewriteStatus = preview(status)
        refreshDebugMenuItems()
    }

    private func preview(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > 48 else { return singleLine.isEmpty ? "empty" : singleLine }
        return "\(singleLine.prefix(45))..."
    }

    private func debugStatusText() -> String {
        """
        Monitor: \(monitorStatus)
        Keys seen: \(keypressCount)
        Last keys: \(lastTriggerDebug)
        Last rewrite: \(lastRewriteStatus)
        Last captured: \(lastCapturedPreview)
        Trigger: \(Settings.trigger)
        Last app: \(lastTypingAppName ?? "unknown")
        Last bundle ID: \(lastTypingBundleID ?? "unknown")
        Accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no")
        """
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
    let accessibilityCaptured: AccessibilityCapturedText?
}

let app = NSApplication.shared
let delegate = TypeRoidApp()
app.delegate = delegate
app.run()
