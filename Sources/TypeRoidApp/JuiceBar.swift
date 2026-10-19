import AppKit
import CoreText
import TypeRoidCore

/// Recent microphone levels for the dock pill. The audio thread pushes.
/// The pill reads a copy while it draws. Silence stays a flat line.
final class MicWave: @unchecked Sendable {
    static let shared = MicWave()

    private let lock = NSLock()
    private var levels: [Float] = []
    private var active = false
    private let capacity = 42

    func begin() {
        lock.lock()
        if !active {
            levels.removeAll(keepingCapacity: true)
            active = true
        }
        lock.unlock()
    }

    func end() {
        lock.lock()
        active = false
        levels.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func push(linear: Float) {
        guard linear.isFinite else { return }
        let sample = min(1, max(0, linear))
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        if levels.count >= capacity {
            levels.removeFirst(levels.count - capacity + 1)
        }
        levels.append(sample)
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return levels
    }
}

enum JuicePick: Equatable {
    case talk
    case fix
    case math
    case ask
    case translate
    case rephrase
    case screen
    case thread
    case quit
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
        let cue = JuiceCue.from(status: status)
        switch cue {
        case .juicing, .openSet:
            MicWave.shared.begin()
        default:
            MicWave.shared.end()
        }
        setCue(cue)
    }

    func rest() {
        start()
        MicWave.shared.end()
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
        if cue == .juicing || cue == .openSet || cue.isCooking {
            onStop?()
            return
        }
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
    static let trayWidth: CGFloat = 236

    var lozenge: CGRect
    var marks: [(JuicePick, String, CGRect)]
    var close: CGRect?

    func pick(at point: CGPoint) -> JuicePick? {
        if let close, close.insetBy(dx: -6, dy: -8).contains(point) { return .quit }
        return marks.first { $0.2.contains(point) }?.0
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
                marks: [],
                close: nil
            )
        }

        let lozenge = CGRect(x: capsule.minX + 8, y: capsule.midY - 3.5, width: 15, height: 7)
        let button: CGFloat = 16
        let close = CGRect(
            x: capsule.maxX - 5 - button,
            y: capsule.midY - button / 2,
            width: button,
            height: button
        )
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
        let end = close.minX - 10
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
        return JuiceLayout(lozenge: lozenge, marks: rects, close: close)
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

    var lively: Bool {
        switch self {
        case .juicing, .openSet, .cooking: true
        default: false
        }
    }

    var isCooking: Bool {
        if case .cooking = self { true } else { false }
    }
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
        case .juicing, .openSet:
            drawWave(in: capsule, context: context)
        case .cooking(let zap):
            drawZap(zap, in: capsule, context: context)
        case .gains:
            drawReformed(in: capsule, context: context)
        case .rest, .benched, .access, .hint, .spit:
            drawLozenge(layout.lozenge, context: context)
            if trayOpen {
                for mark in layout.marks {
                    drawGlyph(mark.1, in: mark.2, context: context)
                }
                if let close = layout.close {
                    drawClose(close, context: context)
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

    /// A white disc with a dark cross, set apart from the acid tool marks.
    private func drawClose(_ rect: CGRect, context: CGContext) {
        context.setFillColor(NSColor.white.withAlphaComponent(0.94).cgColor)
        context.fillEllipse(in: rect)
        let inset: CGFloat = 4.6
        let ink = NSColor.black.withAlphaComponent(0.88)
        strokeLine(
            from: CGPoint(x: rect.minX + inset, y: rect.minY + inset),
            to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset),
            width: 1.8,
            color: ink,
            context: context
        )
        strokeLine(
            from: CGPoint(x: rect.minX + inset, y: rect.maxY - inset),
            to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset),
            width: 1.8,
            color: ink,
            context: context
        )
    }

    /// Real mic levels, newest on the right. Silence is a flat line.
    private func drawWave(in capsule: NSRect, context: CGContext) {
        let melt: CGFloat = arrivedDissolved ? 1 : CGFloat(min(1, sinceMood / 0.28))
        if melt < 1 {
            let width = 15 * (1 - melt) + 4 * melt
            let height = 7 * (1 - melt) + 1.5 * melt
            let rect = CGRect(
                x: capsule.midX - width / 2,
                y: capsule.midY - height / 2,
                width: width,
                height: height
            )
            fillRounded(rect, radius: height / 2, color: cue.acid.withAlphaComponent(0.8 * (1 - melt)), context: context)
        }

        let samples = MicWave.shared.snapshot()
        let inset = capsule.insetBy(dx: 10, dy: 5)
        let mid = inset.midY
        let color = cue.acid.withAlphaComponent(0.95 * melt)
        strokeLine(
            from: CGPoint(x: inset.minX, y: mid),
            to: CGPoint(x: inset.maxX, y: mid),
            width: 1,
            color: color.withAlphaComponent(0.35 * melt),
            context: context
        )
        guard samples.count > 1 else { return }

        let step = inset.width / 41
        let origin = inset.maxX - CGFloat(samples.count - 1) * step
        func amplitude(_ sample: Float) -> CGFloat {
            let lifted = pow(Double(min(1, sample * 4.4)), 0.6)
            return CGFloat(lifted) * (inset.height / 2)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: inset.minX, y: mid))
        path.addLine(to: CGPoint(x: origin, y: mid))
        for index in samples.indices {
            let x = origin + CGFloat(index) * step
            path.addLine(to: CGPoint(x: x, y: mid + amplitude(samples[index])))
        }
        for index in samples.indices.reversed() {
            let x = origin + CGFloat(index) * step
            path.addLine(to: CGPoint(x: x, y: mid - amplitude(samples[index])))
        }
        path.addLine(to: CGPoint(x: origin, y: mid))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private func drawZap(_ zap: JuiceZap, in capsule: NSRect, context: CGContext) {
        let acid = cue.acid
        switch zap {
        case .voice:
            drawBolt(in: capsule, context: context, jagged: true, color: acid)
        case .fix:
            drawSlashes(in: capsule, context: context, leaning: 1, pair: true, color: acid)
        case .math:
            drawEqualsCharge(in: capsule, context: context, color: acid)
        case .ask:
            drawAskSpark(in: capsule, context: context, color: acid)
        case .translate:
            drawSwap(in: capsule, context: context, color: acid)
        case .rephrase:
            drawRicochet(in: capsule, context: context, color: acid)
        case .screen:
            drawChevron(in: capsule, context: context, color: acid)
        case .thread:
            drawSlashes(in: capsule, context: context, leaning: -1, pair: false, color: acid)
        case .charge:
            drawBolt(in: capsule, context: context, jagged: false, color: acid)
        }
    }

    private func cycle(_ period: Double) -> CGFloat {
        guard period > 0 else { return 0 }
        return CGFloat(sinceMood.truncatingRemainder(dividingBy: period) / period)
    }

    private func drawBolt(in capsule: NSRect, context: CGContext, jagged: Bool, color: NSColor) {
        let t = cycle(0.44)
        let strike = min(1, t / 0.34)
        let fade = t < 0.34 ? 1 : max(0, 1 - (t - 0.34) / 0.12)
        let left = capsule.minX + 9
        let right = capsule.maxX - 9
        let headX = left + (right - left) * strike
        let tailX = max(left, headX - 26)
        let mid = capsule.midY
        let generation = floor(sinceMood / 0.44)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: tailX, y: mid))
        let segments = 4
        for index in 1...segments {
            let x = tailX + (headX - tailX) * CGFloat(index) / CGFloat(segments)
            let jag: CGFloat = jagged && index < segments
                ? CGFloat(sin(generation * 1.7 + Double(index) * 2.1)) * 3.4
                : 0
            path.addLine(to: CGPoint(x: x, y: mid + jag))
        }
        strokePath(path, width: 1.6, color: color.withAlphaComponent(fade), context: context)
        fillDot(x: headX, y: mid, radius: 2.1, color: color.withAlphaComponent(fade), context: context)
    }

    private func drawSlashes(in capsule: NSRect, context: CGContext, leaning: CGFloat, pair: Bool, color: NSColor) {
        let t = cycle(0.52)
        let travel = min(1, t / 0.42)
        let fade = t < 0.42 ? 1 : max(0, 1 - (t - 0.42) / 0.1)
        let left = capsule.minX + 12
        let right = capsule.maxX - 18
        let x = left + (right - left) * travel
        slash(at: x, lean: leaning, alpha: fade, color: color, in: capsule, context: context)
        if pair {
            slash(at: x + 7, lean: leaning, alpha: fade, color: color, in: capsule, context: context)
        }
        fillDot(x: x + (pair ? 10 : 4), y: capsule.midY, radius: 1.6, color: color.withAlphaComponent(fade), context: context)
    }

    private func slash(at x: CGFloat, lean: CGFloat, alpha: CGFloat, color: NSColor, in capsule: NSRect, context: CGContext) {
        let mid = capsule.midY
        let rise: CGFloat = 6 * lean
        strokeLine(
            from: CGPoint(x: x, y: mid - rise),
            to: CGPoint(x: x + 5, y: mid + rise),
            width: 1.7,
            color: color.withAlphaComponent(alpha),
            context: context
        )
    }

    private func drawEqualsCharge(in capsule: NSRect, context: CGContext, color: NSColor) {
        let mid = capsule.midX
        let width: CGFloat = 18
        let left = mid - width / 2
        let top = capsule.midY + 3
        let bottom = capsule.midY - 3
        let bar = color.withAlphaComponent(0.45)
        strokeLine(from: CGPoint(x: left, y: top), to: CGPoint(x: left + width, y: top), width: 1.5, color: bar, context: context)
        strokeLine(from: CGPoint(x: left, y: bottom), to: CGPoint(x: left + width, y: bottom), width: 1.5, color: bar, context: context)
        let t = cycle(0.5)
        let along = t < 0.5 ? t * 2 : (t - 0.5) * 2
        let y = t < 0.5 ? top : bottom
        fillDot(x: left + width * along, y: y, radius: 2, color: color, context: context)
    }

    private func drawAskSpark(in capsule: NSRect, context: CGContext, color: NSColor) {
        let t = cycle(0.66)
        let mid = capsule.midY
        let x = capsule.midX
        if t < 0.22 {
            fillDot(x: x - 2, y: mid + 3, radius: 2, color: color, context: context)
        } else if t < 0.44 {
            fillDot(x: x + 2, y: mid + 3, radius: 2, color: color, context: context)
        } else {
            let hook = (t - 0.44) / 0.56
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x + 2, y: mid + 3))
            path.addQuadCurve(
                to: CGPoint(x: x, y: mid - 4),
                control: CGPoint(x: x + 7, y: mid - 1 + 4 * (1 - hook))
            )
            strokePath(path, width: 1.6, color: color.withAlphaComponent(0.5 + 0.5 * hook), context: context)
            fillDot(x: x, y: mid - 4, radius: 1.5, color: color, context: context)
        }
    }

    private func drawSwap(in capsule: NSRect, context: CGContext, color: NSColor) {
        let t = cycle(0.6)
        let eased = t * t * (3 - 2 * t)
        let left = capsule.midX - 8
        let right = capsule.midX + 8
        let y = capsule.midY
        fillDot(x: left + (right - left) * eased, y: y, radius: 2, color: color, context: context)
        fillDot(x: right - (right - left) * eased, y: y, radius: 2, color: color.withAlphaComponent(0.7), context: context)
    }

    private func drawRicochet(in capsule: NSRect, context: CGContext, color: NSColor) {
        let mid = capsule.midX
        let y = capsule.midY
        let bar = color.withAlphaComponent(0.4)
        strokeLine(from: CGPoint(x: mid - 7, y: y - 5), to: CGPoint(x: mid - 7, y: y + 5), width: 1.6, color: bar, context: context)
        strokeLine(from: CGPoint(x: mid + 7, y: y - 5), to: CGPoint(x: mid + 7, y: y + 5), width: 1.6, color: bar, context: context)
        let t = cycle(0.36)
        let bounce = t < 0.5 ? t * 2 : 1 - (t - 0.5) * 2
        fillDot(x: mid - 7 + 14 * bounce, y: y, radius: 2, color: color, context: context)
    }

    private func drawChevron(in capsule: NSRect, context: CGContext, color: NSColor) {
        let t = cycle(0.48)
        let travel = min(1, t / 0.4)
        let fade = t < 0.4 ? 1 : max(0, 1 - (t - 0.4) / 0.08)
        let x = capsule.minX + 14 + (capsule.width - 32) * travel
        let y = capsule.midY
        let ink = color.withAlphaComponent(fade)
        strokeLine(from: CGPoint(x: x, y: y - 4), to: CGPoint(x: x + 5, y: y), width: 1.7, color: ink, context: context)
        strokeLine(from: CGPoint(x: x, y: y + 4), to: CGPoint(x: x + 5, y: y), width: 1.7, color: ink, context: context)
        strokeLine(from: CGPoint(x: x + 6, y: y - 4), to: CGPoint(x: x + 11, y: y), width: 1.7, color: ink, context: context)
        strokeLine(from: CGPoint(x: x + 6, y: y + 4), to: CGPoint(x: x + 11, y: y), width: 1.7, color: ink, context: context)
    }

    private func strokeLine(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor, context: CGContext) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        strokePath(path, width: width, color: color, context: context)
    }

    private func strokePath(_ path: CGPath, width: CGFloat, color: NSColor, context: CGContext) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    private func fillDot(x: CGFloat, y: CGFloat, radius: CGFloat, color: NSColor, context: CGContext) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
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
