import AppKit

/// Custom onboarding window with liquid shader background and animated branding.
@MainActor
final class OnboardingWindow {
    private var window: NSWindow?
    private var shaderView: LiquidShaderView?
    private var contentView: NSView?
    private var continuation: CheckedContinuation<Int, Never>?
    private var buttons: [NSButton] = []
    private var logoView: AnimatedLogoView?
    var mockThreadText: String = ""

    struct Step {
        let title: String
        let body: String
        let buttonTitles: [String]
        var showLogo: Bool = true
        var showBack: Bool = false
        var showTestField: Bool = false
    }

    static let backResult = -1

    func show(step: Step) async -> Int {
        let w: NSWindow
        if let existing = window {
            w = existing
        } else {
            w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
            w.level = .normal  // let user interact with other windows
            w.center()
            window = w

            let shader = LiquidShaderView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
            w.contentView?.addSubview(shader)
            shader.autoresizingMask = [.width, .height]
            shaderView = shader
            shader.startRendering()
        }

        // Clear old content
        contentView?.removeFromSuperview()
        logoView?.stopAnimating()
        logoView = nil
        buttons.removeAll()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        container.autoresizingMask = [.width, .height]

        var yOffset: CGFloat = 0

        // Animated // logo at top
        if step.showLogo {
            let logo = AnimatedLogoView(frame: NSRect(x: 40, y: 400, width: 480, height: 50))
            container.addSubview(logo)
            logo.startAnimating()
            logoView = logo
            yOffset = 60
        }

        // Title
        let titleLabel = NSTextField(labelWithString: step.title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 2
        titleLabel.preferredMaxLayoutWidth = 480
        titleLabel.frame = NSRect(x: 40, y: 400 - yOffset, width: 480, height: 50)
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        container.addSubview(titleLabel)

        // Fade in title
        titleLabel.alphaValue = 0
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.4
        titleLabel.animator().alphaValue = 1
        NSAnimationContext.endGrouping()

        // Body
        let bodyLabel = NSTextField(wrappingLabelWithString: step.body)
        bodyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.preferredMaxLayoutWidth = 480
        bodyLabel.frame = NSRect(x: 40, y: 75, width: 480, height: 310 - yOffset)
        bodyLabel.alignment = .left
        bodyLabel.drawsBackground = false
        bodyLabel.isBezeled = false
        container.addSubview(bodyLabel)

        // Fade in body
        bodyLabel.alphaValue = 0
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.5
        bodyLabel.animator().alphaValue = 1
        NSAnimationContext.endGrouping()

        // Buttons row - shrink sizing for many buttons
        let manyButtons = step.buttonTitles.count > 3
        var buttonX: CGFloat = manyButtons ? 30 : 40
        for (i, title) in step.buttonTitles.enumerated() {
            let btn = NSButton(title: title, target: self, action: #selector(buttonClicked(_:)))
            btn.tag = i
            btn.font = .monospacedSystemFont(ofSize: manyButtons ? 11 : 12, weight: i == 0 ? .bold : .regular)
            btn.sizeToFit()
            let btnWidth = max(btn.frame.width + 16, manyButtons ? 100 : 130)
            btn.frame = NSRect(x: buttonX, y: 28, width: btnWidth, height: 34)
            btn.bezelStyle = .rounded

            if i == 0 {
                btn.keyEquivalent = "\r"
                btn.contentTintColor = .white
            }

            // Fade in buttons
            btn.alphaValue = 0
            container.addSubview(btn)
            buttons.append(btn)
            buttonX += btnWidth + (manyButtons ? 6 : 12)

            let delay = 0.3 + Double(i) * 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.3
                btn.animator().alphaValue = 1
                NSAnimationContext.endGrouping()
            }
        }

        // Test field (for the final "try it" step)
        if step.showTestField {
            let testLabel = NSTextField(labelWithString: "Try it out. Type messy text below and hit //")
            testLabel.font = .systemFont(ofSize: 10, weight: .medium)
            testLabel.textColor = NSColor(red: 0.75, green: 1.0, blue: 0.0, alpha: 0.7)
            testLabel.frame = NSRect(x: 40, y: 92, width: 480, height: 14)
            testLabel.drawsBackground = false
            testLabel.isBezeled = false
            container.addSubview(testLabel)

            let testField = NSTextField(frame: NSRect(x: 40, y: 68, width: 400, height: 22))
            testField.placeholderString = "type somethign messy here then hit //"
            testField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            testField.isEditable = true
            testField.isSelectable = true
            testField.usesSingleLineMode = true
            testField.drawsBackground = true
            testField.backgroundColor = NSColor.black.withAlphaComponent(0.5)
            testField.textColor = NSColor(red: 0.75, green: 1.0, blue: 0.0, alpha: 1)
            testField.isBezeled = true
            testField.bezelStyle = .roundedBezel
            container.addSubview(testField)
        }

        // Back button (left side, subtle)
        if step.showBack {
            let backBtn = NSButton(title: "Back", target: self, action: #selector(backClicked))
            backBtn.font = .systemFont(ofSize: 11, weight: .regular)
            backBtn.isBordered = false
            backBtn.contentTintColor = NSColor.white.withAlphaComponent(0.4)
            backBtn.sizeToFit()
            backBtn.frame = NSRect(x: 460, y: 28, width: 60, height: 28)
            backBtn.alphaValue = 0
            container.addSubview(backBtn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.3
                backBtn.animator().alphaValue = 1
                NSAnimationContext.endGrouping()
            }
        }

        // Subtle "typeroid" watermark bottom right
        let watermark = NSTextField(labelWithString: "typeROID")
        watermark.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        watermark.textColor = NSColor.white.withAlphaComponent(0.15)
        watermark.frame = NSRect(x: 460, y: 6, width: 90, height: 14)
        watermark.alignment = .right
        watermark.drawsBackground = false
        watermark.isBezeled = false
        container.addSubview(watermark)

        w.contentView?.addSubview(container)
        contentView = container

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        if sender.tag == 99 {
            // Copy mock thread to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(mockThreadText, forType: .string)
            sender.title = "Copied!"
            return
        }
        continuation?.resume(returning: sender.tag)
        continuation = nil
    }

    @objc private func backClicked() {
        continuation?.resume(returning: OnboardingWindow.backResult)
        continuation = nil
    }

    func showLoading(_ text: String = "working on it...") {
        if let container = contentView {
            for subview in container.subviews {
                if let label = subview as? NSTextField,
                   label.frame.height > 100,
                   !label.isEditable {
                    label.stringValue = text
                    break
                }
            }
        }
    }

    func showDemo() async -> Int {
        let mockThread = "Sarah: the client wants to move launch to next week\nJohn: that's going to mess up QA\nSarah: can someone figure out if we can compress testing?\nMike: i can pull in testers but need budget approval\nSarah: @you thoughts?"
        self.mockThreadText = mockThread

        return await show(step: .init(
            title: "typeROID is fully injected.",
            body: """
            The enhancement is permanent. You're in the enhanced league now.

            Open any app and try:

            //   heyy john cn u movee the mtg//
            ??   whats 3pm EST in london??
            ;;   good morning how are you;;
            ==   15% of 340==
            \\\\   copy a thread first, then type \\\\

            Custom commands: drop a .txt in ~/.typeroid/commands/
            The filename is your trigger.

            typeROID lives in your menu bar. Look for //
            """,
            buttonTitles: ["Let's go"]
        ))
    }

    func _showDemoUnused() async -> Int {
        // Dead code, kept to preserve file structure
        let w: NSWindow
        if let existing = window {
            w = existing
        } else {
            w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = .clear
            w.level = .floating
            w.center()
            window = w

            let shader = LiquidShaderView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
            w.contentView?.addSubview(shader)
            shader.autoresizingMask = [.width, .height]
            shaderView = shader
            shader.startRendering()
        }

        // Clear old content
        contentView?.removeFromSuperview()
        logoView?.stopAnimating()
        logoView = nil
        buttons.removeAll()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        container.autoresizingMask = [.width, .height]

        // Animated logo at top
        let logo = AnimatedLogoView(frame: NSRect(x: 40, y: 400, width: 480, height: 50))
        container.addSubview(logo)
        logo.startAnimating()
        logoView = logo

        // Title
        let titleLabel = NSTextField(labelWithString: "Try each one.")
        titleLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 40, y: 340, width: 480, height: 30)
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.alphaValue = 0
        container.addSubview(titleLabel)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.4
        titleLabel.animator().alphaValue = 1
        NSAnimationContext.endGrouping()

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Type in any field below. End with the trigger to see it work live.")
        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        subtitleLabel.frame = NSRect(x: 40, y: 318, width: 480, height: 18)
        subtitleLabel.drawsBackground = false
        subtitleLabel.isBezeled = false
        container.addSubview(subtitleLabel)

        // Success message + cheat sheet
        let bodyText = """
        typeROID is fully injected. The enhancement is permanent.

        Open any app and try these:

          //   heyy john cn u movee the mtg//
          ??   whats 3pm EST in london??
          ;;   good morning how are you;;
          ==   15% of 340==
          \\\\   copy a thread, type \\\\

        You can also create custom commands.
        Drop a .txt file in ~/.typeroid/commands/
        The filename is the trigger. The content is the prompt.

        typeROID lives in your menu bar now. Look for the //
        """

        let bodyLabel = NSTextField(wrappingLabelWithString: bodyText)
        bodyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.preferredMaxLayoutWidth = 480
        bodyLabel.frame = NSRect(x: 40, y: 60, width: 480, height: 260)
        bodyLabel.drawsBackground = false
        bodyLabel.isBezeled = false
        container.addSubview(bodyLabel)

        bodyLabel.alphaValue = 0
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.5
        bodyLabel.animator().alphaValue = 1
        NSAnimationContext.endGrouping()

        // Mock thread to copy for \\ demo
        let mockThread = "Sarah: the client wants to move launch to next week\nJohn: that's going to mess up QA\nSarah: can someone figure out if we can compress testing?\nMike: i can pull in testers but need budget approval\nSarah: @you thoughts?"

        let copyBtn = NSButton(title: "Copy mock thread to try \\\\", target: nil, action: nil)
        copyBtn.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        copyBtn.sizeToFit()
        copyBtn.frame = NSRect(x: 40, y: 38, width: 250, height: 24)
        copyBtn.bezelStyle = .rounded
        copyBtn.target = nil
        copyBtn.action = nil
        // Use a block-based approach via the button's tag
        container.addSubview(copyBtn)

        // Store mock thread for the copy action
        copyBtn.target = self
        copyBtn.action = #selector(buttonClicked(_:))
        copyBtn.tag = 99  // special tag for copy

        // We'll handle tag 99 specially
        self.mockThreadText = mockThread

        // Done button
        let doneBtn = NSButton(title: "Let's go", target: self, action: #selector(buttonClicked(_:)))
        doneBtn.tag = 0
        doneBtn.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        doneBtn.sizeToFit()
        doneBtn.frame = NSRect(x: 40, y: 28, width: 130, height: 34)
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.contentTintColor = .white
        doneBtn.alphaValue = 0
        container.addSubview(doneBtn)
        buttons.append(doneBtn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.3
            doneBtn.animator().alphaValue = 1
            NSAnimationContext.endGrouping()
        }

        // Watermark
        let watermark = NSTextField(labelWithString: "typeROID")
        watermark.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        watermark.textColor = NSColor.white.withAlphaComponent(0.15)
        watermark.frame = NSRect(x: 460, y: 6, width: 90, height: 14)
        watermark.alignment = .right
        watermark.drawsBackground = false
        watermark.isBezeled = false
        container.addSubview(watermark)

        w.contentView?.addSubview(container)
        contentView = container

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func close() {
        logoView?.stopAnimating()
        shaderView?.stopRendering()
        window?.orderOut(nil)
        window = nil
        shaderView = nil
        logoView = nil
    }
}

// MARK: - Real Logo View (uses the actual typeROID logo asset)

@MainActor
final class AnimatedLogoView: NSView {
    private var imageLayer: CALayer?
    private var animating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLogo()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLogo() {
        let logoImage: NSImage?
        if let path = Bundle.main.path(forResource: "logo", ofType: "png") {
            logoImage = NSImage(contentsOfFile: path)
        } else {
            logoImage = nil
        }

        // Logo image, no container, no glow
        if let logoImage {
            let imgLayer = CALayer()
            imgLayer.frame = CGRect(x: 0, y: -2, width: 48, height: 52)
            imgLayer.contents = logoImage
            imgLayer.contentsGravity = .resizeAspect
            imgLayer.contentsScale = (NSScreen.main?.backingScaleFactor ?? 2)
            layer?.addSublayer(imgLayer)
            imageLayer = imgLayer
        } else {
            let text = CATextLayer()
            text.frame = CGRect(x: 0, y: 5, width: 48, height: 45)
            text.string = "//"
            text.font = NSFont.monospacedSystemFont(ofSize: 28, weight: .heavy)
            text.fontSize = 28
            text.foregroundColor = NSColor(red: 0.75, green: 1.0, blue: 0.0, alpha: 1).cgColor
            text.contentsScale = (NSScreen.main?.backingScaleFactor ?? 2)
            layer?.addSublayer(text)
            imageLayer = text
        }

        // "typeROID" wordmark
        let wordmark = CATextLayer()
        wordmark.frame = CGRect(x: 60, y: 15, width: 300, height: 28)
        wordmark.string = "typeROID"
        wordmark.font = NSFont.systemFont(ofSize: 22, weight: .black)
        wordmark.fontSize = 22
        wordmark.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        wordmark.contentsScale = (NSScreen.main?.backingScaleFactor ?? 2)
        layer?.addSublayer(wordmark)
    }

    func startAnimating() {
        guard !animating else { return }
        animating = true

        // Subtle breathe on logo
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1.0
        breathe.toValue = 1.03
        breathe.duration = 2.0
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer?.add(breathe, forKey: "breathe")
    }

    func stopAnimating() {
        animating = false
        imageLayer?.removeAllAnimations()
    }
}
