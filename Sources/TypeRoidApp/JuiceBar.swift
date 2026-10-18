import AppKit
import CoreText
import TypeRoidCore

enum JuicePick: Equatable {
    case talk
    case fix
    case math
    case ask
    case translate
    case rephrase
    case screen
    case thread
}

/// A small capsule just above the Dock.
/// At rest it holds a tablet. Talking melts it. Done, it squares up.
/// A click slides the tablet aside and shows the tools.
@MainActor
final class JuiceBar {
    private var panel: NSPanel?
    private var pill: JuicePill?
    private var timer: Timer?
    private var benched = false
    private var cue: JuiceCue = .rest
    private var phase: Double = 0
    private var moodStarted = Date()
    private var displayedWidth: CGFloat = JuiceCue.rest.panelWidth
    private var lastFrame: NSRect = .zero
    private var trayOpen = false

    var onPick: ((JuicePick) -> Void)?
    var onStop: (() -> Void)?

    func start() {
        guard panel == nil else { return }
        let size = NSSize(width: displayedWidth, height: JuiceCue.panelHeight)
        let pill = JuicePill(frame: NSRect(origin: .zero, size: size))
        pill.onClick = { [weak self] point, bounds in
            self?.clicked(at: point, in: bounds)
        }
        let panel = JuicePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        pill.autoresizingMask = [.width, .height]
        panel.contentView = pill
        panel.orderFrontRegardless()
        self.panel = panel
        self.pill = pill
        place()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func show(status: String) {
        start()
        closeTray()
        setCue(JuiceCue.from(status: status))
    }

    func rest() {
        start()
        setCue(benched ? .benched : .rest)
    }

    func setBenched(_ benched: Bool) {
        self.benched = benched
        if benched { closeTray() }
        rest()
    }

    private func setCue(_ cue: JuiceCue) {
        guard cue != self.cue else { return }
        let alreadyMelted = self.cue.lively && cue.lively
        self.cue = cue
        moodStarted = Date()
        pill?.cue = cue
        pill?.arrivedDissolved = alreadyMelted
        if cue.lively || cue == .gains || cue == .spit {
            closeTray()
        }
        place()
    }

    private func closeTray() {
        guard trayOpen else { return }
        trayOpen = false
        pill?.trayOpen = false
    }

    private func clicked(at point: CGPoint, in bounds: CGRect) {
        if cue == .juicing || cue == .openSet || cue == .cooking {
            onStop?()
            return
        }
        guard !benched else { return }
        let capsule = bounds.insetBy(dx: 3, dy: 4)
        let layout = JuiceLayout.layout(in: capsule, open: trayOpen)
        if trayOpen, let pick = layout.pick(at: point) {
            closeTray()
            pill?.needsDisplay = true
            onPick?(pick)
            return
        }
        trayOpen.toggle()
        pill?.trayOpen = trayOpen
        pill?.needsDisplay = true
    }

    private func tick() {
        let lively = cue.lively
        phase += lively ? 0.16 : 0.04
        let target = trayOpen ? JuiceLayout.trayWidth : cue.panelWidth
        if abs(displayedWidth - target) < 0.4 {
            displayedWidth = target
        } else {
            displayedWidth += (target - displayedWidth) * 0.18
        }
        pill?.phase = phase
        pill?.sinceMood = Date().timeIntervalSince(moodStarted)
        pill?.needsDisplay = true
        place()
    }

    private func place() {
        guard let panel else { return }
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let vis = screen.visibleFrame
        let width = displayedWidth.rounded()
        let height = JuiceCue.panelHeight
        let frame = NSRect(
            x: (vis.midX - width / 2).rounded(),
            y: (vis.minY + 8).rounded(),
            width: width,
            height: height
        )
        guard frame != lastFrame else { return }
        lastFrame = frame
        panel.setFrame(frame, display: true)
    }
}

private final class JuicePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct JuiceLayout {
    static let trayWidth: CGFloat = 204

    var lozenge: CGRect
    var marks: [(JuicePick, String, CGRect)]

    func pick(at point: CGPoint) -> JuicePick? {
        marks.first { $0.2.contains(point) }?.0
    }

    static func layout(in capsule: CGRect, open: Bool) -> JuiceLayout {
        if !open {
            let width: CGFloat = 15
            let height: CGFloat = 7
            return JuiceLayout(
                lozenge: CGRect(
                    x: capsule.midX - width / 2,
                    y: capsule.midY - height / 2,
                    width: width,
                    height: height
                ),
                marks: []
            )
        }

        let lozenge = CGRect(x: capsule.minX + 8, y: capsule.midY - 3.5, width: 15, height: 7)
        let marks: [(JuicePick, String)] = [
            (.talk, "fn"),
            (.fix, "//"),
            (.math, "=="),
            (.ask, "??"),
            (.translate, ";;"),
            (.rephrase, "||"),
            (.screen, ">>"),
            (.thread, "\\\\"),
        ]
        let start = lozenge.maxX + 6
        let end = capsule.maxX - 4
        let slot = max(12, (end - start) / CGFloat(marks.count))
        let rects = marks.enumerated().map { index, mark in
            (
                mark.0,
                mark.1,
                CGRect(
                    x: start + CGFloat(index) * slot,
                    y: capsule.minY,
                    width: slot,
                    height: capsule.height
                )
            )
        }
        return JuiceLayout(lozenge: lozenge, marks: rects)
    }
}

private extension JuiceCue {
    static let panelHeight: CGFloat = 28

    /// The tablet sits in a small capsule. It only widens while it's melted.
    var panelWidth: CGFloat {
        switch self {
        case .juicing, .openSet, .cooking: 92
        default: 64
        }
    }

    var acid: NSColor {
        NSColor(srgbRed: 191.0 / 255.0, green: 1, blue: 0, alpha: 1)
    }

    var lively: Bool { self == .juicing || self == .openSet || self == .cooking }
}

@MainActor
private final class JuicePill: NSView {
    var cue: JuiceCue = .rest
    var phase: Double = 0
    var sinceMood: TimeInterval = 0
    var arrivedDissolved = false
    var trayOpen = false
    var onClick: ((CGPoint, CGRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { return nil }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil), bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let shrug: CGFloat = cue == .spit && sinceMood < 0.42
            ? CGFloat(sin(min(1, sinceMood / 0.42) * .pi)) * 2
            : 0
        context.saveGState()
        context.translateBy(x: shrug, y: 0)

        let capsule = bounds.insetBy(dx: 3, dy: 4)
        let radius = capsule.height / 2
        let path = CGPath(roundedRect: capsule, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        let glow = cue.lively ? cue.acid.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.2)
        context.setShadow(offset: .zero, blur: cue.lively ? 5 : 3, color: glow.cgColor)
        context.addPath(path)
        context.setFillColor(fillColor().cgColor)
        context.fillPath()
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(strokeColor().cgColor)
        context.setLineWidth(1)
        context.strokePath()

        drawMark(in: capsule, context: context)
        context.restoreGState()
    }

    private func fillColor() -> NSColor {
        NSColor.black.withAlphaComponent(cue == .benched ? 0.4 : 0.8)
    }

    private func strokeColor() -> NSColor {
        if cue == .benched { return cue.acid.withAlphaComponent(0.2) }
        if cue.lively || trayOpen { return cue.acid.withAlphaComponent(0.42) }
        if cue == .gains { return cue.acid.withAlphaComponent(0.5) }
        return cue.acid.withAlphaComponent(0.32)
    }

    private func drawMark(in capsule: NSRect, context: CGContext) {
        let layout = JuiceLayout.layout(in: capsule, open: trayOpen && !cue.lively)
        switch cue {
        case .juicing, .openSet, .cooking:
            drawDissolved(in: capsule, context: context)
        case .gains:
            drawReformed(in: capsule, context: context)
        case .rest, .benched, .access, .hint, .spit:
            drawLozenge(layout.lozenge, context: context)
            if trayOpen {
                for mark in layout.marks {
                    drawGlyph(mark.1, in: mark.2, context: context)
                }
            }
        }
    }

    private func drawLozenge(_ rect: CGRect, context: CGContext) {
        let lean: CGFloat = cue == .hint
            ? CGFloat(sin(min(1, sinceMood / 0.48) * .pi)) * 2.2
            : 0
        var shifted = rect
        shifted.origin.x += lean
        fillRounded(shifted, radius: shifted.height / 2, color: cue.acid.withAlphaComponent(lozengeAlpha()), context: context)
    }

    private func lozengeAlpha() -> CGFloat {
        switch cue {
        case .benched:
            return 0.28
        case .access:
            return sin(phase * 1.3) > 0 ? 0.88 : 0.22
        case .spit:
            return 0.5
        default:
            return 0.72 + 0.1 * CGFloat(0.5 + 0.5 * sin(phase * 0.45))
        }
    }

    private func drawGlyph(_ text: String, in rect: CGRect, context: CGContext) {
        let font = CTFontCreateWithName("Menlo" as CFString, 9, nil)
        guard let raw = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0) else { return }
        let range = CFRange(location: 0, length: text.utf16.count)
        CFAttributedStringReplaceString(raw, CFRange(location: 0, length: 0), text as CFString)
        CFAttributedStringSetAttribute(raw, range, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(raw, range, kCTForegroundColorAttributeName, cue.acid.withAlphaComponent(0.9).cgColor)
        let line = CTLineCreateWithAttributedString(raw)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: rect.midX - width / 2,
            y: rect.midY - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawDissolved(in capsule: NSRect, context: CGContext) {
        let melt: CGFloat = arrivedDissolved ? 1 : CGFloat(min(1, sinceMood / 0.4))
        if melt < 1 {
            let width = 15 + 18 * melt
            let height = 7 * (1 - melt) + 2 * melt
            let rect = CGRect(
                x: capsule.midX - width / 2,
                y: capsule.midY - height / 2,
                width: width,
                height: height
            )
            fillRounded(rect, radius: height / 2, color: cue.acid.withAlphaComponent(0.75 * (1 - melt)), context: context)
        }

        let count = 9
        let barWidth: CGFloat = 2
        let gap: CGFloat = 2.2
        let cluster = CGFloat(count) * (barWidth + gap) - gap
        let origin = capsule.midX - cluster / 2
        let maxH = capsule.height - 8
        let lateIndex = count - 2
        for index in 0..<count {
            let height = dissolvedHeight(index: index, lateIndex: lateIndex, maxH: maxH)
            let x = origin + CGFloat(index) * (barWidth + gap)
            let rect = CGRect(x: x, y: capsule.midY - height / 2, width: barWidth, height: height)
            fillRounded(rect, radius: 1, color: cue.acid.withAlphaComponent(0.88 * melt), context: context)
        }
    }

    private func dissolvedHeight(index: Int, lateIndex: Int, maxH: CGFloat) -> CGFloat {
        if cue == .cooking {
            let catchup = max(0, 1 - sinceMood / 0.9)
            if index == lateIndex { return min(maxH, 3 + 4.5 * catchup) }
            return 2.6
        }
        var clock = phase
        if index == lateIndex { clock -= cue == .openSet ? 0.9 : 0.5 }
        let snap = pow(abs(sin(clock * 1.15 + Double(index) * 0.5)), 0.75)
        return min(maxH, 2.4 + (maxH - 2.4) * snap * 0.72)
    }

    private func drawReformed(in capsule: NSRect, context: CGContext) {
        let form = CGFloat(min(1, sinceMood / 0.36))
        let count = 7
        let gap: CGFloat = 4
        let cluster = CGFloat(count - 1) * gap
        let origin = capsule.midX - cluster / 2
        if form < 1 {
            for index in 0..<count {
                let home = origin + CGFloat(index) * gap
                let x = home + (capsule.midX - home) * form
                let height = 2.4 * (1 - form) + 1
                let rect = CGRect(x: x, y: capsule.midY - height / 2, width: 2, height: height)
                fillRounded(rect, radius: 1, color: cue.acid.withAlphaComponent(0.7 * (1 - form)), context: context)
            }
        }
        let side: CGFloat = 8
        let square = CGRect(
            x: capsule.midX - side / 2,
            y: capsule.midY - side / 2,
            width: side,
            height: side
        )
        fillRounded(square, radius: 1.5, color: cue.acid.withAlphaComponent(0.92 * form), context: context)
    }

    private func fillRounded(_ rect: CGRect, radius: CGFloat, color: NSColor, context: CGContext) {
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }
}
