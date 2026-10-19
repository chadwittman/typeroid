import AppKit
import ApplicationServices
import Carbon
import Foundation
import TypeRoidCore

// MARK: - Menu bar status (dynamic title like <title>)

@MainActor
final class MenuBarStatus {
    private weak var statusItem: NSStatusItem?
    private let juice: JuiceBar
    private var resetTask: Task<Void, Never>?

    init(statusItem: NSStatusItem, juice: JuiceBar) {
        self.statusItem = statusItem
        self.juice = juice
    }

    func show(_ text: String, resetAfter: Double? = 2.0) {
        resetTask?.cancel()
        resetTask = nil
        statusItem?.button?.image = nil
        statusItem?.button?.title = text
        juice.show(status: text)

        if let delay = resetAfter {
            resetTask = Task { @MainActor in
                // A cancelled sleep must not fall through and clear the next
                // status. try? would swallow that cancellation and reset anyway.
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.reset()
            }
        }
    }

    func reset() {
        resetTask?.cancel()
        statusItem?.button?.title = ""
        statusItem?.button?.image = makeMenuBarIcon()
        juice.rest()
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
    private let juiceBar = JuiceBar()
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
    private var activeTask: Task<Void, Never>?
    private var cancelMenuItem: NSMenuItem?
    private var capturedBeforeProcess: AccessibilityCapturedText?
    private var fnGesture = FunctionDictationGesture()
    private var fnSignals = FunctionKeySignals()
    private var fnHoldTask: Task<Void, Never>?
    private var fnArmTask: Task<Void, Never>?
    private var fnSession: FnDictationSession?
    private var activityGeneration = 0
    private var didRequestKeyboardAccess = false
    private var didOpenInputMonitoring = false
    private var functionFlagDown = false
    private var functionFlagTimer: Timer?

    private var appIcon: NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        juiceBar.onPick = { [weak self] pick in
            self?.handlePill(pick)
        }
        juiceBar.onStop = { [weak self] in
            self?.stopFromPill()
        }
        juiceBar.start()
        startFunctionFlagPoll()
        GlobeKeyClaim.claim()

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

        let needsSetup = !Settings.onboardingComplete
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
            try? await Task.sleep(for: .seconds(1))
            requestKeyboardAccessIfNeeded()
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

    /// Ask once per launch. The preview (and a fresh install) never hears fn
    /// until Accessibility and Input Monitoring are on, and macOS only lists
    /// the app after something actually tries to tap the keyboard.
    private func requestKeyboardAccessIfNeeded() {
        guard !didRequestKeyboardAccess else { return }
        didRequestKeyboardAccess = true
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if !AXIsProcessTrusted() {
                status.show("fn needs Accessibility permission", resetAfter: 4)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func startMonitorWithRetry() {
        startMonitor()
        // If permissions aren't ready yet, keep checking every 3 seconds
        if monitorStatus != "active" {
            Task { @MainActor in
                for _ in 0..<40 {
                    try? await Task.sleep(for: .seconds(3))
                    if triggerMonitor?.isActive == true { return }
                    startMonitor()
                    if monitorStatus == "active" { return }
                }
            }
        }
    }

    /// The globe key often never arrives on the event tap. The fn modifier
    /// flag still changes, so poll it. The gesture ignores a repeated edge.
    private func startFunctionFlagPoll() {
        guard functionFlagTimer == nil else { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFunctionFlag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        functionFlagTimer = timer
    }

    private func pollFunctionFlag() {
        let down = CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
        guard down != functionFlagDown else { return }
        functionFlagDown = down
        let time = ProcessInfo.processInfo.systemUptime
        ingestFunction(down: down, at: time)
    }

    /// Poll and the event tap both report fn. Keep one edge, and drop a copy
    /// that arrives after a newer edge.
    private func ingestFunction(down: Bool, at time: TimeInterval) {
        guard let edge = fnSignals.edge(down: down, at: time) else { return }
        handleFunctionKey(edge)
    }

    private func startMonitor() {
        if triggerMonitor?.isActive == true { return }
        // Accessibility is required to paste. The keyboard tap is separate,
        // and fn should still be heard once Input Monitoring is on.
        triggerMonitor = TriggerMonitor(
            triggerProvider: { Settings.trigger },
            contextTriggerProvider: { Settings.rewriteTrigger },
            queryTriggerProvider: { Settings.contextTrigger },
            translateTriggerProvider: { Settings.translateTrigger },
            mathTriggerProvider: { Settings.mathTrigger },
            screenTriggerProvider: { Settings.screenTrigger },
            onFunctionKey: { [weak self] edge in
                Task { @MainActor in
                    guard let self else { return }
                    switch edge {
                    case .down(let time):
                        self.ingestFunction(down: true, at: time)
                    case .up(let time):
                        self.ingestFunction(down: false, at: time)
                    case .otherKey(let time):
                        guard !self.fnSignals.isStale(time) else { return }
                        self.handleFunctionKey(edge)
                    case .escape:
                        self.handleFunctionKey(edge)
                    }
                }
            },
            shouldSwallowGlobe: { [weak self] in self?.isEnabled ?? false },
            shouldSwallowEscape: { [weak self] in self?.fnSession != nil },
            onDebugEvent: { [weak self] event in Task { @MainActor in self?.handleDebugEvent(event) } }
        ) { [weak self] match in
            Task { @MainActor in
                self?.handleTrigger(
                    mode: match.mode,
                    typedBefore: match.textBefore,
                    typedDeleteCount: match.deleteCount,
                    typedBufferTruncated: match.bufferTruncated
                )
            }
        }
        triggerMonitor?.start()
        // Say it once. Repeating this every retry pinned the bar on ALLOW FN
        // and covered LISTENING while fn was already being seen.
        if triggerMonitor?.isActive != true, fnSession == nil, !didOpenInputMonitoring {
            didOpenInputMonitoring = true
            status.show("fn needs Input Monitoring", resetAfter: 4)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }
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
            status = MenuBarStatus(statusItem: statusItem, juice: juiceBar)
        }
        setStatusIcon()

        let menu = NSMenu()

        let allGood = AXIsProcessTrusted() && (triggerMonitor?.isActive ?? false) && Settings.apiKeyIsAvailable
        let statusText = allGood ? "typeROID \(Settings.currentVersion)  ● ready" : "typeROID \(Settings.currentVersion)  ○ setup needed"
        let statusItem2 = NSMenuItem(title: statusText, action: allGood ? nil : #selector(rerunOnboarding), keyEquivalent: "")
        if !allGood { statusItem2.target = self }
        menu.addItem(statusItem2)
        menu.addItem(NSMenuItem.separator())

        // Core actions
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.state = isEnabled ? .on : .off; toggle.target = self
        menu.addItem(toggle)

        let fnHint = NSMenuItem(title: "Fn: hold to talk, double-tap hands-free", action: nil, keyEquivalent: "")
        fnHint.isEnabled = false
        menu.addItem(fnHint)

        let undo = NSMenuItem(title: "Undo", action: #selector(undoLastRewrite), keyEquivalent: "z")
        undo.target = self
        menu.addItem(undo)

        let cancel = NSMenuItem(title: "Cancel", action: #selector(cancelActiveTask), keyEquivalent: ".")
        cancel.target = self
        cancel.isEnabled = activeTask != nil
        menu.addItem(cancel)
        cancelMenuItem = cancel

        let demoPad = NSMenuItem(title: "Open Demo Pad", action: #selector(openDemoPad), keyEquivalent: "")
        demoPad.target = self
        menu.addItem(demoPad)

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

        // Translation proof (back-translate to verify)
        let proofItem = NSMenuItem(title: ";; Translation proof", action: #selector(toggleBackTranslate), keyEquivalent: "")
        proofItem.target = self
        proofItem.state = Settings.backTranslateEnabled ? .on : .off
        settingsMenu.addItem(proofItem)

        // API Key (hidden for Ollama)
        if Settings.provider.requiresAPIKey {
            let apiKeyItem = NSMenuItem(title: "API Key...", action: #selector(setAPIKeyAction), keyEquivalent: "")
            apiKeyItem.target = self; settingsMenu.addItem(apiKeyItem)
        } else {
            let ollamaItem = NSMenuItem(title: "Ollama: local (no key needed)", action: nil, keyEquivalent: "")
            ollamaItem.isEnabled = false; settingsMenu.addItem(ollamaItem)
            let refreshItem = NSMenuItem(title: "Refresh Ollama Models", action: #selector(refreshOllamaModels), keyEquivalent: "")
            refreshItem.target = self; settingsMenu.addItem(refreshItem)
        }

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
        let mic = NSMenuItem(title: "Microphone Settings", action: #selector(openMicrophoneSettings), keyEquivalent: "")
        mic.target = self; settingsMenu.addItem(mic)
        let speech = NSMenuItem(title: "Speech Recognition Settings", action: #selector(openSpeechRecognitionSettings), keyEquivalent: "")
        speech.target = self; settingsMenu.addItem(speech)
        let screen = NSMenuItem(title: "Screen Recording Settings", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        screen.target = self; settingsMenu.addItem(screen)
        let dictation = NSMenuItem(title: "Keyboard Dictation Settings", action: #selector(openKeyboardDictationSettings), keyEquivalent: "")
        dictation.target = self; settingsMenu.addItem(dictation)

        settingsMenu.addItem(NSMenuItem.separator())

        // Diagnostics
        let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        diagnostics.submenu = buildDiagnosticsMenu()
        settingsMenu.addItem(diagnostics)

        let runSetup = NSMenuItem(title: "Run Setup Again", action: #selector(rerunOnboarding), keyEquivalent: "")
        runSetup.target = self; settingsMenu.addItem(runSetup)

        let uninstall = NSMenuItem(title: "Uninstall typeROID...", action: #selector(uninstallTypeRoid), keyEquivalent: "")
        uninstall.target = self; settingsMenu.addItem(uninstall)

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
        juiceBar.setBenched(!isEnabled)
        if !isEnabled {
            activityGeneration += 1
            activeTask?.cancel()
            activeTask = nil
            fnSession?.control.cancel()
            fnSession = nil
            fnGesture.reset()
            syncFunctionTimers()
            GlobeKeyClaim.release()
        } else {
            GlobeKeyClaim.claim()
        }
        setStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobeKeyClaim.release()
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

        if p == .ollama {
            Settings.provider = p
            Settings.model = Settings.cachedOllamaModels.first ?? p.defaultModel
            buildMenu()
            Task { @MainActor in
                status.show("checking Ollama...", resetAfter: nil)
                let running = await TextCleaner.isOllamaRunning()
                if running {
                    let models = await TextCleaner.fetchOllamaModels()
                    if !models.isEmpty {
                        Settings.cachedOllamaModels = models
                        Settings.model = models.first ?? p.defaultModel
                    }
                    status.show("Ollama ready")
                } else {
                    status.show("Ollama not running — start with: ollama serve")
                }
                buildMenu()
            }
            return
        }

        Settings.provider = p; Settings.model = p.defaultModel; buildMenu()
    }

    @objc private func refreshOllamaModels() {
        Task { @MainActor in
            status.show("fetching models...", resetAfter: nil)
            let running = await TextCleaner.isOllamaRunning()
            guard running else { status.show("Ollama not running — start with: ollama serve"); return }
            let models = await TextCleaner.fetchOllamaModels()
            if models.isEmpty { status.show("no models found — run: ollama pull llama3"); return }
            Settings.cachedOllamaModels = models
            if !models.contains(Settings.model) { Settings.model = models[0] }
            buildMenu()
            status.show("\(models.count) model\(models.count == 1 ? "" : "s") found")
        }
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
        NSWorkspace.shared.open(URL(string: "https://github.com/chadwittman/typeroid/releases/latest")!)
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
    @objc private func toggleBackTranslate() {
        Settings.backTranslateEnabled.toggle()
        buildMenu()
        status.show(Settings.backTranslateEnabled ? ";; proof on" : ";; proof off")
    }
    @objc private func setAPIKeyAction() {
        if let key = askForAPIKey(provider: Settings.provider) {
            Settings.setAPIKey(key, for: Settings.provider)
            status.show("Key saved!")
        }
    }
    @objc private func testCleanupAPI() {
        guard Settings.apiKeyIsAvailable else { status.show("No API key set"); return }
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
    @objc private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
    @objc private func openSpeechRecognitionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
    }
    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc private func openKeyboardDictationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
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

    @objc private func cancelActiveTask() {
        activityGeneration += 1
        activeTask?.cancel()
        activeTask = nil
        fnSession?.control.cancel()
        fnSession = nil
        fnGesture.reset()
        syncFunctionTimers()
        cancelMenuItem?.isEnabled = false
        loadingTimer?.invalidate()
        loadingTimer = nil
        if let captured = capturedBeforeProcess {
            try? AccessibilityReplacement.replaceCapturedText(captured, with: captured.text)
            capturedBeforeProcess = nil
        }
        status.show("Cancelled")
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
    @objc private func openDemoPad() {
        let url = ensureDemoPadFile(overwrite: true)
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func ensureDemoPadFile(overwrite: Bool) -> URL {
        let dir = NSHomeDirectory() + "/.typeroid"
        let path = dir + "/typeROID Demo.txt"
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if overwrite || !FileManager.default.fileExists(atPath: path) {
            try? demoPadText.write(toFile: path, atomically: true, encoding: .utf8)
        }

        return URL(fileURLWithPath: path)
    }

    private func revealDemoPadFile(overwrite: Bool) {
        let url = ensureDemoPadFile(overwrite: overwrite)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
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
    @objc private func uninstallTypeRoid() {
        let alert = makeAlert("Uninstall typeROID?",
        """
        This will quit typeROID and remove:

        - the app from Applications
        - API keys from Keychain
        - typeROID settings
        - ~/.typeroid demo, style, and command files
        - Accessibility and Input Monitoring permission entries
        """)
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("typeROID-uninstall.sh")
        do {
            try uninstallScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            let failed = makeAlert("Uninstall failed to start", error.localizedDescription)
            failed.addButton(withTitle: "OK")
            failed.runModal()
        }
    }

    // MARK: - Inline Loading

    private func startInlineLoading(in captured: AccessibilityCapturedText?, fallbackTrigger: String) {
        let msg = loadingMessages.randomElement() ?? "typeROIDing"
        dotCount = 1
        let inline = AccessibilityReplacement.allowsInlinePlaceholder() ? captured : nil

        if let inline {
            try? AccessibilityReplacement.replaceCapturedText(inline, with: "\(msg).")
        } else {
            status.show("\(fallbackTrigger) \(msg).", resetAfter: nil)
        }

        loadingTimer?.invalidate()
        loadingTimer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dotCount = (self.dotCount % 3) + 1
                let dots = String(repeating: ".", count: self.dotCount)
                if let inline {
                    try? AccessibilityReplacement.replaceCapturedText(inline, with: "\(msg)\(dots)")
                } else {
                    self.status.show("\(fallbackTrigger) \(msg)\(dots)", resetAfter: nil)
                }
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

    private var demoPadText: String {
        """
        typeROID demo pad
        ─────────────────────────────────────────

        Put your cursor at the END of any example line, then type the trigger.
        typeROID replaces what you typed. No copy-paste. No app switching.

        ─────────────────────────────────────────
        // — Fix your typing. Works everywhere.
        ─────────────────────────────────────────

        Place cursor after the text below, type //

        heyy john cn u movee the mtg to tmrw morning

        i wanted to circle back and touch base re the synergy we discussed re q4

        Fn dictation: hold fn, speak, release. Ums and ahs come out. The rest of what you said pastes at the cursor.
        Double-tap fn for hands-free. The next fn press stops and pastes.
        Escape cancels. A single short tap does not record.
        Typing .. or ,, does not start the microphone. // never starts voice.

        ─────────────────────────────────────────
        ?? — Ask AI anything. Answer replaces what you typed.
        ─────────────────────────────────────────

        Place cursor after the question, type ??

        whats 3pm EST in Tokyo

        how many weeks in a quarter

        ─────────────────────────────────────────
        ;; — Translate. Defaults to Spanish (change in Settings).
        ─────────────────────────────────────────

        Place cursor after the text, type ;;

        i'll be five minutes late, sorry

        ─────────────────────────────────────────
        == — Math and unit conversions. Returns just the answer.
        ─────────────────────────────────────────

        Place cursor after the expression, type ==

        15% of 340

        5ft 11in in cm

        ─────────────────────────────────────────
        \\\\ — Summarize a thread and draft a reply.
        ─────────────────────────────────────────

        1. Select and copy the thread below (Cmd+A on just that section, or manually)
        2. Click somewhere else in this file so your cursor is on a blank line
        3. Type \\\\

        The summary lands in the text field.
        Your suggested reply is copied to clipboard — hit Cmd+V to paste it anywhere.

        --- copy this thread ---
        Sarah: the client pushed launch to next week. not our call.
        John: that wrecks QA. we had 3 days blocked and now it's compressed into one.
        Sarah: can anyone figure out if we can actually test in one day?
        Mike: i can call in the testers but i need budget sign-off first
        Sarah: @you what do you think we should do here
        --- end thread ---

        ─────────────────────────────────────────
        >> — Ask with the screen. Prompt plus a full-screen shot.
        ─────────────────────────────────────────

        Place cursor after the prompt, type >>

        what is this error

        ─────────────────────────────────────────
        || — Rephrase. Rewrite the line like a person said it.
        ─────────────────────────────────────────

        Place cursor after the text, type ||

        Please do not hesitate to reach out should you require anything further

        ─────────────────────────────────────────
        Undo the last rewrite: typeROID menu > Undo
        Stuck? typeROID menu > Cancel
        ─────────────────────────────────────────
        """
    }

    private var uninstallScript: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail

        BUNDLE_ID="com.typeroid.app"
        KEYCHAIN_SERVICE="com.typeroid.app"
        HOME_DIR="$HOME"

        sleep 1
        pkill -x TypeRoid 2>/dev/null || true
        pkill -x typeROID 2>/dev/null || true

        remove_app_bundle() {
            local path="$1"
            [ -e "$path" ] || return 0

            rm -rf "$path" 2>/dev/null && return 0

            osascript \\
                -e 'on run argv' \\
                -e 'set appPath to item 1 of argv' \\
                -e 'do shell script "rm -rf " & quoted form of appPath with administrator privileges' \\
                -e 'end run' \\
                "$path"
        }

        remove_app_bundle "$HOME_DIR/Applications/TypeRoid.app"
        remove_app_bundle "$HOME_DIR/Applications/typeROID.app"
        remove_app_bundle "/Applications/TypeRoid.app"
        remove_app_bundle "/Applications/typeROID.app"

        defaults delete "$BUNDLE_ID" 2>/dev/null || true

        for account in openai_api_key anthropic_api_key google_api_key groq_api_key; do
            security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1 || true
        done

        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
        tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true

        rm -rf "$HOME_DIR/.typeroid"
        rm -f "$0"
        """
    }

    // MARK: - Function key dictation

    private func handleFunctionKey(_ edge: FunctionKeyEdge) {
        guard isEnabled || fnSession != nil else { return }
        let actions: [FunctionDictationAction]
        switch edge {
        case .down(let time):
            updateLastTypingApplication()
            actions = fnGesture.fnDown(at: time)
        case .up(let time):
            actions = fnGesture.fnUp(at: time)
        case .otherKey(let time):
            actions = fnGesture.otherKey(at: time)
        case .escape:
            guard fnSession != nil else { return }
            fnSession?.control.cancel()
            fnGesture.reset()
            syncFunctionTimers()
            status.show("Cancelled")
            return
        }
        applyFunctionActions(actions)
    }

    private func applyFunctionActions(_ actions: [FunctionDictationAction]) {
        for action in actions {
            switch action {
            case .begin(let mode):
                startFnSession(handsFree: mode == .handsFree)
            case .promoteToHandsFree:
                fnSession?.handsFree = true
                status.show("fn on. tap fn to stop", resetAfter: nil)
            case .end:
                let recording = fnSession?.didStartRecording == true
                fnSession?.control.stop()
                // The next press stops hands-free even when the mic is not
                // open yet. Leave the bar on "fn on" only while audio is
                // actually in flight, so that stop can still paste it.
                if !recording {
                    status.show("No speech was detected.")
                }
            case .discard:
                fnSession?.control.cancel()
                status.reset()
            case .cancel:
                fnSession?.control.cancel()
                status.show("Cancelled")
            case .hintHold:
                status.show("Hold fn to talk")
            }
        }
        syncFunctionTimers()
    }

    private func syncFunctionTimers() {
        fnHoldTask?.cancel()
        fnArmTask?.cancel()
        fnHoldTask = nil
        fnArmTask = nil

        switch fnGesture.phase {
        case .pressed(let downAt):
            let fireAt = downAt + fnGesture.holdStart
            fnHoldTask = Task { @MainActor in
                let delay = max(0, fireAt - ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.applyFunctionActions(self.fnGesture.holdElapsed(at: fireAt))
            }
        case .armingDoubleTap(let upAt, _):
            let fireAt = upAt + fnGesture.doubleTapGap
            fnArmTask = Task { @MainActor in
                let delay = max(0, fireAt - ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.applyFunctionActions(self.fnGesture.secondTapWindowElapsed(at: fireAt))
            }
        case .idle, .pushToTalk, .handsFree, .handsFreeHeld:
            break
        }
    }

    private func startFnSession(handsFree: Bool) {
        guard isEnabled else {
            fnGesture.reset()
            return
        }
        if activeTask != nil && fnSession == nil {
            fnGesture.reset()
            status.show("fn busy")
            return
        }
        guard fnSession == nil else { return }

        let session = FnDictationSession(handsFree: handsFree)
        fnSession = session
        cancelMenuItem?.isEnabled = true
        status.show(handsFree ? "fn on. tap fn to stop" : "fn listening...", resetAfter: nil)

        activityGeneration += 1
        let generation = activityGeneration
        activeTask = Task { @MainActor in
            defer {
                if self.activityGeneration == generation {
                    if self.fnSession === session {
                        self.fnSession = nil
                    }
                    self.activeTask = nil
                    self.cancelMenuItem?.isEnabled = false
                    switch self.fnGesture.phase {
                    case .pushToTalk, .handsFree, .handsFreeHeld:
                        self.fnGesture.reset()
                        self.syncFunctionTimers()
                    default:
                        break
                    }
                }
            }

            if let blocked = self.fnDictationBlockedReason() {
                session.control.cancel()
                self.fnGesture.reset()
                self.syncFunctionTimers()
                self.status.show(blocked)
                return
            }

            do {
                guard await self.voiceReadyForFnDictation() else {
                    if session.control.isStopRequested || session.control.isCancelRequested {
                        if !session.didStartRecording { self.status.show("No speech was detected.") }
                        return
                    }
                    session.control.cancel()
                    self.fnGesture.reset()
                    self.syncFunctionTimers()
                    self.status.show("fn needs microphone access")
                    return
                }
                if session.control.isStopRequested || session.control.isCancelRequested {
                    if session.control.isCancelRequested {
                        self.status.reset()
                    } else if !session.didStartRecording {
                        self.status.show("No speech was detected.")
                    }
                    return
                }

                session.didStartRecording = true
                let transcript = try await self.transcribeVoice(
                    trigger: "fn",
                    control: session.control,
                    stopOnSilence: false
                )
                if session.control.isCancelRequested || Task.isCancelled { return }

                self.status.show("fn cooking...", resetAfter: nil)
                let text = try await self.cleanedDictation(transcript)
                if session.control.isCancelRequested || Task.isCancelled { return }
                self.insertDictationText(text, original: transcript)
                self.status.show("fn done")
            } catch is CancellationError {
                return
            } catch {
                let message = self.voiceErrorMessage(error)
                if message == "Turn on Keyboard > Dictation" {
                    self.openKeyboardDictationSettings()
                }
                self.status.show(message)
            }
        }
    }

    private func fnDictationBlockedReason() -> String? {
        updateLastTypingApplication()
        guard isEnabled else { return "typeROID is off" }
        guard AXIsProcessTrusted() else { return "fn needs Accessibility permission" }
        if Settings.isExcluded(bundleID: lastTypingBundleID) {
            return "fn disabled in \(lastTypingAppName ?? "this app")"
        }
        if AccessibilityReplacement.focusedElementIsSecureTextEntry() {
            return "fn won't touch password fields"
        }
        if AccessibilityReplacement.focusedElementLooksLikeBrowserAddressBar(bundleID: lastTypingBundleID) {
            return "fn won't touch address bars"
        }
        return nil
    }

    private func voiceReadyForFnDictation() async -> Bool {
        if voiceReadyForCurrentTranscriber() { return true }
        await requestVoicePermissionsAndOpenSettingsIfNeeded()
        return voiceReadyForCurrentTranscriber()
    }

    private func cleanedDictation(_ transcript: String) async throws -> String {
        let spoken = TextCleaner.capitalizeSpoken(transcript)
        let canClean = Settings.apiKeyIsAvailable
        guard canClean else { return spoken }
        do {
            let cleaned = try await TextCleaner.process(transcript, mode: .dictation)
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? spoken : trimmed
        } catch let error as TextCleanerError {
            if case .apiError(let message) = error, message.hasPrefix("Blocked") {
                throw error
            }
            return spoken
        }
    }

    private func insertDictationText(_ text: String, original: String) {
        ClipboardReplacement.deleteCharactersBeforeCursorAndPaste(0, text: text)
        setReplacement(ReplacementRecord(original: original, replacement: text, accessibilityCaptured: nil))
    }

    // MARK: - Trigger

    private func handleDebugEvent(_ event: TriggerMonitorDebugEvent) {
        switch event {
        case .tapStarted:
            monitorStatus = "active"
            if fnSession == nil { status.reset() }
        case .tapCreationFailed:
            monitorStatus = "blocked"
        case .tapReenabled: monitorStatus = "re-enabled"
        case .key(let k): keypressCount += 1; lastTriggerDebug = k.isEmpty ? "empty" : k; updateLastTypingApplication(); setStatusIcon()
        case .triggerMatched: lastTriggerDebug = "// matched"
        case .triggerMatchedRewrite: lastTriggerDebug = "?? matched"
        case .triggerMatchedContext: lastTriggerDebug = "\\\\ matched"
        case .triggerMatchedTranslate: lastTriggerDebug = ";; matched"
        case .triggerMatchedVoice: lastTriggerDebug = "\(Settings.voiceTrigger) matched"
        case .triggerMatchedScreen: lastTriggerDebug = "\(Settings.screenTrigger) matched"
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

    private func handleTrigger(
        mode: CleanMode,
        typedBefore: String = "",
        typedDeleteCount: Int = 0,
        typedBufferTruncated: Bool = false
    ) {
        guard isEnabled else { return }
        if fnSession != nil {
            status.show("fn listening...")
            return
        }
        updateLastTypingApplication()

        // Compute label up front so blocked status messages can include it
        let label: String
        let verb: String
        switch mode {
        case .clean: label = "//"; verb = "fixing"
        case .query: label = "??"; verb = "asking"
        case .context: label = "\\\\"; verb = "reading"
        case .translate: label = ";;"; verb = "translating"
        case .math: label = "=="; verb = "calculating"
        case .rephrase: label = "||"; verb = "rephrasing"
        case .smartBrevity: label = Settings.voiceTrigger; verb = "briefing"
        case .dictation: label = "fn"; verb = "dictating"
        case .screen: label = Settings.screenTrigger; verb = "reading screen"
        case .custom(let name): label = name; verb = "running"
        }
        if case .dictation = mode { return }

        guard !Settings.isExcluded(bundleID: lastTypingBundleID) else {
            status.show("\(label) disabled in \(lastTypingAppName ?? "this app")"); return }
        guard AXIsProcessTrusted() else { status.show("\(label) needs Accessibility permission"); return }
        guard !AccessibilityReplacement.focusedElementIsSecureTextEntry() else {
            status.show("\(label) won't touch password fields"); return }
        if AccessibilityReplacement.focusedElementLooksLikeBrowserAddressBar(bundleID: lastTypingBundleID) {
            status.show("\(label) won't touch address bars"); return
        }
        guard Settings.apiKeyIsAvailable else { status.show("\(label) no API key — set one in the menu"); return }

        activityGeneration += 1
        let generation = activityGeneration
        activeTask = Task { @MainActor in
            defer {
                if self.activityGeneration == generation {
                    self.activeTask = nil
                    self.cancelMenuItem?.isEnabled = false
                }
            }
            cancelMenuItem?.isEnabled = true
            let loadingTimer: Timer?
            if mode == .smartBrevity {
                loadingTimer = nil
            } else {
                var msgIndex = 0
                let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        let msg = self.loadingMessages[msgIndex % self.loadingMessages.count]
                        self.status.show("\(label) \(msg)...", resetAfter: nil)
                        msgIndex += 1
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                loadingTimer = timer
            }
            let webSearchActive = (mode == .query) && Settings.webSearchEnabled
                && (Settings.provider == .openai || Settings.provider == .google)
            let initialStatus = webSearchActive ? "\(label) searching web..." : "\(label) \(verb)..."
            status.show(initialStatus, resetAfter: nil)

            defer { loadingTimer?.invalidate() }

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
                case .rephrase: trigger = Settings.rephraseTrigger
                case .smartBrevity: trigger = voiceBriefTriggerForFocusedElement()
                case .dictation: return
                case .screen: trigger = Settings.screenTrigger
                case .context: trigger = Settings.rewriteTrigger
                case .custom(let name): trigger = name
                }
                try await Task.sleep(for: .milliseconds(80))
                if mode == .smartBrevity {
                    let captured = try? AccessibilityReplacement.captureTriggerOnly(trigger: trigger)
                    try await handleVoiceBriefMode(captured: captured, fallbackTrigger: trigger)
                    return
                }
                if mode == .screen {
                    try await handleScreenMode(trigger: trigger)
                    return
                }
                if mode == .clean, try await handleCleanOrVoiceMode(trigger: trigger) { return }
                if mode == .clean, try await fixFromTypedBuffer(
                    typedBefore: typedBefore,
                    deleteCount: typedDeleteCount,
                    truncated: typedBufferTruncated,
                    trigger: trigger,
                    label: label
                ) { return }

                let fullCapture = false
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
                if mode == .query && !Settings.webSearchEnabled {
                    status.show("?? done  (enable Web Search in Settings for live results)")
                } else {
                    status.show("\(label) done")
                }
            } catch {
                let message = errorStatusMessage(error, label: label)
                lastRewriteStatus = String(message.prefix(60))
                refreshDebugMenuItems()
                status.show(message, resetAfter: 4)
            }
            // no status.reset() here - show() auto-resets after 2s
        }
    }

    private func handlePill(_ pick: JuicePick) {
        if pick == .quit {
            NSApp.terminate(nil)
            return
        }
        if pick == .talk {
            if fnSession != nil {
                fnSession?.control.stop()
            } else {
                startFnSession(handsFree: true)
            }
            return
        }

        let mode: CleanMode
        let label: String
        let verb: String
        switch pick {
        case .talk, .quit:
            return
        case .fix:
            mode = .clean; label = "//"; verb = "fixing"
        case .math:
            mode = .math; label = "=="; verb = "calculating"
        case .ask:
            mode = .query; label = "??"; verb = "asking"
        case .translate:
            mode = .translate; label = ";;"; verb = "translating"
        case .rephrase:
            mode = .rephrase; label = "||"; verb = "rephrasing"
        case .screen:
            mode = .screen; label = ">>"; verb = "reading screen"
        case .thread:
            mode = .context; label = "\\\\"; verb = "reading"
        }
        beginFocusedTool(mode: mode, label: label, verb: verb)
    }

    private func stopFromPill() {
        if fnSession != nil {
            fnSession?.control.stop()
            return
        }
        if activeTask != nil {
            cancelActiveTask()
        }
    }

    /// Runs a tool on the focused paragraph or selection. No trigger has to be typed.
    private func beginFocusedTool(mode: CleanMode, label: String, verb: String) {
        guard isEnabled else { return }
        if fnSession != nil {
            status.show("fn listening...")
            return
        }
        if activeTask != nil {
            status.show("\(label) busy")
            return
        }
        updateLastTypingApplication()
        guard !Settings.isExcluded(bundleID: lastTypingBundleID) else {
            status.show("\(label) disabled in \(lastTypingAppName ?? "this app")", resetAfter: 4)
            return
        }
        guard AXIsProcessTrusted() else {
            status.show("\(label) needs Accessibility permission", resetAfter: 4)
            return
        }
        guard !AccessibilityReplacement.focusedElementIsSecureTextEntry() else {
            status.show("\(label) won't touch password fields", resetAfter: 4)
            return
        }
        if AccessibilityReplacement.focusedElementLooksLikeBrowserAddressBar(bundleID: lastTypingBundleID) {
            status.show("\(label) won't touch address bars", resetAfter: 4)
            return
        }
        guard Settings.apiKeyIsAvailable else {
            status.show("\(label) no API key — set one in the menu", resetAfter: 4)
            return
        }

        activityGeneration += 1
        let generation = activityGeneration
        activeTask = Task { @MainActor in
            defer {
                if self.activityGeneration == generation {
                    self.activeTask = nil
                    self.cancelMenuItem?.isEnabled = false
                }
            }
            cancelMenuItem?.isEnabled = true
            status.show("\(label) \(verb)...", resetAfter: nil)
            do {
                switch mode {
                case .context:
                    try await self.handleContextFromFocus()
                case .screen:
                    try await self.handleScreenFromFocus()
                default:
                    let captured = try AccessibilityReplacement.captureFocusedMessage()
                    _ = try await self.processCapturedText(captured, mode: mode, label: label)
                }
            } catch AccessibilityReplacementError.emptyMessage {
                status.show("nothing to \(verb)")
            } catch {
                let message = self.errorStatusMessage(error, label: label)
                self.lastRewriteStatus = String(message.prefix(60))
                self.refreshDebugMenuItems()
                status.show(message, resetAfter: 4)
            }
        }
    }

    private func handleScreenFromFocus() async throws {
        let captured: AccessibilityCapturedText
        do {
            captured = try AccessibilityReplacement.captureFocusedMessage()
        } catch AccessibilityReplacementError.emptyMessage {
            status.show("ask something before >>")
            return
        }
        lastCapturedSummary = "\(captured.text.count) chars + screen"
        capturedBeforeProcess = captured
        status.show(">> reading screen...", resetAfter: nil)
        let screenshot = try FullScreenCapture.capturePNG()
        startInlineLoading(in: captured, fallbackTrigger: ">>")
        defer {
            capturedBeforeProcess = nil
            stopInlineLoading()
        }
        status.show(">> thinking with screen...", resetAfter: nil)
        let answer = try await TextCleaner.processWithScreenshot(captured.text, screenshotPNG: screenshot)
        try AccessibilityReplacement.replaceCapturedText(captured, with: answer)
        setReplacement(ReplacementRecord(original: captured.text, replacement: answer, accessibilityCaptured: captured))
        lastRewriteStatus = ">> ok"
        status.show(">> done")
    }

    private func handleContextFromFocus() async throws {
        let clipboardContext = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardContext.isEmpty else {
            status.show("\\\\ copy a thread first")
            return
        }

        let captured = try? AccessibilityReplacement.captureFocusedMessage()
        capturedBeforeProcess = captured
        if let captured {
            startInlineLoading(in: captured, fallbackTrigger: "\\\\")
        }
        status.show("\\\\ thinking...", resetAfter: nil)
        let raw = try await TextCleaner.processWithContext(captured?.text ?? "", threadContext: clipboardContext)
        stopInlineLoading()
        capturedBeforeProcess = nil

        let (summary, reply) = parseContextJSON(raw)
        let combined = reply.isEmpty ? summary : "\(summary)\n\n— Suggested reply —\n\(reply)"
        if let captured {
            try AccessibilityReplacement.replaceCapturedText(captured, with: combined, selectReplacement: true)
            setReplacement(ReplacementRecord(original: captured.text, replacement: combined, accessibilityCaptured: captured))
        } else if let cursor = try? AccessibilityReplacement.captureAtCursor() {
            try AccessibilityReplacement.replaceCapturedText(cursor, with: combined, selectReplacement: true)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reply.isEmpty ? raw : reply, forType: .string)
        lastRewriteStatus = "\\\\ ok"
        status.show("\\\\ reply in clipboard — ⌘V to paste")
    }

    private func errorStatusMessage(_ error: Error, label: String) -> String {
        if let screenError = error as? FullScreenCaptureError {
            openScreenRecordingSettings()
            return screenError.localizedDescription
        }
        if let cleanerError = error as? TextCleanerError {
            switch cleanerError {
            case .unsupportedProvider:
                return "\(label) needs OpenAI, Claude, or Gemini"
            case .missingAPIKey:
                if Settings.apiKeyIsAvailable {
                    return "\(label) needs keychain access"
                }
                return "\(label) no API key — set one in the menu"
            case .apiError(let message):
                return message
            case .invalidResponse:
                return "\(label) got a weird response"
            }
        }
        if let accessibilityError = error as? AccessibilityReplacementError {
            return accessibilityError.localizedDescription
        }
        if let clipboardError = error as? ClipboardReplacementError {
            return clipboardError.localizedDescription
        }
        return "\(label) failed"
    }

    /// Used when the field does not expose the `//` that was just typed.
    /// Backspace only the characters the monitor saw, then paste the fix.
    private func fixFromTypedBuffer(
        typedBefore: String,
        deleteCount: Int,
        truncated: Bool,
        trigger: String,
        label: String
    ) async throws -> Bool {
        let text = typedBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !truncated, !text.isEmpty, deleteCount >= trigger.count, deleteCount <= 2000 else { return false }

        status.show("\(label) fixing...", resetAfter: nil)
        let cleaned = try await TextCleaner.process(text, mode: .clean)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = trimmed.isEmpty || trimmed == text ? text : trimmed
        let output = AccessibilityReplacement.allowsInlinePlaceholder()
            ? replacement
            : AccessibilityReplacement.terminalReplacement(replacement)
        ClipboardReplacement.deleteCharactersBeforeCursorAndPaste(deleteCount, text: output)
        if replacement == text {
            status.show("looks good")
        } else {
            setReplacement(ReplacementRecord(original: text, replacement: output, accessibilityCaptured: nil))
            status.show("\(label) done")
        }
        return true
    }

    private func handleCleanOrVoiceMode(trigger: String) async throws -> Bool {
        do {
            let captured = try AccessibilityReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
            return try await processCapturedText(captured, mode: .clean, label: "//")
        } catch AccessibilityReplacementError.emptyMessage {
            status.show("nothing to fix")
            return true
        } catch is AccessibilityReplacementError {
            return false
        }
    }

    private func handleVoiceBriefMode(captured: AccessibilityCapturedText?, fallbackTrigger: String) async throws {
        capturedBeforeProcess = captured
        let deleteCount = voiceTriggerDeleteCount(captured: captured, fallbackTrigger: fallbackTrigger)
        status.show("listening...", resetAfter: nil)

        do {
            let transcript = try await transcribeVoice(trigger: fallbackTrigger)
            lastCapturedSummary = "\(transcript.count) voice chars"
            status.show("\(fallbackTrigger) cooking transcript...", resetAfter: nil)
            startInlineLoading(in: nil, fallbackTrigger: fallbackTrigger)
            defer { stopInlineLoading() }

            let brief = try await TextCleaner.process(transcript, mode: .smartBrevity)
            capturedBeforeProcess = nil

            ClipboardReplacement.deleteCharactersBeforeCursorAndPaste(deleteCount, text: brief)
            setReplacement(ReplacementRecord(original: transcript, replacement: brief, accessibilityCaptured: nil))
            status.show("\(fallbackTrigger) done")
        } catch {
            capturedBeforeProcess = nil
            let message = voiceErrorMessage(error)
            if message == "Turn on Keyboard > Dictation" {
                openKeyboardDictationSettings()
            }
            ClipboardReplacement.deleteCharactersBeforeCursorAndPaste(deleteCount, text: "")
            status.show(message)
        }
    }

    private func handleScreenMode(trigger: String) async throws {
        do {
            let captured = try AccessibilityReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
            if captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                status.show("ask something before \(trigger)")
                return
            }

            lastCapturedSummary = "\(captured.text.count) chars + screen"
            capturedBeforeProcess = captured
            status.show("\(trigger) reading screen...", resetAfter: nil)
            let screenshot = try FullScreenCapture.capturePNG()
            startInlineLoading(in: captured, fallbackTrigger: trigger)
            defer {
                capturedBeforeProcess = nil
                stopInlineLoading()
            }

            status.show("\(trigger) thinking with screen...", resetAfter: nil)
            let answer = try await TextCleaner.processWithScreenshot(captured.text, screenshotPNG: screenshot)
            try AccessibilityReplacement.replaceCapturedText(captured, with: answer)
            setReplacement(ReplacementRecord(original: captured.text, replacement: answer, accessibilityCaptured: captured))
            status.show("\(trigger) done")
        } catch is AccessibilityReplacementError {
            try await handleScreenModeWithClipboardFallback(trigger: trigger)
        }
    }

    private func handleScreenModeWithClipboardFallback(trigger: String) async throws {
        let captured = try await ClipboardReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
        if captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status.show("ask something before \(trigger)")
            return
        }

        lastCapturedSummary = "\(captured.text.count) chars + screen"
        status.show("\(trigger) reading screen...", resetAfter: nil)
        let screenshot = try FullScreenCapture.capturePNG()
        startInlineLoading(in: nil, fallbackTrigger: trigger)
        defer { stopInlineLoading() }

        status.show("\(trigger) thinking with screen...", resetAfter: nil)
        let answer = try await TextCleaner.processWithScreenshot(captured.text, screenshotPNG: screenshot)
        ClipboardReplacement.replaceCurrentSelection(with: answer)
        setReplacement(ReplacementRecord(original: captured.text, replacement: answer, accessibilityCaptured: nil))
        status.show("\(trigger) done")
    }

    private func transcribeVoice(
        trigger: String,
        control: DictationControl? = nil,
        stopOnSilence: Bool = true
    ) async throws -> String {
        let volumeDucker = OutputVolumeDucker()
        defer { volumeDucker.restore() }

        let onRecordingFinished: @MainActor () -> Void = { [weak self] in
            volumeDucker.restore()
            self?.status.show("\(trigger) transcribing...", resetAfter: nil)
        }

        let silenceAfter: TimeInterval = stopOnSilence ? 2.2 : .greatestFiniteMagnitude
        if WhisperDictation.isConfigured {
            return try await WhisperDictation().transcribe(
                silenceAfter: silenceAfter,
                control: control,
                onRecordingFinished: onRecordingFinished
            )
        }
        return try await VoiceDictation().transcribe(
            silenceAfter: silenceAfter,
            control: control,
            onRecordingFinished: onRecordingFinished
        )
    }

    private func voiceBriefTriggerForFocusedElement() -> String {
        if (try? AccessibilityReplacement.captureTriggerOnly(trigger: Settings.voiceTrigger)) != nil {
            return Settings.voiceTrigger
        }
        return Settings.voiceTrigger
    }

    private func voiceTriggerDeleteCount(captured: AccessibilityCapturedText?, fallbackTrigger: String) -> Int {
        guard let captured else { return fallbackTrigger.count }
        return captured.replaceCharacterCount
    }

    private func processCapturedText(_ captured: AccessibilityCapturedText, mode: CleanMode, label: String) async throws -> Bool {
        if captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status.show("nothing to do"); return true
        }
        lastCapturedSummary = "\(captured.text.count) chars"
        capturedBeforeProcess = captured
        startInlineLoading(in: captured, fallbackTrigger: label)
        let cleaned = try await TextCleaner.process(captured.text, mode: mode)
        capturedBeforeProcess = nil
        stopInlineLoading()
        if mode == .clean {
            guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                try AccessibilityReplacement.replaceCapturedText(captured, with: captured.text)
                status.show("looks good"); return true
            }
        }
        try AccessibilityReplacement.replaceCapturedText(captured, with: cleaned)
        setReplacement(ReplacementRecord(original: captured.text, replacement: cleaned, accessibilityCaptured: captured))
        lastRewriteStatus = "\(label) ok"
        refreshDebugMenuItems()
        status.show("\(label) done")
        return true
    }

    private func handleContextMode() async throws {
        let trigger = Settings.rewriteTrigger
        try await Task.sleep(for: .milliseconds(80))

        // Read clipboard first — this is the thread context
        let clipboardContext = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardContext.isEmpty else {
            status.show("\\\\ copy a thread first"); status.reset(); return
        }

        // Capture text before \\ using Accessibility — exactly like // does.
        // captured.text = optional user instruction typed before \\
        // If nothing was typed before \\, emptyMessage is thrown — handle gracefully.
        let captured: AccessibilityCapturedText
        do {
            captured = try AccessibilityReplacement.captureCurrentMessageBeforeTrigger(trigger: trigger)
        } catch AccessibilityReplacementError.emptyMessage {
            // Nothing typed before \\: delete trigger, capture cursor position, show inline loading
            for _ in 0..<trigger.count {
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: true)
                down?.post(tap: .cghidEventTap)
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: false)
                up?.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(80))
            let cursorCapture = try? AccessibilityReplacement.captureAtCursor()
            capturedBeforeProcess = cursorCapture
            startInlineLoading(in: cursorCapture, fallbackTrigger: trigger)
            let raw = try await TextCleaner.processWithContext("", threadContext: clipboardContext)
            stopInlineLoading()
            capturedBeforeProcess = nil
            let (summary, reply) = parseContextJSON(raw)
            let combined = reply.isEmpty ? summary : "\(summary)\n\n— Suggested reply —\n\(reply)"
            if let cursorCapture {
                try? AccessibilityReplacement.replaceCapturedText(cursorCapture, with: combined, selectReplacement: true)
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(reply.isEmpty ? raw : reply, forType: .string)
            status.show("\\\\ reply in clipboard — ⌘V to paste")
            return
        }

        // We have a captured range — use inline loading and replace exactly like //
        capturedBeforeProcess = captured
        startInlineLoading(in: captured, fallbackTrigger: trigger)
        status.show("\\\\ thinking...", resetAfter: nil)

        let raw = try await TextCleaner.processWithContext(captured.text, threadContext: clipboardContext)
        stopInlineLoading()
        capturedBeforeProcess = nil

        let (summary, reply) = parseContextJSON(raw)
        let combined = reply.isEmpty ? summary : "\(summary)\n\n— Suggested reply —\n\(reply)"

        try AccessibilityReplacement.replaceCapturedText(captured, with: combined, selectReplacement: true)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reply.isEmpty ? raw : reply, forType: .string)
        setReplacement(ReplacementRecord(original: captured.text, replacement: combined, accessibilityCaptured: captured))
        status.show("\\\\ reply in clipboard — ⌘V to paste")
    }

    private func parseContextJSON(_ raw: String) -> (summary: String, reply: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let summary = json["summary"], let reply = json["reply"] else {
            return (text, "")
        }
        return (summary, reply)
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
            capturedBeforeProcess = captured
            startInlineLoading(in: captured, fallbackTrigger: trigger)
            let cleaned = try await TextCleaner.process(captured.text, mode: mode)
            capturedBeforeProcess = nil
            stopInlineLoading()
            // Skip "already clean" check for non-clean modes (math, query, translate always change)
            if mode == .clean {
                guard cleaned.trimmingCharacters(in: .whitespacesAndNewlines) != captured.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    try AccessibilityReplacement.replaceCapturedText(captured, with: captured.text)
                    status.show("looks good"); return true
                }
            }
            // Translation proof: back-translate so the user can verify quality
            var final = cleaned
            if mode == .translate && Settings.backTranslateEnabled {
                status.show(";; proofing...", resetAfter: nil)
                let backLang = Settings.language
                let proof = (try? await TextCleaner.process(cleaned, mode: .translate, translateTarget: backLang)) ?? ""
                if !proof.isEmpty {
                    final = "\(cleaned)\n\n↩ proof: \(proof)"
                }
            }
            try AccessibilityReplacement.replaceCapturedText(captured, with: final)
            setReplacement(ReplacementRecord(original: captured.text, replacement: final, accessibilityCaptured: captured))
            status.show(mode == .translate && Settings.backTranslateEnabled ? ";; done + proofed" : "done")
            return true
        } catch is AccessibilityReplacementError { stopInlineLoading(); return false }
    }

    private func debugStatusText() -> String {
        let webSearchStatus: String = {
            guard Settings.webSearchEnabled else { return "off" }
            let p = Settings.provider
            if p == .openai || p == .google { return "on (\(p.displayName))" }
            return "on but \(p.displayName) doesn't support it — switch to OpenAI or Google"
        }()
        return "Monitor: \(monitorStatus)\nKeys seen: \(keypressCount)\nLast keys: \(lastTriggerDebug)\nLast rewrite: \(lastRewriteStatus)\nCapture: \(lastCapturedSummary)\nClean trigger: \(Settings.trigger)\nScreen trigger: \(Settings.screenTrigger)\nRewrite trigger: \(Settings.rewriteTrigger)\nProvider: \(Settings.provider.displayName)\nModel (//;;==\\\\>>): \(Settings.model)\nModel (??): \(Settings.provider.queryModel)\nWeb search (??): \(webSearchStatus)\nLanguage: \(Settings.language)\nLast app: \(lastTypingAppName ?? "unknown")\nAccessibility: \(AXIsProcessTrusted() ? "yes" : "no")"
    }

    private func requestVoicePermissionsAndOpenSettingsIfNeeded() async {
        _ = await VoiceDictation.requestMicrophonePermission()
        _ = await VoiceDictation.requestSpeechPermission()

        if !VoiceDictation.microphoneAuthorized {
            openMicrophoneSettings()
        } else if !WhisperDictation.isConfigured && !VoiceDictation.speechAuthorized {
            openSpeechRecognitionSettings()
        } else if !WhisperDictation.isConfigured && !VoiceDictation.systemDictationEnabled {
            openKeyboardDictationSettings()
        }
    }

    private func voiceReadyForCurrentTranscriber() -> Bool {
        if WhisperDictation.isConfigured {
            return VoiceDictation.microphoneAuthorized
        }
        return VoiceDictation.voiceReady
    }

    private func screenRecordingReady() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func requestScreenRecordingPermissionAndOpenSettingsIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        if !CGPreflightScreenCaptureAccess() {
            openScreenRecordingSettings()
        }
    }

    private func voiceErrorMessage(_ error: Error) -> String {
        if case VoiceDictationError.recognizerUnavailable = error {
            return "Turn on Keyboard > Dictation"
        }
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("dictation") || message.localizedCaseInsensitiveContains("siri") {
            return "Turn on Keyboard > Dictation"
        }
        return message
    }

    // MARK: - Onboarding

    private func runOnboarding() {
        Task { @MainActor in
            do {
                try await runOnboardingAsync()
            } catch is OnboardingClosed {
                finishOnboarding(markComplete: true)
            } catch {
                // If onboarding crashes, mark complete and move on
                finishOnboarding(markComplete: true)
            }
        }
    }

    private func finishOnboarding(markComplete: Bool) {
        onboarding.close()
        if markComplete {
            Settings.onboardingComplete = true
            Settings.onboardingStep = 0
        }
        NSApp.setActivationPolicy(.accessory)
        startMonitorWithRetry()
        buildMenu()
    }

    private func present(step: OnboardingWindow.Step) async throws -> Int {
        let result = await onboarding.show(step: step)
        if result == OnboardingWindow.closeResult { throw OnboardingClosed() }
        return result
    }

    private func presentDemo() async throws -> Int {
        let result = await onboarding.showDemo()
        if result == OnboardingWindow.closeResult { throw OnboardingClosed() }
        return result
    }

    private func inputMonitoringGranted() -> Bool {
        let probe = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let probe { CFMachPortInvalidate(probe) }
        return probe != nil
    }

    private func runOnboardingAsync() async throws {
        NSApp.activate(ignoringOtherApps: true)

        // Smart resume: check what's already done and skip ahead
        var step: Int
        let savedStep = Settings.onboardingStep
        if savedStep > 0 {
            // Resuming after restart. Check if permissions are now granted.
            let accOK = AXIsProcessTrusted()
            let hasKey = Settings.apiKeyIsAvailable
            if hasKey && accOK {
                step = voiceReadyForCurrentTranscriber() ? 12 : 6 // voice permissions, then test
            } else if hasKey {
                step = 2 // have key but need permissions
            } else if accOK && savedStep >= 7 {
                step = 7 // have permissions, need provider/key
            } else {
                step = savedStep
            }
        } else {
            step = 1
        }
        var selectedProvider: AIProvider = Settings.provider
        var finishedCycle = false

        while step > 0 {
            // Save progress at every step
            Settings.onboardingStep = step

            switch step {

            // 1. Welcome
            case 1:
                let r = try await present(step: .init(
                    title: "Hold fn. It types what you said.",
                    body: """
                    One check per step. Each one has a single job.

                    Hold fn, talk, release. What you said pastes. Ums come out. The words stay yours. Double-tap fn for hands-free. The next fn press stops and pastes.

                    The typed stack waits until the permissions are real.
                    """,
                    buttonTitles: ["Set it up", "Later"],
                    kicker: "01  Welcome"
                ))
                if r != 0 { step = 0 } else { step = 2 }

            // 2. Accessibility permission
            case 2:
                let r = try await present(step: .init(
                    title: "Let typeROID touch the text.",
                    body: "This step turns on Accessibility.\n\nOpen Settings. Find typeROID. Toggle it on. The next screen checks that it stuck.",
                    buttonTitles: ["Open Accessibility Settings", "Skip"],
                    kicker: "02  Accessibility",
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
                let r3 = try await present(step: .init(
                    title: permGranted ? "Accessibility is on." : "The toggle is still off.",
                    body: permGranted
                        ? "typeROID can read and replace text. Next check is the keyboard."
                        : "Flip typeROID on in System Settings, then check again.\n\nIf it is missing from the list, quit and reopen the app, then come back to this step.",
                    buttonTitles: permGranted ? ["Continue"] : ["Check again", "Continue anyway"],
                    kicker: "03  Accessibility check",
                    showBack: true
                ))
                if r3 == OnboardingWindow.backResult { step = 2; continue }
                if r3 == 0 && !permGranted { continue } // re-check
                step = 4

            // 4. Input Monitoring
            case 4:
                // The probe adds typeROID to Input Monitoring when the toggle is still off.
                let keysLive = inputMonitoringGranted()
                let r = try await present(step: .init(
                    title: keysLive ? "The keyboard is already open." : "Turn on the keyboard.",
                    body: keysLive
                        ? "Input Monitoring is on. typeROID can hear fn and the two-character triggers. The next screen confirms it."
                        : "This step lets typeROID hear fn and the triggers.\n\nmacOS added typeROID to Input Monitoring. Turn the toggle on.\n\nIf it is missing, click +, then Applications, then typeROID, then Open.",
                    buttonTitles: keysLive ? ["Continue"] : ["Open Input Monitoring", "Skip"],
                    kicker: "04  Input Monitoring",
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 3; continue }
                if r == 0 && !keysLive {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                step = 5

            // 5. Confirm the tap, and relaunch only when macOS still needs it
            case 5:
                let keysLive = inputMonitoringGranted()
                let r5 = try await present(step: .init(
                    title: keysLive ? "Keys are live." : "Quit and reopen typeROID.",
                    body: keysLive
                        ? "Input Monitoring is on and the tap came up. No relaunch. Next is the microphone."
                        : "macOS applies Input Monitoring the next time typeROID launches. The Mac stays up.\n\nQuit and reopen, and setup resumes at the microphone. Continue anyway if you want to finish the other checks first. This step is saved.",
                    buttonTitles: keysLive ? ["Continue"] : ["Quit and reopen", "Continue anyway"],
                    kicker: "05  Relaunch check",
                    showBack: true
                ))
                if r5 == OnboardingWindow.backResult { step = 4; continue }
                Settings.onboardingStep = 6
                Settings.provider = selectedProvider
                if r5 == 0 && !keysLive {
                    onboarding.close()
                    NSApp.terminate(nil)
                    return
                }
                step = 6

            // 6. Voice permissions
            case 6:
                let hasVoicePermissions = voiceReadyForCurrentTranscriber()
                let usingWhisper = WhisperDictation.isConfigured
                let body = hasVoicePermissions
                    ? "The microphone is authorized. The next screen confirms dictation is ready."
                    : usingWhisper
                        ? "This step allows the microphone. Dictation uses local Whisper. Audio stays on this Mac.\n\nApprove the prompt. If macOS already blocked it, typeROID opens Settings."
                        : "This step allows the microphone and Speech Recognition.\n\nApprove the prompts. Dictation also has to be on in Keyboard settings. If macOS already blocked one, typeROID opens Settings."
                let r = try await present(step: .init(
                    title: hasVoicePermissions ? "Microphone is on." : "Allow the microphone.",
                    body: body,
                    buttonTitles: hasVoicePermissions ? ["Continue"] : ["Set Up Voice", "Skip"],
                    kicker: "06  Microphone",
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 5; continue }
                if !hasVoicePermissions {
                    if r == 0 {
                        await requestVoicePermissionsAndOpenSettingsIfNeeded()
                        continue
                    }
                }
                step = 7

            // 7. Confirm voice permissions
            case 7:
                let microphoneOK = VoiceDictation.microphoneAuthorized
                let usingWhisper = WhisperDictation.isConfigured
                let speechOK = usingWhisper || VoiceDictation.speechAuthorized
                let dictationOK = usingWhisper || VoiceDictation.systemDictationEnabled
                let voiceOK = voiceReadyForCurrentTranscriber()
                let missing = [
                    microphoneOK ? nil : "Microphone",
                    speechOK ? nil : "Speech Recognition",
                    dictationOK ? nil : "Keyboard Dictation"
                ].compactMap { $0 }.joined(separator: " and ")
                let r = try await present(step: .init(
                    title: voiceOK ? "Voice is ready." : "Voice is still off.",
                    body: voiceOK
                        ? "Hold fn, talk, release. Ums come out. Sentences start with a capital, and so does I. The words stay yours.\n\nDouble-tap fn for hands-free. The next fn press stops and pastes. Escape cancels. A short tap does not record.\n\nTyping does not start the microphone. // never starts voice."
                        : "\(missing) still needs a toggle.\n\nTurn typeROID on, then check again.",
                    buttonTitles: voiceOK ? ["Continue"] : ["Check again", "Open Settings", "Skip"],
                    kicker: "07  Voice check",
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 6; continue }
                if voiceOK {
                    step = 8
                    continue
                }
                if r == 0 { continue }
                if r == 1 {
                    if !microphoneOK {
                        openMicrophoneSettings()
                    } else if !speechOK {
                        openSpeechRecognitionSettings()
                    } else {
                        openKeyboardDictationSettings()
                    }
                    continue
                }
                step = 8

            // 8. Pick provider
            case 8:
                let r = try await present(step: .init(
                    title: "Pick your supplier.",
                    body: """
                    This step picks the compound for the typed stack. // ?? ;; == >> \\\\ || use it.

                    fn does not. It transcribes on this Mac.

                    OpenAI is fast and cheap. Claude is the premium dose. Gemini and Groq have free tiers. Ollama stays on the machine, no key.
                    """,
                    buttonTitles: ["OpenAI", "Claude", "Gemini", "Groq", "Ollama"],
                    kicker: "08  Supplier",
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 7; continue }
                selectedProvider = switch r {
                    case 0: .openai
                    case 1: .anthropic
                    case 2: .google
                    case 3: .groq
                    default: .ollama
                }
                // Warn about Google API key exposure
                if selectedProvider == .google {
                    let gr = try await present(step: .init(
                        title: "Google puts the key in the URL.",
                        body: "The text is encrypted. The key itself can show up on public wifi or a network that inspects traffic.\n\nOpenAI, Claude, and Groq keep the key in the header. Google is fine on a network you trust.",
                        buttonTitles: ["Use Google", "Pick another"],
                        kicker: "08  Supplier",
                        showBack: true
                    ))
                    if gr == 1 || gr == OnboardingWindow.backResult { continue }
                }

                Settings.provider = selectedProvider
                Settings.model = selectedProvider.defaultModel
                step = 9

            // 9. API key instructions (or Ollama health check)
            case 9:
                if selectedProvider == .ollama {
                    // Ollama: no key needed — check if it's running
                    onboarding.showLoading("checking for Ollama...")
                    let running = await TextCleaner.isOllamaRunning()
                    if running {
                        let models = await TextCleaner.fetchOllamaModels()
                        if !models.isEmpty {
                            Settings.cachedOllamaModels = models
                            Settings.model = models[0]
                        }
                        let modelList = models.isEmpty ? "No models found yet." : "Models found:\n" + models.prefix(5).joined(separator: "\n")
                        let ro = try await present(step: .init(
                            title: "Ollama is up.",
                            body: "\(modelList)\n\nNo API key. The compound stays on this Mac. Next is a test dose.",
                            buttonTitles: ["Continue"],
                            kicker: "09  Local compound",
                            showBack: true
                        ))
                        if ro == OnboardingWindow.backResult { step = 8; continue }
                        step = 12
                    } else {
                        let ro = try await present(step: .init(
                            title: "Ollama is quiet.",
                            body: "Nothing answered at localhost:11434.\n\nbrew install ollama\nollama serve\nollama pull llama3\n\nTry again once it is up, or continue and start it later.",
                            buttonTitles: ["Continue anyway", "Try again"],
                            kicker: "09  Local compound",
                            showBack: true
                        ))
                        if ro == OnboardingWindow.backResult { step = 8; continue }
                        if ro == 1 { continue } // try again
                        step = 12
                    }
                    continue
                }

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
                case .ollama:
                    keyURL = ""; keyInstructions = "" // handled above
                }
                let r = try await present(step: .init(
                    title: "Load the \(selectedProvider.displayName) key.",
                    body: """
                    \(keyInstructions)

                    Get Key opens the dashboard. Copy the key. Come back. Paste from Clipboard.

                    It goes into Keychain. typeROID reads it on this Mac.
                    """,
                    buttonTitles: ["Get Key", "Paste from Clipboard", "Skip"],
                    kicker: "09  API key",
                    showBack: true
                ))
                if r == 0 {
                    // Open the key URL in browser
                    NSWorkspace.shared.open(URL(string: keyURL)!)
                    // Wait for browser to open, then bring our window back
                    try? await Task.sleep(for: .seconds(2))
                    NSApp.activate(ignoringOtherApps: true)
                    let r2 = try await present(step: .init(
                        title: "Paste the key.",
                        body: "Copy the \(selectedProvider.displayName) key, then paste it from the clipboard.",
                        buttonTitles: ["Paste from Clipboard", "Skip"],
                        kicker: "09  API key",
                        showBack: true
                    ))
                    if r2 == OnboardingWindow.backResult { continue }
                    if r2 == 0 {
                        let clip2 = NSPasteboard.general.string(forType: .string)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !clip2.isEmpty { step = 10 } else { step = 11 }
                    } else { step = 13 }
                    continue
                }
                if r == OnboardingWindow.backResult { step = 8; continue }
                if r == 1 { // "Paste from Clipboard"
                    let clip = NSPasteboard.general.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !clip.isEmpty {
                        step = 10
                    } else {
                        step = 11
                    }
                } else { // "Skip"
                    step = 13
                }

            // 10. Keychain warning + save
            case 10:
                // Grab clipboard NOW before any dialogs change it
                let clipToSave = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                _ = try await present(step: .init(
                    title: "Allow Keychain.",
                    body: "macOS may ask to use the key. Choose Always Allow so the next shortcut does not stop to ask.",
                    buttonTitles: ["Got it"],
                    kicker: "10  Keychain",
                    showLogo: false
                ))
                Settings.setAPIKey(clipToSave, for: selectedProvider)
                let clip = clipToSave
                let mask = clip.count >= 12 ? "\(clip.prefix(4))…\(clip.suffix(4))" : "Saved."
                _ = try await present(step: .init(
                    title: "Key is in.",
                    body: "\(mask)\n\nStored in Keychain for \(selectedProvider.displayName). Next is a test dose.",
                    buttonTitles: ["Continue"],
                    kicker: "10  Keychain"
                ))
                step = 12

            // 11. Empty clipboard
            case 11:
                let r9 = try await present(step: .init(
                    title: "Clipboard is empty.",
                    body: "Copy the API key, then try again. Or skip and add it later from the menu, under API Key.",
                    buttonTitles: ["Try again", "Skip"],
                    kicker: "11  Clipboard",
                    showBack: true
                ))
                if r9 == OnboardingWindow.backResult { step = 9; continue }
                if r9 == 0 { step = 9; continue } // try again
                step = 13

            // 12. Test API (auto-send, show joke while waiting)
            case 12:
                if Settings.apiKeyMissing(for: selectedProvider) {
                    step = 13; continue
                }
                onboarding.showLoading("injecting test substance into \(selectedProvider.displayName)...")
                let sample = "yojohn saww you lookmaxxing during the meting w our client, bettr off mewing on your own time bro lmaooo"
                do {
                    let result = try await TextCleaner.process(sample, mode: .clean)
                    _ = try await present(step: .init(
                        title: "The compound hit.",
                        body: """
                        \(selectedProvider.displayName) answered.

                        In:
                        \(sample)

                        Out:
                        \(result)
                        """,
                        buttonTitles: ["Nice"],
                        kicker: "12  Test dose"
                    ))
                } catch is OnboardingClosed {
                    throw OnboardingClosed()
                } catch {
                    _ = try await present(step: .init(
                        title: "The dose missed.",
                        body: "\(error.localizedDescription)\n\nFix the key later from the menu, under API Key.",
                        buttonTitles: ["Continue"],
                        kicker: "12  Test dose"
                    ))
                }
                step = 13

            // 13. Screen Recording
            case 13:
                let screenOK = screenRecordingReady()
                let r = try await present(step: .init(
                    title: screenOK ? "Screen context is on." : "Screen context is optional.",
                    body: screenOK
                        ? "Type a prompt, then >>. typeROID sends the prompt and a full-screen shot. // and fn never take a screenshot."
                        : "This step is only for >>.\n\nType a prompt, then >>. typeROID sends that prompt plus a full-screen screenshot. // and fn never take a screenshot.\n\nSkip if you do not want Screen Recording.",
                    buttonTitles: screenOK ? ["Continue"] : ["Set Up Screen Context", "Skip"],
                    kicker: "13  Screen",
                    showBack: true
                ))
                if r == OnboardingWindow.backResult { step = 12; continue }
                if !screenOK && r == 0 {
                    requestScreenRecordingPermissionAndOpenSettingsIfNeeded()
                    continue
                }
                step = 14

            // 14. Final screen
            case 14:
                _ = try await presentDemo()
                finishedCycle = true
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
        if finishedCycle { openDemoPad() }

    }
}

private struct OnboardingClosed: Error {}

private final class FnDictationSession {
    let control = DictationControl()
    var handsFree: Bool
    /// True once audio capture has been asked to start. A stop before this
    /// has nothing to paste.
    var didStartRecording = false

    init(handsFree: Bool) {
        self.handsFree = handsFree
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
