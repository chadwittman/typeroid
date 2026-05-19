import AppKit
import ApplicationServices
import Carbon
import Foundation
import TypeRoidCore

// MARK: - Menu bar status (dynamic title like <title>)

@MainActor
final class MenuBarStatus {
    private weak var statusItem: NSStatusItem?
    private var resetTask: Task<Void, Never>?

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    func show(_ text: String, resetAfter: Double? = 2.0) {
        resetTask?.cancel()
        statusItem?.button?.image = nil
        statusItem?.button?.title = text

        if let delay = resetAfter {
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                self.reset()
            }
        }
    }

    func reset() {
        resetTask?.cancel()
        statusItem?.button?.title = ""
        statusItem?.button?.image = makeMenuBarIcon()
    }
}

// MARK: - Menu bar icon

@MainActor
func makeMenuBarIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let str = NSAttributedString(string: "//", attributes: [.font: font, .foregroundColor: NSColor.white])
        str.draw(at: NSPoint(x: (rect.width - str.size().width) / 2, y: (rect.height - str.size().height) / 2))
        return true
    }
    img.isTemplate = true
    return img
}

// MARK: - App

@MainActor
final class TypeRoidApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var triggerMonitor: TriggerMonitor?
    private var isEnabled = true
    private var lastReplacement: ReplacementRecord?
    private var clearReplacementTask: Task<Void, Never>?
    private var monitorStatus = "starting"
    private var keypressCount = 0
    private var lastTriggerDebug = "none"
    private var lastRewriteStatus = "none"
    private var lastCapturedSummary = "none"
    private var lastTypingAppName: String?
    private var lastTypingBundleID: String?
    private var statusMenuItem: NSMenuItem?
    private var debugMenuItem: NSMenuItem?
    private var countMenuItem: NSMenuItem?
    private var rewriteStatusMenuItem: NSMenuItem?
    private var capturedPreviewMenuItem: NSMenuItem?
    private var exclusionMenuItem: NSMenuItem?
    private let onboarding = OnboardingWindow()
    private var openMenuAfterRewriteMenuItem: NSMenuItem?
    private var status: MenuBarStatus!
    private var latestAvailableVersion: String?

    private let loadingMessages = [
        "typeROIDing",
        "juicing your text",
        "on the cycle",
        "cooking",
        "getting swole",
        "injecting clarity",
        "hitting the gym",
        "running the cycle",
        "getting jacked",
        "on it",
        "doing reps",
        "maxing out",
    ]

    private var loadingTimer: Timer?
    private var dotCount = 1

    private var appIcon: NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable Cmd+Q
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit typeROID", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu

        buildMenu()

        // Check if app is in /Applications (needed for permissions to stick)
        let appPath = Bundle.main.bundlePath
        let inApplications = appPath.hasPrefix("/Applications") || appPath.hasPrefix(NSHomeDirectory() + "/Applications")

        let needsSetup = !Settings.onboardingComplete || Settings.apiKey == nil
        if needsSetup {
            NSApp.setActivationPolicy(.regular)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if !inApplications {
                    await showMoveToApplications()
                }
                runOnboarding()
            }
        } else {
            NSApp.setActivationPolicy(.accessory)
            startMonitorWithRetry()
        }

        // Check for updates silently
        Task.detached {
            await self.checkForUpdates()
        }

        // Safety: always try to start monitor even during onboarding
        // (in case user already granted permissions)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if triggerMonitor == nil || !triggerMonitor!.isActive {
                startMonitor()
            }
        }
    }

    private func showMoveToApplications() async {
        let alert = makeAlert("Move typeROID to Applications first.",
            "Drag typeROID.app into your Applications folder before continuing.\n\nmacOS needs the app in a stable location for permissions to work. If it's still in Downloads or on your Desktop, permissions will break next time you move it.\n\nOnce it's in Applications, reopen it from there.")
        alert.addButton(withTitle: "Open Applications Folder")
        alert.addButton(withTitle: "It's already there")
        NSApp.activate(ignoringOtherApps: true)
        let r = alert.runModal()
        if r == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            // Quit so they reopen from Applications
            NSApp.terminate(nil)
        }
    }

    private func startMonitorWithRetry() {
        startMonitor()
        // If permissions aren't ready yet, keep checking every 3 seconds
        if monitorStatus != "active" {
            Task { @MainActor in
                for _ in 0..<20 { // try for up to 60 seconds
                    try? await Task.sleep(for: .seconds(3))
                    if AXIsProcessTrusted() {
                        startMonitor()
                        if monitorStatus == "active" { return }
                    }
                }
            }
        }
    }

    private func startMonitor() {
        if !AXIsProcessTrusted() { monitorStatus = "needs permission"; return }
        triggerMonitor = TriggerMonitor(
            triggerProvider: { Settings.trigger },
            contextTriggerProvider: { Settings.rewriteTrigger },
            queryTriggerProvider: { Settings.contextTrigger },
            translateTriggerProvider: { Settings.translateTrigger },
            mathTriggerProvider: { Settings.mathTrigger },
            onDebugEvent: { [weak self] event in Task { @MainActor in self?.handleDebugEvent(event) } }
        ) { [weak self] mode in Task { @MainActor in self?.handleTrigger(mode: mode) } }
        triggerMonitor?.start()
    }

    private func makeAlert(_ title: String, _ body: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        if let icon = appIcon { alert.icon = icon }
        return alert
    }

    private func setStatusIcon() {
        statusItem.button?.image = makeMenuBarIcon()
        statusItem.button?.title = ""
    }

    // MARK: - API Key via clipboard (since NSAlert eats paste events)

    private func askForAPIKey(provider: AIProvider) -> String? {
        // Check clipboard first
        let clipboardKey = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasClipboardKey = !clipboardKey.isEmpty && (
            clipboardKey.hasPrefix("sk-") ||
            clipboardKey.hasPrefix("sk-ant-") ||
            clipboardKey.hasPrefix("AIza") ||
            clipboardKey.hasPrefix("gsk_")
        )

        if hasClipboardKey {
            // Key is on clipboard already
            let alert = makeAlert("Found an API key on your clipboard",
                "This looks like it could be a \(provider.displayName) key:\n\n\(String(clipboardKey.prefix(12)))...\(String(clipboardKey.suffix(4)))\n\nUse this key?")
            alert.addButton(withTitle: "Use this key")
            alert.addButton(withTitle: "Enter manually")
            alert.addButton(withTitle: "Skip")

            NSApp.activate(ignoringOtherApps: true)
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                return clipboardKey
            } else if resp == .alertSecondButtonReturn {
                return askForAPIKeyManually(provider: provider)
            }
            return nil
        } else {
            return askForAPIKeyManually(provider: provider)
        }
    }

    private func askForAPIKeyManually(provider: AIProvider) -> String? {
        let alert = makeAlert("Paste your \(provider.displayName) API key",
        """
        Copy your API key from the \(provider.displayName) dashboard, then:

        Option 1: Copy it, then click "Paste from Clipboard"
        Option 2: Type/paste it in the field below

        Your key is stored in the macOS Keychain. Encrypted. Never sent anywhere except \(provider.displayName).
        """)
        alert.addButton(withTitle: "Paste from Clipboard")
        alert.addButton(withTitle: "Skip for now")

        // Still provide a text field as backup
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = provider.keyPlaceholder
        field.isEditable = true
        field.isSelectable = true
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        let resp = alert.runModal()

        if resp == .alertFirstButtonReturn {
            // Try clipboard first
            let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !clip.isEmpty { return clip }
            // Fall back to text field
            let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return typed.isEmpty ? nil : typed
        }

        // Check if they managed to type something
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? nil : typed
    }

    // MARK: - Menu

    private func buildMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            status = MenuBarStatus(statusItem: statusItem)
        }
        setStatusIcon()

        let menu = NSMenu()

        let allGood = AXIsProcessTrusted() && (triggerMonitor?.isActive ?? false) && Settings.apiKey != nil
        let statusText = allGood ? "typeROID  ● ready" : "typeROID  ○ setup needed"
        let statusItem2 = NSMenuItem(title: statusText, action: allGood ? nil : #selector(rerunOnboarding), keyEquivalent: "")
        if !allGood { statusItem2.target = self }
        menu.addItem(statusItem2)
        menu.addItem(NSMenuItem.separator())

        // Core actions
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.state = isEnabled ? .on : .off; toggle.target = self
        menu.addItem(toggle)

        let undo = NSMenuItem(title: "Undo", action: #selector(undoLastRewrite), keyEquivalent: "z")
        undo.target = self
        menu.addItem(undo)

        menu.addItem(NSMenuItem.separator())

        // Settings submenu (everything tucked in here)
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        // Provider
        let providerItem = NSMenuItem(title: "Provider: \(Settings.provider.displayName)", action: nil, keyEquivalent: "")
        let providerMenu = NSMenu()
        for p in AIProvider.allCases {
            let item = NSMenuItem(title: p.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.rawValue
            item.state = p == Settings.provider ? .on : .off
            providerMenu.addItem(item)
        }
        providerItem.submenu = providerMenu
        settingsMenu.addItem(providerItem)

        // Model
        let modelItem = NSMenuItem(title: "Model: \(Settings.model)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for m in Settings.provider.availableModels {
            let item = NSMenuItem(title: m, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = m
            item.state = m == Settings.model ? .on : .off
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        settingsMenu.addItem(modelItem)

        // Translate target (;; output language)
        let transItem = NSMenuItem(title: "Translate to: \(Settings.translateTarget)", action: nil, keyEquivalent: "")
        let transMenu = NSMenu()
        for lang in Settings.supportedLanguages {
            let item = NSMenuItem(title: lang, action: #selector(selectTranslateTarget(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = lang
            item.state = lang == Settings.translateTarget ? .on : .off
            transMenu.addItem(item)
        }
        transItem.submenu = transMenu
        settingsMenu.addItem(transItem)

        // API Key
        let apiKeyItem = NSMenuItem(title: "API Key...", action: #selector(setAPIKeyAction), keyEquivalent: "")
        apiKeyItem.target = self; settingsMenu.addItem(apiKeyItem)

        let testItem = NSMenuItem(title: "Test API", action: #selector(testCleanupAPI), keyEquivalent: "")
        testItem.target = self; settingsMenu.addItem(testItem)

        // Custom commands
        let cmds = TextCleaner.availableCommands()
        if !cmds.isEmpty {
            let cmdItem = NSMenuItem(title: "Commands (\(cmds.count))", action: nil, keyEquivalent: "")
            let cmdMenu = NSMenu()
            for cmd in cmds {
                cmdMenu.addItem(NSMenuItem(title: "\(cmd)", action: nil, keyEquivalent: ""))
            }
            cmdMenu.addItem(NSMenuItem.separator())
            let openDir = NSMenuItem(title: "Open Commands Folder", action: #selector(openCommandsFolder), keyEquivalent: "")
            openDir.target = self; cmdMenu.addItem(openDir)
            cmdItem.submenu = cmdMenu
            settingsMenu.addItem(cmdItem)
        } else {
            let openDir = NSMenuItem(title: "Add Custom Commands", action: #selector(openCommandsFolder), keyEquivalent: "")
            openDir.target = self; settingsMenu.addItem(openDir)
        }

        settingsMenu.addItem(NSMenuItem.separator())

        // Web search for ?? (OpenAI + Gemini only)
        if Settings.provider == .openai || Settings.provider == .google {
            let webToggle = NSMenuItem(title: "Web Search for ??", action: #selector(toggleWebSearch(_:)), keyEquivalent: "")
            webToggle.target = self; webToggle.state = Settings.webSearchEnabled ? .on : .off
            settingsMenu.addItem(webToggle)
        }

        let styleToggle = NSMenuItem(title: "Enable Writing Style", action: #selector(toggleWritingStyle(_:)), keyEquivalent: "")
        styleToggle.target = self; styleToggle.state = Settings.useWritingStyle ? .on : .off
        settingsMenu.addItem(styleToggle)

        let styleItem = NSMenuItem(title: "Edit Writing Style", action: #selector(openStyleFile), keyEquivalent: "")
        styleItem.target = self; settingsMenu.addItem(styleItem)

        settingsMenu.addItem(NSMenuItem.separator())

        // App exclusion
        exclusionMenuItem = NSMenuItem(title: "", action: #selector(toggleLastTypingAppExclusion), keyEquivalent: "")
        exclusionMenuItem?.target = self
        if let e = exclusionMenuItem { settingsMenu.addItem(e) }

        openMenuAfterRewriteMenuItem = NSMenuItem(title: "Open Menu After //", action: #selector(toggleOpenMenuAfterRewrite(_:)), keyEquivalent: "")
        openMenuAfterRewriteMenuItem?.target = self
        openMenuAfterRewriteMenuItem?.state = Settings.openMenuAfterRewrite ? .on : .off
        if let item = openMenuAfterRewriteMenuItem { settingsMenu.addItem(item) }

        settingsMenu.addItem(NSMenuItem.separator())

        // Permissions
        let acc = NSMenuItem(title: "Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        acc.target = self; settingsMenu.addItem(acc)
        let inp = NSMenuItem(title: "Input Monitoring", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inp.target = self; settingsMenu.addItem(inp)

        settingsMenu.addItem(NSMenuItem.separator())

        // Diagnostics
        let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        diagnostics.submenu = buildDiagnosticsMenu()
        settingsMenu.addItem(diagnostics)

        let runSetup = NSMenuItem(title: "Run Setup Again", action: #selector(rerunOnboarding), keyEquivalent: "")
        runSetup.target = self; settingsMenu.addItem(runSetup)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Update check
        if let latestVersion = latestAvailableVersion, latestVersion != Settings.currentVersion {
            let updateItem = NSMenuItem(title: "Update available: v\(latestVersion)", action: #selector(openReleasesPage), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        let versionItem = NSMenuItem(title: "v\(Settings.currentVersion)", action: nil, keyEquivalent: "")
        menu.addItem(versionItem)

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        refreshDebugMenuItems()
    }

    private func buildDiagnosticsMenu() -> NSMenu {
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let s = statusMenuItem { menu.addItem(s) }
        debugMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let d = debugMenuItem { menu.addItem(d) }
        countMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let c = countMenuItem { menu.addItem(c) }
        rewriteStatusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let r = rewriteStatusMenuItem { menu.addItem(r) }
        capturedPreviewMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let c = capturedPreviewMenuItem { menu.addItem(c) }
        let copy = NSMenuItem(title: "Copy Debug Status", action: #selector(copyDebugStatus), keyEquivalent: "")
        copy.target = self; menu.addItem(copy)
        return menu
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle(); sender.state = isEnabled ? .on : .off
        setStatusIcon()
    }
    @objc private func toggleOpenMenuAfterRewrite(_ sender: NSMenuItem) {
        Settings.openMenuAfterRewrite.toggle(); sender.state = Settings.openMenuAfterRewrite ? .on : .off
    }
    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let p = AIProvider(rawValue: raw) else { return }

        if p == .google {
            let alert = makeAlert("Heads up about Google Gemini",
                "Google's API requires your API key in the URL. Your text is always encrypted in transit (HTTPS), but the key itself could be visible to anyone inspecting your network traffic, like a corporate VPN, work wifi, or public wifi.\n\nThe other providers (OpenAI, Claude, Groq) send the key in a header, which is fully encrypted.\n\nGoogle is fine on a trusted network. Just something to know.")
            alert.addButton(withTitle: "Use Google anyway")
            alert.addButton(withTitle: "Pick a different provider")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        Settings.provider = p; Settings.model = p.defaultModel; buildMenu()
    }
    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let m = sender.representedObject as? String else { return }
        Settings.model = m; buildMenu()
    }
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let l = sender.representedObject as? String else { return }
        Settings.language = l; buildMenu()
        status.show("\(l)")
    }
    private func checkForUpdates() async {
        guard let url = URL(string: Settings.updateCheckURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty, version != Settings.currentVersion {
                await MainActor.run {
                    latestAvailableVersion = version
                    buildMenu()
                }
            }
        } catch {
            // silently fail, not critical
        }
    }

    @objc private func openReleasesPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/typeroid/typeroid/releases")!)
    }

    @objc private func toggleWebSearch(_ sender: NSMenuItem) {
        Settings.webSearchEnabled.toggle()
        sender.state = Settings.webSearchEnabled ? .on : .off
        status.show(Settings.webSearchEnabled ? "?? web on" : "?? web off")
    }
    @objc private func toggleWritingStyle(_ sender: NSMenuItem) {
        Settings.useWritingStyle.toggle()
        sender.state = Settings.useWritingStyle ? .on : .off
        status.show(Settings.useWritingStyle ? "style on" : "style off")
    }
    @objc private func selectTranslateTarget(_ sender: NSMenuItem) {
        guard let l = sender.representedObject as? String else { return }
        Settings.translateTarget = l; buildMenu()
        status.show(";; -> \(l)")
    }
    @objc private func setAPIKeyAction() {
        if let key = askForAPIKey(provider: Settings.provider) {
            Settings.setAPIKey(key, for: Settings.provider)
            status.show("Key saved!")
        }
    }
    @objc private func testCleanupAPI() {
        guard Settings.apiKey != nil else { status.show("No API key set"); return }
        Task { @MainActor in
            status.show("// testing...", resetAfter: nil)
            do {
                let sample = "yojohn saww you lookmaxxing during the meting w our client, bettr off mewing on your own time bro lmaooo"
                let cleaned = try await TextCleaner.process(sample, mode: .clean)
                status.show("It works!")
                let a = makeAlert("It works!", "You typed:\n\(sample)\n\ntypeROID made it:\n\(cleaned)")
                a.addButton(withTitle: "Nice"); NSApp.activate(ignoringOtherApps: true); a.runModal()
            } catch {
                status.show("API failed")
                let a = makeAlert("API test failed", error.localizedDescription)
                a.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); a.runModal()
            }
        }
    }
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc private func copyDebugStatus() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugStatusText(), forType: .string)
        status.show("Copied!")
    }
    @objc private func undoLastRewrite() {
        guard let r = lastReplacement else { status.show("Nothing to undo"); return }
        if let a = r.accessibilityCaptured { try? AccessibilityReplacement.replaceCapturedText(a, with: r.original) }
        else { ClipboardReplacement.replaceCurrentSelection(with: r.original) }
        lastReplacement = nil; status.show("Undone!")
    }
    @objc private func toggleLastTypingAppExclusion() {
        guard let bid = lastTypingBundleID else { return }
        let exclude = !Settings.isExcluded(bundleID: bid)
        Settings.setExcluded(exclude, bundleID: bid); refreshDebugMenuItems()
        status.show(exclude ? "\(lastTypingAppName ?? bid) excluded" : "\(lastTypingAppName ?? bid) enabled")
    }
    @objc private func clearAppExclusions() {
        Settings.resetExcludedBundleIDsToDefaults(); refreshDebugMenuItems()
        status.show("Exclusions reset")
    }
    @objc private func rerunOnboarding() { Settings.onboardingComplete = false; runOnboarding() }
    @objc private func openCommandsFolder() {
        let dir = NSHomeDirectory() + "/.typeroid/commands"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }
    @objc private func openStyleFile() {
        let path = Settings.stylePath
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: path) {
            try? "# My Writing Style\n\nDescribe how you write here.\n".write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Inline Loading

    private func startInlineLoading(in captured: AccessibilityCapturedText?, fallbackTrigger: String) {
        let msg = loadingMessages.randomElement() ?? "typeROIDing"
        dotCount = 1

        // Replace text immediately with loading message
        if let captured {
            try? AccessibilityReplacement.replaceCapturedText(captured, with: "\(msg).")
        }

        // Animate dots: . -> .. -> ... -> . (every 400ms)
        loadingTimer?.invalidate()
        loadingTimer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let captured else { return }
                self.dotCount = (self.dotCount % 3) + 1
                let dots = String(repeating: ".", count: self.dotCount)
                try? AccessibilityReplacement.replaceCapturedText(captured, with: "\(msg)\(dots)")
            }
        }
        if let timer = loadingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopInlineLoading() {
        loadingTimer?.invalidate()
        loadingTimer = nil
    }

    // MARK: - Trigger

    private func handleDebugEvent(_ event: TriggerMonitorDebugEvent) {
        switch event {
        case .tapStarted: monitorStatus = "active"
        case .tapCreationFailed: monitorStatus = "blocked"; status.show("Keyboard monitor failed. Check permissions.")
        case .tapReenabled: monitorStatus = "re-enabled"
        case .key(let k): keypressCount += 1; lastTriggerDebug = k.isEmpty ? "empty" : k; updateLastTypingApplication(); setStatusIcon()
        case .triggerMatched: lastTriggerDebug = "// matched"
        case .triggerMatchedRewrite: lastTriggerDebug = "?? matched"
        case .triggerMatchedContext: lastTriggerDebug = "\\\\ matched"
        case .triggerMatchedTranslate: lastTriggerDebug = ";; matched"
        }
        refreshDebugMenuItems()
    }

    private func refreshDebugMenuItems() {
        statusMenuItem?.title = "Monitor: \(monitorStatus)"
        debugMenuItem?.title = "Last keys: \(lastTriggerDebug)"
        countMenuItem?.title = "Keys seen: \(keypressCount)"
        rewriteStatusMenuItem?.title = "Last rewrite: \(lastRewriteStatus)"
        capturedPreviewMenuItem?.title = "Captured: \(lastCapturedSummary)"
        if let bid = lastTypingBundleID {
            let name = lastTypingAppName ?? bid
            exclusionMenuItem?.title = Settings.isExcluded(bundleID: bid) ? "Enable in \(name)" : "Exclude \(name)"
            exclusionMenuItem?.isEnabled = true
        } else { exclusionMenuItem?.title = "Exclude Current App"; exclusionMenuItem?.isEnabled = false }
    }

    private func updateLastTypingApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastTypingAppName = app.localizedName; lastTypingBundleID = app.bundleIdentifier
    }

    private func handleTrigger(mode: CleanMode) {
        guard isEnabled else { return }
        updateLastTypingApplication()
        guard !Settings.isExcluded(bundleID: lastTypingBundleID) else {
            status.show("Disabled in \(lastTypingAppName ?? "this app")"); return }
        guard AXIsProcessTrusted() else { status.show("Need Accessibility permission"); return }
        guard !AccessibilityReplacement.focusedElementIsSecureTextEntry() else {
            status.show("Won't touch password fields"); return }
        guard !AccessibilityReplacement.focusedElementLooksLikeBrowserAddressBar(bundleID: lastTypingBundleID) else {
            status.show("Won't touch address bars"); return }
        guard Settings.apiKey != nil else { status.show("No API key. Set one in the menu."); return }

        let label: String
        let verb: String
        switch mode {
        case .clean: label = "//"; verb = "fixing"
        case .query: label = "??"; verb = "asking"
        case .context: label = "\\\\"; verb = "reading"
        case .translate: label = ";;"; verb = "translating"
        case .math: label = "=="; verb = "calculating"
        case .custom(let name): label = name; verb = "running"
        }

        Task { @MainActor in
            // Start rotating loading messages
            var msgIndex = 0
            let loadingTimer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let msg = self.loadingMessages[msgIndex % self.loadingMessages.count]
                    self.status.show("\(label) \(msg)...", resetAfter: nil)
                    msgIndex += 1
                }
            }
            RunLoop.main.add(loadingTimer, forMode: .common)
            status.show("\(label) \(verb)...", resetAfter: nil)

            defer { loadingTimer.invalidate() }

            do {
                if mode == .context {
                    try await handleContextMode()
                    return
                }

                let trigger: String
                switch mode {
                case .clean: trigger = Settings.trigger
                case .query: trigger = Settings.contextTrigger
                case .translate: trigger = Settings.translateTrigger
                case .math: trigger = Settings.mathTrigger
                case .context: trigger = Settings.rewriteTrigger
                case .custom(let name): trigger = name
                }
                try await Task.sleep(for: .milliseconds(80))
                let fullCapture = mode == .query || mode == .translate
                if try await handleWithAccessibility(trigger: trigger, mode: mode, fullCapture: fullCapture) { return }

                let captured = try await ClipboardReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
                if captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    status.show("nothing to \(verb)")
                    status.reset()
                    return
                }
                lastCapturedSummary = "\(captured.text.count) chars"
                let cleaned = try await TextCleaner.process(captured.text, mode: mode)
                if mode == .clean {
                    guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                        ClipboardReplacement.replaceCurrentSelection(with: captured.text)
                        status.show("Already looks good!"); return
                    }
                }
                ClipboardReplacement.replaceCurrentSelection(with: cleaned)
                setReplacement(ReplacementRecord(original: captured.text, replacement: cleaned, accessibilityCaptured: nil))
                status.show("\(label) done")
            } catch {
                status.show("\(label) failed")
            }
            // no status.reset() here - show() auto-resets after 2s
        }
    }

    private func handleContextMode() async throws {
        // Clipboard-based context: user copies a thread, types optional instructions, hits \\
        let trigger = Settings.rewriteTrigger
        try await Task.sleep(for: .milliseconds(80))

        // 1. Read clipboard FIRST (this is the context, don't touch it)
        let clipboardContext = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if clipboardContext.isEmpty {
            status.show("\\\\ copy first")
            status.reset()
            return
        }

        // 2. Delete the trigger chars from the text field
        // Use backspace simulation (works in Slack and everywhere)
        for _ in 0..<trigger.count {
            let backspace = CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: true)
            backspace?.post(tap: .cghidEventTap)
            let backspaceUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: false)
            backspaceUp?.post(tap: .cghidEventTap)
        }
        try await Task.sleep(for: .milliseconds(50))

        // 3. Try to capture any text the user typed before the trigger
        var userRequest = ""
        var accessibilityCaptured: AccessibilityCapturedText?

        do {
            // Read the text field (trigger already deleted)
            let system = AXUIElementCreateSystemWide()
            var focusedRef: AnyObject?
            if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success {
                let element = focusedRef as! AXUIElement
                var valueRef: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
                   let value = valueRef as? String {
                    userRequest = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        status.show("\\\\ thinking...", resetAfter: nil)

        // 4. Send to AI with clipboard as context
        let response = try await TextCleaner.processWithContext(
            userRequest,
            threadContext: clipboardContext
        )

        // 5. Extract the suggested reply (last paragraph, strip label prefix)
        let paragraphs = response.components(separatedBy: "\n\n")
        var suggestedReply = paragraphs.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? response
        // Strip common label prefixes the AI might add
        for prefix in ["SUGGESTED REPLY:", "SUGGESTED REPLY", "Suggested reply:", "Suggested Reply:", "Reply:"] {
            if suggestedReply.hasPrefix(prefix) {
                suggestedReply = String(suggestedReply.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // 6. Select all text in the field and replace with response
        // Select all (Cmd+A) then paste the response
        let selectAll = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)  // 'a'
        selectAll?.flags = .maskCommand
        selectAll?.post(tap: .cghidEventTap)
        let selectAllUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: false)
        selectAllUp?.flags = .maskCommand
        selectAllUp?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(50))

        // Paste the full response
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response, forType: .string)

        let paste = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)  // 'v'
        paste?.flags = .maskCommand
        paste?.post(tap: .cghidEventTap)
        let pasteUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        pasteUp?.flags = .maskCommand
        pasteUp?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(300))

        // 7. Now load the suggested reply into clipboard for Cmd+V
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestedReply, forType: .string)

        // 8. Select all the pasted text so user can see it
        let selectAll2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)
        selectAll2?.flags = .maskCommand
        selectAll2?.post(tap: .cghidEventTap)
        let selectAllUp2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: false)
        selectAllUp2?.flags = .maskCommand
        selectAllUp2?.post(tap: .cghidEventTap)

        setReplacement(ReplacementRecord(original: userRequest, replacement: suggestedReply, accessibilityCaptured: nil))
        status.show("\\\\ reply copied")
    }

    private func setReplacement(_ record: ReplacementRecord) {
        lastReplacement = record
        clearReplacementTask?.cancel()
        clearReplacementTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            lastReplacement = nil  // auto-clear sensitive text from memory
        }
    }

    private func handleWithAccessibility(trigger: String, mode: CleanMode, fullCapture: Bool = false) async throws -> Bool {
        do {
            let captured = try AccessibilityReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger, fullCapture: fullCapture)
            if captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                status.show("nothing to do"); return true
            }
            lastCapturedSummary = "\(captured.text.count) chars"
            startInlineLoading(in: captured, fallbackTrigger: trigger)
            let cleaned = try await TextCleaner.process(captured.text, mode: mode)
            stopInlineLoading()
            // Skip "already clean" check for non-clean modes (math, query, translate always change)
            if mode == .clean {
                guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    try AccessibilityReplacement.replaceCapturedText(captured, with: captured.text)
                    status.show("looks good"); return true
                }
            }
            try AccessibilityReplacement.replaceCapturedText(captured, with: cleaned)
            setReplacement(ReplacementRecord(original: captured.text, replacement: cleaned, accessibilityCaptured: captured))
            status.show("done")
            return true
        } catch is AccessibilityReplacementError { stopInlineLoading(); return false }
    }

    private func debugStatusText() -> String {
        "Monitor: \(monitorStatus)\nKeys seen: \(keypressCount)\nLast keys: \(lastTriggerDebug)\nLast rewrite: \(lastRewriteStatus)\nCapture: \(lastCapturedSummary)\nClean trigger: \(Settings.trigger)\nRewrite trigger: \(Settings.rewriteTrigger)\nProvider: \(Settings.provider.displayName)\nModel: \(Settings.model)\nLast app: \(lastTypingAppName ?? "unknown")\nAccessibility: \(AXIsProcessTrusted() ? "yes" : "no")"
    }

    // MARK: - Onboarding

    private func runOnboarding() {
        Task { @MainActor in
            do {
                await runOnboardingAsync()
            } catch {
                // If onboarding crashes, mark complete and move on
                Settings.onboardingComplete = true
                Settings.onboardingStep = 0
                onboarding.close()
                startMonitorWithRetry()
                buildMenu()
            }
        }
    }

    private func runOnboardingAsync() async {
        NSApp.activate(ignoringOtherApps: true)

        // Smart resume: check what's already done and skip ahead
        var step: Int
        let savedStep = Settings.onboardingStep
        if savedStep > 0 {
            // Resuming after restart. Check if permissions are now granted.
            let accOK = AXIsProcessTrusted()
            let hasKey = Settings.apiKey != nil
            if hasKey && accOK {
                step = 10 // skip to test
            } else if hasKey {
                step = 2 // have key but need permissions
            } else if accOK && savedStep >= 6 {
                step = 6 // have permissions, need provider/key
            } else {
                step = savedStep
            }
        } else {
            step = 1
        }
        var selectedProvider: AIProvider = Settings.provider

        while step > 0 {
            // Save progress at every step
            Settings.onboardingStep = step

            switch step {

            // 1. Welcome
            case 1:
                let r = await onboarding.show(step: .init(
                    title: "Type like a goblin. Send like a grown-up.",
                    body: """
                    Performance-enhancing drugs for your typing. Five triggers, all inline, works in any app.

                    //   Fix your text. Grammar, spelling, keeps your voice.
                    ??   Ask AI anything. Answer replaces your text.
                    ;;   Translate to another language.
                    ==   Math and conversions. Just the answer.
                    \\\\   Summarize a thread and draft a reply.

                    Open source. No telemetry. No database. No account.
                    """,
                    buttonTitles: ["Set it up", "Later"]
                ))
                if r != 0 { step = 0 } else { step = 2 }

            // 2. Accessibility permission
            case 2:
                let r = await onboarding.show(step: .init(
                    title: "Accessibility",
                    body: "typeROID needs this to read and replace text in your apps.\n\nClick below. Find typeROID in the list. Toggle it on.",
                    buttonTitles: ["Open Accessibility Settings", "Skip"],
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 1; continue }
                if r == 0 {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
                step = 3

            // 3. Confirm accessibility
            case 3:
                let permGranted = AXIsProcessTrusted()
                let r3 = await onboarding.show(step: .init(
                    title: permGranted ? "Accessibility: on" : "Toggle it on.",
                    body: permGranted
                        ? "Accessibility is on. You're good."
                        : "Toggle typeROID on in System Settings, then come back.\n\nIf you don't see it, quit and reopen the app first.",
                    buttonTitles: permGranted ? ["Continue"] : ["Check again", "Continue anyway"],
                    showBack: true
                ))
                if r3 == OnboardingWindow.backResult { step = 2; continue }
                if r3 == 0 && !permGranted { continue } // re-check
                step = 4

            // 4. Input Monitoring
            case 4:
                let r = await onboarding.show(step: .init(
                    title: "Input Monitoring",
                    body: "typeROID needs this to detect when you type // or ??.\n\nClick below to open Settings, then:\n1. Click the + button\n2. Go to Applications, find TypeRoid\n3. Click Open to add it\n4. Make sure the toggle is on",
                    buttonTitles: ["Open Input Monitoring", "Skip"],
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 2; continue }
                if r == 0 {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                step = 5

            // 5. Confirm input monitoring + quit/reopen notice
            case 5:
                let r5 = await onboarding.show(step: .init(
                    title: "You'll need to quit and reopen typeROID.",
                    body: "macOS won't detect your triggers until you quit and reopen the app. Not a full computer restart, just typeROID.\n\nFinish setup first. We saved your spot. When you reopen, you'll pick up right here.",
                    buttonTitles: ["Continue"],
                    showBack: true
                ))
                if r5 == OnboardingWindow.backResult { step = 4; continue }
                // Save progress so we can resume after restart
                Settings.onboardingStep = 6
                Settings.provider = selectedProvider
                step = 6

            // 6. Pick provider
            case 6:
                let r = await onboarding.show(step: .init(
                    title: "Pick your supplier.",
                    body: """
                    Pick whichever AI you have an API key for.

                    OpenAI: gpt-4.1-nano (fast, cheap)
                    Claude: haiku (premium quality)
                    Gemini: flash (free tier available)
                    Groq: llama 8b (free tier, instant)
                    """,
                    buttonTitles: ["OpenAI", "Claude", "Gemini", "Groq"],
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 4; continue }
                selectedProvider = switch r {
                    case 0: .openai
                    case 1: .anthropic
                    case 2: .google
                    default: .groq
                }
                // Warn about Google API key exposure
                if selectedProvider == .google {
                    let gr = await onboarding.show(step: .init(
                        title: "Quick note about Google.",
                        body: "Google's API puts your key in the URL. Your text is always encrypted, but the key itself could be visible on public wifi or corporate VPNs with network inspection.\n\nOpenAI, Claude, and Groq keep the key fully encrypted.\n\nGoogle is fine on a trusted network.",
                        buttonTitles: ["Use Google", "Pick another"],
                        showBack: true
                    ))
                    if gr == 1 || gr == OnboardingWindow.backResult { continue }
                }

                Settings.provider = selectedProvider
                Settings.model = selectedProvider.defaultModel
                step = 7

            // 7. API key instructions
            case 7:
                let keyURL: String
                let keyInstructions: String
                switch selectedProvider {
                case .openai:
                    keyURL = "https://platform.openai.com/api-keys"
                    keyInstructions = "Click 'Create new secret key'. Copy it."
                case .anthropic:
                    keyURL = "https://console.anthropic.com/settings/keys"
                    keyInstructions = "Click 'Create Key'. Copy it."
                case .google:
                    keyURL = "https://aistudio.google.com/apikey"
                    keyInstructions = "Click 'Create API key'. Copy it."
                case .groq:
                    keyURL = "https://console.groq.com/keys"
                    keyInstructions = "Click 'Create API Key'. Copy it."
                }
                let r = await onboarding.show(step: .init(
                    title: "Load your API key.",
                    body: """
                    \(keyInstructions)

                    Click "Get Key" to open \(selectedProvider.displayName)'s dashboard. Copy the key. Come back and click "Paste from Clipboard."

                    Stored in macOS Keychain. Never leaves your machine.
                    """,
                    buttonTitles: ["Get Key", "Paste from Clipboard", "Skip"],
                    showBack: true
                ))
                if r == 0 {
                    // Open the key URL in browser
                    NSWorkspace.shared.open(URL(string: keyURL)!)
                    // Wait for browser to open, then bring our window back
                    try? await Task.sleep(for: .seconds(2))
                    NSApp.activate(ignoringOtherApps: true)
                    let r2 = await onboarding.show(step: .init(
                        title: "Got it? Paste it.",
                        body: "Copy your \(selectedProvider.displayName) key to clipboard, then click below.",
                        buttonTitles: ["Paste from Clipboard", "Skip"],
                        showBack: true
                    ))
                    if r2 == OnboardingWindow.backResult { continue }
                    if r2 == 0 {
                        let clip2 = NSPasteboard.general.string(forType: .string)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !clip2.isEmpty { step = 8 } else { step = 9 }
                    } else { step = 11 }
                    continue
                }
                if r == OnboardingWindow.backResult { step = 6; continue }
                if r == 1 { // "Paste from Clipboard"
                    let clip = NSPasteboard.general.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !clip.isEmpty {
                        step = 8
                    } else {
                        step = 9
                    }
                } else { // "Skip"
                    step = 11
                }

            // 8. Keychain warning + save
            case 8:
                // Grab clipboard NOW before any dialogs change it
                let clipToSave = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                _ = await onboarding.show(step: .init(
                    title: "Heads up.",
                    body: "macOS may ask you to allow Keychain access. Hit \"Always Allow\" so it doesn't ask again.",
                    buttonTitles: ["Got it"],
                    showLogo: false
                ))
                Settings.setAPIKey(clipToSave, for: selectedProvider)
                let clip = clipToSave
                _ = await onboarding.show(step: .init(
                    title: "Key saved.",
                    body: "\(String(clip.prefix(8)))...\(String(clip.suffix(4)))\n\nStored securely in your Keychain.",
                    buttonTitles: ["Continue"]
                ))
                step = 10

            // 9. Empty clipboard
            case 9:
                let r9 = await onboarding.show(step: .init(
                    title: "Nothing on clipboard.",
                    body: "Copy your API key first, then come back. Or skip and add it later from the // menu.\n\nSettings > API Key",
                    buttonTitles: ["Try again", "Skip"],
                    showBack: true
                ))
                if r9 == OnboardingWindow.backResult { step = 7; continue }
                if r9 == 0 { step = 7; continue } // try again
                step = 11

            // 10. Test API (auto-send, show joke while waiting)
            case 10:
                if Settings.apiKey(for: selectedProvider) == nil {
                    step = 11; continue
                }
                onboarding.showLoading("injecting test substance into \(selectedProvider.displayName)...")
                let sample = "yojohn saww you lookmaxxing during the meting w our client, bettr off mewing on your own time bro lmaooo"
                do {
                    let result = try await TextCleaner.process(sample, mode: .clean)
                    _ = await onboarding.show(step: .init(
                        title: "Clean. Very clean.",
                        body: "Before:\n\(sample)\n\nAfter:\n\(result)",
                        buttonTitles: ["Nice"]
                    ))
                } catch {
                    _ = await onboarding.show(step: .init(
                        title: "That didn't hit.",
                        body: "\(error.localizedDescription)\n\nYou can fix your API key later from the // menu.",
                        buttonTitles: ["Continue"]
                    ))
                }
                step = 11

            // 11. Final screen
            case 11:
                _ = await onboarding.showDemo()
                Settings.onboardingStep = 0
                step = 0

            default:
                step = 0
            }
        }

        onboarding.close()
        Settings.onboardingComplete = true
        Settings.onboardingStep = 0
        NSApp.setActivationPolicy(.accessory) // hide from Dock now
        startMonitorWithRetry()
        buildMenu()

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
