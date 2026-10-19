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
    private var bodyLabel: NSTextField?
    private let closeProxy = OnboardingCloseProxy()
    var mockThreadText: String = ""

    struct Step {
        let title: String
        let body: String
        let buttonTitles: [String]
        var kicker: String? = nil
        var showLogo: Bool = true
        var showBack: Bool = false
        var showTestField: Bool = false
    }

    static let backResult = -1
    static let closeResult = -2
    static let acid = NSColor(srgbRed: 191.0 / 255.0, green: 1, blue: 0, alpha: 1)

    private let windowSize = NSSize(width: 560, height: 600)

    func show(step: Step) async -> Int {
        let w = prepareWindow()

        contentView?.removeFromSuperview()
        logoView?.stopAnimating()
        logoView = nil
        buttons.removeAll()
        bodyLabel = nil

        let width = windowSize.width
        let height = windowSize.height
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.autoresizingMask = [.width, .height]

        let margin: CGFloat = 40
        let contentWidth = width - margin * 2
        var cursor = height - 28

        if step.showLogo {
            let logo = AnimatedLogoView(frame: NSRect(x: margin, y: cursor - 50, width: contentWidth, height: 50))
            container.addSubview(logo)
            logo.startAnimating()
            logoView = logo
            cursor -= 62
        }

        if let kicker = step.kicker {
            let kickerLabel = NSTextField(labelWithString: kicker.uppercased())
            kickerLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
            kickerLabel.textColor = Self.acid
            kickerLabel.frame = NSRect(x: margin, y: cursor - 16, width: contentWidth, height: 16)
            kickerLabel.drawsBackground = false
            kickerLabel.isBezeled = false
            container.addSubview(kickerLabel)
            cursor -= 24
        }

        let titleFont = NSFont.systemFont(ofSize: 24, weight: .heavy)
        let titleHeight = min(78, textHeight(step.title, font: titleFont, width: contentWidth) + 4)
        let titleLabel = NSTextField(wrappingLabelWithString: step.title)
        titleLabel.font = titleFont
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 2
        titleLabel.preferredMaxLayoutWidth = contentWidth
        titleLabel.frame = NSRect(x: margin, y: cursor - titleHeight, width: contentWidth, height: titleHeight)
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        container.addSubview(titleLabel)
        cursor -= titleHeight + 12

        let buttonTop: CGFloat = 72
        let testReserve: CGFloat = step.showTestField ? 64 : 0
        let bodyBottom = buttonTop + testReserve
        let bodyHeight = max(80, cursor - bodyBottom)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let measuredBody = textHeight(step.body, font: bodyFont, width: contentWidth - 4) + 8

        let scroll = NSScrollView(frame: NSRect(x: margin, y: bodyBottom, width: contentWidth, height: bodyHeight))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = measuredBody > bodyHeight + 1
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let doc = TopAlignedDocument(frame: NSRect(x: 0, y: 0, width: contentWidth, height: max(measuredBody, bodyHeight)))
        let body = NSTextField(wrappingLabelWithString: step.body)
        body.font = bodyFont
        body.textColor = NSColor.white.withAlphaComponent(0.78)
        body.maximumNumberOfLines = 0
        body.preferredMaxLayoutWidth = contentWidth - 4
        body.frame = NSRect(x: 0, y: 0, width: contentWidth - 4, height: measuredBody)
        body.isSelectable = true
        body.drawsBackground = false
        body.isBezeled = false
        doc.addSubview(body)
        scroll.documentView = doc
        container.addSubview(scroll)
        bodyLabel = body

        if step.showTestField {
            let testLabel = NSTextField(labelWithString: "Type a messy line, then //")
            testLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            testLabel.textColor = Self.acid.withAlphaComponent(0.8)
            testLabel.frame = NSRect(x: margin, y: buttonTop + 28, width: contentWidth, height: 16)
            testLabel.drawsBackground = false
            testLabel.isBezeled = false
            container.addSubview(testLabel)

            let testField = NSTextField(frame: NSRect(x: margin, y: buttonTop, width: contentWidth, height: 24))
            testField.placeholderString = "heyy can we move the mtg"
            testField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            testField.isEditable = true
            testField.isSelectable = true
            testField.usesSingleLineMode = true
            testField.drawsBackground = true
            testField.backgroundColor = NSColor.black.withAlphaComponent(0.5)
            testField.textColor = Self.acid
            testField.isBezeled = true
            testField.bezelStyle = .roundedBezel
            container.addSubview(testField)
        }

        let manyButtons = step.buttonTitles.count > 3
        let buttonSpacing: CGFloat = manyButtons ? 8 : 12
        let rowWidth = contentWidth
        let maxButtonWidth = (rowWidth - (buttonSpacing * CGFloat(max(step.buttonTitles.count - 1, 0)))) / CGFloat(max(step.buttonTitles.count, 1))
        var buttonX = margin
        for (i, title) in step.buttonTitles.enumerated() {
            let btn = NSButton(title: title, target: self, action: #selector(buttonClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .rounded
            btn.font = .monospacedSystemFont(ofSize: manyButtons ? 11 : 13, weight: i == 0 ? .bold : .medium)
            btn.sizeToFit()
            let naturalWidth = btn.frame.width + (manyButtons ? 12 : 22)
            let btnWidth = manyButtons ? maxButtonWidth : max(naturalWidth, 120)
            btn.frame = NSRect(x: buttonX, y: 28, width: btnWidth, height: 34)
            if i == 0 {
                btn.keyEquivalent = "\r"
                btn.bezelColor = Self.acid
                btn.contentTintColor = .black
            } else {
                btn.contentTintColor = .white
            }
            btn.alphaValue = 0
            container.addSubview(btn)
            buttons.append(btn)
            buttonX += btnWidth + buttonSpacing

            let delay = 0.15 + Double(i) * 0.06
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0.25
                btn.animator().alphaValue = 1
                NSAnimationContext.endGrouping()
            }
        }

        if step.showBack {
            let backBtn = NSButton(title: "Back", target: self, action: #selector(backClicked))
            backBtn.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            backBtn.isBordered = false
            backBtn.contentTintColor = NSColor.white.withAlphaComponent(0.55)
            backBtn.sizeToFit()
            backBtn.frame = NSRect(x: width - margin - backBtn.frame.width, y: 6, width: backBtn.frame.width + 4, height: 18)
            container.addSubview(backBtn)
        }

        w.contentView?.addSubview(container)
        contentView = container
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    private func prepareWindow() -> NSWindow {
        if let existing = window { return existing }
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
        w.level = .normal
        closeProxy.onClose = { [weak self] in
            guard let self, let continuation = self.continuation else { return }
            self.continuation = nil
            continuation.resume(returning: Self.closeResult)
        }
        w.delegate = closeProxy
        w.center()
        window = w

        let shader = LiquidShaderView(frame: NSRect(origin: .zero, size: windowSize))
        w.contentView?.addSubview(shader)
        shader.autoresizingMask = [.width, .height]
        shaderView = shader
        shader.startRendering()
        return w
    }

    private func textHeight(_ string: String, font: NSFont, width: CGFloat) -> CGFloat {
        let box = (string as NSString).boundingRect(
            with: NSSize(width: width, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(box.height)
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
        bodyLabel?.stringValue = text
    }

    func showDemo() async -> Int {
        let mockThread = "Sarah: the client wants to move launch to next week\nJohn: that's going to mess up QA\nSarah: can someone figure out if we can compress testing?\nMike: i can pull in testers but need budget approval\nSarah: @you thoughts?"
        self.mockThreadText = mockThread

        return await show(step: .init(
            title: "You're on cycle.",
            body: """
            The menu bar is home. A practice file opens next.

            Hold fn, talk, release. Ums come out. The words stay yours.
            Double-tap fn for hands-free. The next fn press stops and pastes. Escape cancels. A short tap does not record.

            ,,   same dictation. Talk, then pause.
            //   fix a draft. Never starts voice.
            >>   prompt plus the screen.
            ??   ask.
            ;;   translate.
            ==   math.
            \\\\   summarize a copied thread.
            ||   rephrase.

            Put the cursor at the end of a line in the practice file. Type the trigger.
            """,
            buttonTitles: ["Open the practice file"],
            kicker: "14  On cycle"
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
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        shaderView = nil
        logoView = nil
        bodyLabel = nil
    }
}

@MainActor
private final class OnboardingCloseProxy: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return true
    }
}

private final class TopAlignedDocument: NSView {
    override var isFlipped: Bool { true }
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
