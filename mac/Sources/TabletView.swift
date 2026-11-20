// The tablet itself: vector-drawn device (or your own picture) with a see-through screen where the web page shows, the round
// buttons / soft keys on the frame, the labels and clock panel drawn over the page, the address bar and the side panels.
import Cocoa
import WebKit
import QuartzCore

private let uiGreen = NSColor(srgbRed: 150 / 255.0, green: 205 / 255.0, blue: 90 / 255.0, alpha: 1)

// ---------------------------------------------------------------- address bar
final class BarView: NSView {
    let backButton = NSButton()
    let forwardButton = NSButton()
    let reloadButton = NSButton()
    let homeButton = NSButton()
    let field = NSTextField()

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onHome: (() -> Void)?
    var onGo: ((String) -> Void)?

    override var isFlipped: Bool { return true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0.105, blue: 0.085, alpha: 1.0).cgColor
        configure(backButton, symbol: "chevron.left", fallback: "<", action: #selector(backTapped))
        configure(forwardButton, symbol: "chevron.right", fallback: ">", action: #selector(forwardTapped))
        configure(reloadButton, symbol: "arrow.clockwise", fallback: "R", action: #selector(reloadTapped))
        configure(homeButton, symbol: "house", fallback: "H", action: #selector(homeTapped))
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.045, alpha: 1.0)
        field.textColor = NSColor(srgbRed: 0.80, green: 0.84, blue: 0.74, alpha: 1.0)
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 12)
        field.placeholderString = "Type a web address or search"
        field.target = self
        field.action = #selector(fieldEntered)
        addSubview(field)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func configure(_ b: NSButton, symbol: String, fallback: String, action: Selector) {
        b.isBordered = false
        b.target = self
        b.action = action
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            b.image = img
            b.imagePosition = .imageOnly
            b.contentTintColor = NSColor(srgbRed: 0.80, green: 0.84, blue: 0.74, alpha: 1.0)
        } else {
            b.title = fallback
        }
        addSubview(b)
    }

    @objc func backTapped() { onBack?() }
    @objc func forwardTapped() { onForward?() }
    @objc func reloadTapped() { onReload?() }
    @objc func homeTapped() { onHome?() }
    @objc func fieldEntered() { onGo?(field.stringValue) }

    override func layout() {
        super.layout()
        let h = bounds.height
        let bs = max(18.0, h - 6.0)
        var x: CGFloat = 4
        for b in [backButton, forwardButton, reloadButton, homeButton] {
            b.frame = NSRect(x: x, y: (h - bs) / 2, width: bs, height: bs)
            x += bs + 2
        }
        let fh = min(h - 6.0, 22.0)
        field.frame = NSRect(x: x + 4, y: (h - fh) / 2, width: max(40, bounds.width - x - 8), height: fh)
    }
}

// ---------------------------------------------------------------- labels and clock panel over the page
struct HUDLabel {
    let id: String       // soft key slot, e.g. "T1"
    let text: String
    let state: Int
}

final class HUDView: NSView {
    var layoutDef: Layout = .atak
    var clock: Clockwork?
    var showLabels = true
    var showPanel = true
    var labels: [HUDLabel] = []
    var hoverID: String?
    var panelRightLimit: CGFloat?      // the clock panel stays left of this x (a side panel is open)
    var panelMinTop: CGFloat?          // ... and below this y (the address bar is showing)
    var live = false                   // frameless live view: only the alarm banner
    var onAction: ((String) -> Void)?
    private var labelRects: [(String, CGRect)] = []

    override var isFlipped: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    // only the soft-key labels take clicks; everything else goes through to the page
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        for (_, r) in labelRects where r.contains(p) { return self }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (id, r) in labelRects where r.contains(p) {
            onAction?("SK:" + id)
            return
        }
    }

    // a short message (e.g. "Preset 1 applied") at the bottom of the screen
    var toast: String?

    private func drawToast(_ ctx: CGContext) {
        guard let t = toast, !t.isEmpty else { return }
        let fs = max(11.0, bounds.width / 46.0)
        let font = NSFont.monospacedSystemFont(ofSize: fs, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiGreen]
        let sz = (t as NSString).size(withAttributes: attrs)
        let w = min(bounds.width - 16, sz.width + 24)
        let pill = CGRect(x: (bounds.width - w) / 2, y: bounds.height - sz.height - 28, width: w, height: sz.height + 10)
        ctx.setFillColor(NSColor(srgbRed: 10 / 255.0, green: 12 / 255.0, blue: 8 / 255.0, alpha: 220 / 255.0).cgColor)
        ctx.addPath(ArtPainter.rounded(pill, 8))
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(srgbRed: 70 / 255.0, green: 80 / 255.0, blue: 62 / 255.0, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(ArtPainter.rounded(pill, 8))
        ctx.strokePath()
        (t as NSString).draw(in: CGRect(x: pill.minX + 12, y: pill.minY + 5, width: w - 24, height: sz.height), withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        labelRects = []
        defer { drawToast(ctx) }
        guard let clock = clock else { return }
        if live {
            drawBanner(ctx, clock)
            return
        }
        let sc = bounds.width / layoutDef.logical.width
        let s = layoutDef.screen
        let fpx = max(9.0, 8.6 * sc)
        let font = NSFont.monospacedSystemFont(ofSize: fpx, weight: .bold)

        if layoutDef.isPilot && showLabels {
            for lab in labels {
                if lab.text.isEmpty { continue }
                guard let k = layoutDef.softKeys.first(where: { $0.id == lab.id }) else { continue }
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: clock.stateColor(lab.state)]
                let sz = (lab.text as NSString).size(withAttributes: attrs)
                let tw = max(4.0, sz.width - fpx * 0.4)
                let th = fpx * 1.25
                let pad = 2.5 * sc
                var cx: CGFloat
                var cy: CGFloat
                switch k.side {
                case "L": cx = (s.minX + 3) * sc + tw / 2 + pad; cy = k.y * sc
                case "R": cx = (s.maxX - 3) * sc - tw / 2 - pad; cy = k.y * sc
                case "T": cx = k.x * sc; cy = (s.minY + 10) * sc
                default: cx = k.x * sc; cy = (s.maxY - 10) * sc
                }
                let box = CGRect(x: cx - tw / 2 - pad, y: cy - th / 2, width: tw + 2 * pad, height: th)
                let hot = hoverID == "SK:" + lab.id
                let path = ArtPainter.rounded(box, th * 0.28)
                ctx.setFillColor(NSColor(srgbRed: 8 / 255.0, green: 10 / 255.0, blue: 8 / 255.0, alpha: hot ? 215 / 255.0 : 165 / 255.0).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.setStrokeColor((hot ? uiGreen : NSColor(srgbRed: 60 / 255.0, green: 70 / 255.0, blue: 55 / 255.0, alpha: 1)).cgColor)
                ctx.setLineWidth(1)
                ctx.addPath(path)
                ctx.strokePath()
                (lab.text as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + (th - sz.height) / 2), withAttributes: attrs)
                labelRects.append((lab.id, box.insetBy(dx: -3, dy: -3)))
            }
        }

        if showPanel {
            let lines = clock.panelLines()
            let lh = fpx * 1.35
            var wmax: CGFloat = 0
            for l in lines {
                let w = (l.text as NSString).size(withAttributes: [.font: font]).width
                wmax = max(wmax, w)
            }
            let pad = 4.0 * sc
            let bw = wmax + 2 * pad
            let bh = CGFloat(lines.count) * lh + pad
            var right = (s.maxX - 6) * sc
            var top = (s.minY + (layoutDef.isPilot && showLabels ? 24 : 6)) * sc
            if let lim = panelRightLimit { right = min(right, lim - 6 * sc) }
            if let mt = panelMinTop { top = max(top, mt) }
            let box = CGRect(x: right - bw, y: top, width: bw, height: bh)
            let path = ArtPainter.rounded(box, 4 * sc)
            ctx.setFillColor(NSColor(srgbRed: 8 / 255.0, green: 10 / 255.0, blue: 8 / 255.0, alpha: 150 / 255.0).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(srgbRed: 70 / 255.0, green: 80 / 255.0, blue: 62 / 255.0, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(path)
            ctx.strokePath()
            for (i, l) in lines.enumerated() {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: clock.stateColor(l.state)]
                (l.text as NSString).draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad / 2 + CGFloat(i) * lh), withAttributes: attrs)
            }
        }
    }

    // live corner view: a flashing banner when a timer is up
    private func drawBanner(_ ctx: CGContext, _ clock: Clockwork) {
        guard let idx = clock.timers.firstIndex(where: { $0.done }) else { return }
        let fs = max(11.0, bounds.width / 34.0) * 1.25
        let font = NSFont.monospacedSystemFont(ofSize: fs, weight: .bold)
        let txt = "TIMER \(idx + 1) DONE  " + Clockwork.fmtPreset(clock.timers[idx].preset)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 1, green: 245 / 255.0, blue: 225 / 255.0, alpha: 1)]
        let sz = (txt as NSString).size(withAttributes: attrs)
        let pill = CGRect(x: (bounds.width - sz.width) / 2 - 12, y: 10, width: sz.width + 24, height: sz.height + 10)
        let on = clock.flashOn
        ctx.setFillColor(NSColor(srgbRed: (on ? 120 : 60) / 255.0, green: (on ? 70 : 8) / 255.0, blue: 6 / 255.0, alpha: 215 / 255.0).cgColor)
        ctx.addPath(ArtPainter.rounded(pill, 8))
        ctx.fillPath()
        ctx.setStrokeColor(clock.stateColor(3).cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(ArtPainter.rounded(pill, 8))
        ctx.strokePath()
        (txt as NSString).draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 5), withAttributes: attrs)
    }
}

// ---------------------------------------------------------------- "move the live view" layer
final class DragCatcherView: NSView {
    var onFinish: (() -> Void)?
    override var isFlipped: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)      // returns when the mouse button is let go
        onFinish?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setFillColor(NSColor(srgbRed: 20 / 255.0, green: 20 / 255.0, blue: 20 / 255.0, alpha: 10 / 255.0).cgColor)
        ctx.fill(bounds)
        ctx.setStrokeColor(NSColor(srgbRed: 150 / 255.0, green: 205 / 255.0, blue: 90 / 255.0, alpha: 235 / 255.0).cgColor)
        ctx.setLineWidth(4)
        ctx.stroke(bounds.insetBy(dx: 2.5, dy: 2.5))
        let fs = max(11.0, bounds.width / 34.0)
        let font = NSFont.monospacedSystemFont(ofSize: fs, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiGreen]
        let hint = "DRAG TO MOVE  -  click to finish"
        let sz = (hint as NSString).size(withAttributes: attrs)
        let pill = CGRect(x: (bounds.width - sz.width) / 2 - 10, y: bounds.height / 2 - sz.height / 2 - 6, width: sz.width + 20, height: sz.height + 12)
        ctx.setFillColor(NSColor(srgbRed: 10 / 255.0, green: 12 / 255.0, blue: 8 / 255.0, alpha: 200 / 255.0).cgColor)
        ctx.addPath(ArtPainter.rounded(pill, 8))
        ctx.fillPath()
        (hint as NSString).draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + 6), withAttributes: attrs)
    }
}

// ---------------------------------------------------------------- the tablet
final class TabletView: NSView {
    enum Mode { case art, live }

    var layoutDef: Layout = .atak { didSet { hud.layoutDef = layoutDef; needsLayout = true; needsDisplay = true } }
    var theme: Theme = Themes.all[0] { didSet { needsDisplay = true } }
    var skin: NSImage? { didSet { needsDisplay = true } }
    var mode: Mode = .art { didSet { updateVisibility(); needsLayout = true; needsDisplay = true; hud.live = (mode == .live); hud.needsDisplay = true } }
    var pageWidthCSS = 1050
    var isExpanded = false { didSet { needsDisplay = true } }
    private(set) var contentVisible = false
    var barVisible = false { didSet { updateVisibility(); needsLayout = true } }
    var dragActive = false { didSet { dragCatcher.isHidden = !dragActive; dragCatcher.needsDisplay = true } }

    // what the art shows
    var statusKey = ""            // e.g. the open / minimize shortcut as text
    var statusInfo = ""           // minimized: the running timer or the clock
    var lockMouse = true
    var alert = false
    var liveOn = false
    var notesOn = false
    var timerLit = false
    var hoverID: String? {
        didSet {
            if hoverID != oldValue {
                needsDisplay = true
                hud.hoverID = hoverID
                hud.needsDisplay = true
            }
        }
    }

    var onAction: ((String) -> Void)?
    var onDockClick: (() -> Void)?
    var onDockMoved: (() -> Void)?

    let web: WKWebView
    let bar = BarView(frame: .zero)
    let hud = HUDView(frame: .zero)
    let dragCatcher = DragCatcherView(frame: .zero)
    var sidePanel: NSView? {
        didSet {
            if let o = oldValue { o.removeFromSuperview() }
            if let p = sidePanel { addSubview(p, positioned: .below, relativeTo: hud) }
            needsLayout = true
        }
    }

    override var isFlipped: Bool { return true }

    var scale: CGFloat { return bounds.width / layoutDef.logical.width }

    init(web: WKWebView) {
        self.web = web
        super.init(frame: .zero)
        wantsLayer = true
        hud.wantsLayer = true
        dragCatcher.wantsLayer = true
        addSubview(web)
        addSubview(bar)
        addSubview(hud)
        addSubview(dragCatcher)
        dragCatcher.isHidden = true
        web.isHidden = true
        bar.isHidden = true
        hud.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    // ---- showing / hiding the live page
    func showContent(_ show: Bool) {
        contentVisible = show
        updateVisibility()
        needsLayout = true
        needsDisplay = true
    }

    private func updateVisibility() {
        web.isHidden = !contentVisible
        bar.isHidden = !(barVisible && contentVisible && mode == .art)
        sidePanel?.isHidden = !(contentVisible && mode == .art)
        hud.isHidden = (mode == .art && !contentVisible)
    }

    // ---- layout
    override func layout() {
        super.layout()
        hud.frame = bounds
        dragCatcher.frame = bounds
        if mode == .live {
            web.frame = bounds
            web.layer?.cornerRadius = 14
            web.layer?.masksToBounds = true
            hud.panelRightLimit = nil
            hud.panelMinTop = nil
            if contentVisible { setZoom(max(0.15, min(3.0, bounds.width / CGFloat(max(300, pageWidthCSS))))) }
            return
        }
        let s = scale
        let hole = layoutDef.screen
        let hx = hole.minX * s, hy = hole.minY * s, hw = hole.width * s, hh = hole.height * s
        var barH: CGFloat = 0
        if barVisible && contentVisible {
            barH = max(24.0, 15.0 * s)
            bar.frame = NSRect(x: hx, y: hy, width: hw, height: barH)
        }
        var pw: CGFloat = 0
        if let p = sidePanel, contentVisible {
            pw = min(hw * 0.6, max(240.0, hw * 0.38))
            if let sp = p as? SidePanelBase { sp.uiScale = s }
            p.frame = NSRect(x: hx + hw - pw, y: hy + barH, width: pw, height: hh - barH)
        }
        web.frame = NSRect(x: hx, y: hy, width: hw - pw, height: hh)      // the page keeps its place; the address bar lies on top of it
        web.layer?.cornerRadius = layoutDef.holeRadius * s * 0.8
        web.layer?.masksToBounds = true
        if contentVisible { setZoom(max(0.25, min(3.0, hw / CGFloat(max(500, pageWidthCSS))))) }
        hud.panelRightLimit = pw > 0 ? hx + hw - pw : nil
        hud.panelMinTop = barH > 0 ? hy + barH + 4 * s : nil
    }

    private func setZoom(_ z: CGFloat) {
        if abs(web.pageZoom - z) > 0.001 { web.pageZoom = z }
    }

    // ---- drawing
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        if mode == .live { return }
        let s = scale
        let L = layoutDef
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)

        if let img = skin {
            img.draw(in: NSRect(x: 0, y: 0, width: L.logical.width, height: L.logical.height),
                     from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else if L.isPilot {
            ArtPainter.drawPilot(ctx, theme: theme)
        } else {
            ArtPainter.drawAtak(ctx, theme: theme)
        }

        // the see-through screen
        let hole = ArtPainter.rounded(L.screen, L.holeRadius)
        ctx.setBlendMode(.clear)
        ctx.addPath(hole)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        if !contentVisible {
            // minimized / moving: dark glass instead of the live page, with the name and the shortcut
            ctx.setFillColor(NSColor(srgbRed: 8 / 255.0, green: 10 / 255.0, blue: 8 / 255.0, alpha: 0.96).cgColor)
            ctx.addPath(hole)
            ctx.fillPath()
            let c = CGPoint(x: L.screen.midX, y: L.screen.midY)
            let big = max(14.0, 12.0 / s)
            ArtPainter.text("TAC MAP", at: CGPoint(x: c.x, y: c.y - big * 0.7), size: big, color: uiGreen)
            let small = max(9.0, 9.5 / s)
            let hint = statusKey.isEmpty ? "" : "[" + statusKey + "]"
            let line = statusInfo.isEmpty ? hint : hint + "  " + statusInfo
            let col = alert ? NSColor(srgbRed: 1, green: 175 / 255.0, blue: 35 / 255.0, alpha: 1) : NSColor(srgbRed: 125 / 255.0, green: 235 / 255.0, blue: 95 / 255.0, alpha: 1)
            ArtPainter.text(line, at: CGPoint(x: c.x, y: c.y + big * 0.6), size: small, color: col)
        }

        // buttons on the frame (only while the tablet is open)
        if isExpanded && contentVisible {
            for (id, c) in L.roundButtons {
                var lit = hoverID == id
                var al = false
                switch id {
                case "LIVE": lit = lit || liveOn
                case "NOTES": lit = lit || notesOn
                case "TIMERMENU": lit = lit || timerLit; al = alert
                default: break
                }
                ArtPainter.drawRoundButton(ctx, id: id, center: c, lit: lit, alert: al)
            }
            if L.isPilot, let h = hoverID {
                // highlight the soft key / rocker under the mouse
                var r: CGRect?
                if h.hasPrefix("SK:") {
                    let slot = String(h.dropFirst(3))
                    if let k = L.softKeys.first(where: { $0.id == slot }) { r = Layout.keyRect(k) }
                } else if let sp = L.spots.first(where: { $0.id == h }) { r = sp.rect }
                if let rr = r {
                    ctx.setStrokeColor(uiGreen.cgColor)
                    ctx.setLineWidth(1.6)
                    ctx.addPath(ArtPainter.rounded(rr.insetBy(dx: 0.8, dy: 0.8), 4))
                    ctx.strokePath()
                }
            }
            drawStatusText(ctx)
        }
        ctx.restoreGState()
    }

    // the light and the words on the frame while the tablet is open
    private func drawStatusText(_ ctx: CGContext) {
        let L = layoutDef
        let dark = Themes.isDark(theme)
        let txtCol = dark ? NSColor(srgbRed: 210 / 255.0, green: 215 / 255.0, blue: 195 / 255.0, alpha: 1)
                          : NSColor(srgbRed: 38 / 255.0, green: 40 / 255.0, blue: 30 / 255.0, alpha: 1)
        var accent = NSColor(srgbRed: 1.0, green: 160 / 255.0, blue: 20 / 255.0, alpha: 1)
        if alert { accent = NSColor(srgbRed: 1.0, green: 175 / 255.0, blue: 35 / 255.0, alpha: 1) }
        let l1 = lockMouse ? "MOUSE LOCKED" : "TABLET ACTIVE"
        let l2 = "[" + statusKey + "] minimize"
        if L.compactLabels {
            let cx = L.labelAt.x, cy = L.labelAt.y
            let back = CGRect(x: cx - 75, y: cy - 10, width: 150, height: 46)
            ctx.setFillColor(NSColor(srgbRed: 12 / 255.0, green: 14 / 255.0, blue: 10 / 255.0, alpha: 150 / 255.0).cgColor)
            ctx.addPath(ArtPainter.rounded(back, 7))
            ctx.fillPath()
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 3.5, y: cy - 3.5, width: 7, height: 7))
            let light = NSColor(srgbRed: 215 / 255.0, green: 220 / 255.0, blue: 200 / 255.0, alpha: 1)
            ArtPainter.text(l1, at: CGPoint(x: cx, y: cy + 15), size: 8.5, color: light)
            ArtPainter.text(l2, at: CGPoint(x: cx, y: cy + 28), size: 8.5, color: light)
        } else {
            let d: CGFloat = 7
            let cx: CGFloat = 150, cy: CGFloat = 334
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
            ArtPainter.text(l1 + "   " + l2, at: CGPoint(x: cx + d, y: cy), size: 9.5, color: txtCol, centered: false)
        }
    }

    // ---- mouse
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        if !isExpanded { return }
        hoverID = hitAction(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverID = nil
    }

    // which button on the frame is under this point? (nil = none)
    func hitAction(at p: NSPoint) -> String? {
        if !isExpanded || mode != .art || !contentVisible { return nil }
        let s = scale
        let lx = p.x / s, ly = p.y / s
        for (id, c) in layoutDef.roundButtons where hypot(lx - c.x, ly - c.y) <= Layout.buttonRadius + 1 { return id }
        if layoutDef.isPilot {
            let pt = CGPoint(x: lx, y: ly)
            for k in layoutDef.softKeys where Layout.keyRect(k).contains(pt) { return "SK:" + k.id }
            for h in layoutDef.spots where h.rect.contains(pt) { return h.id }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .live { return }
        if !isExpanded {
            // the little tablet: a click opens it, dragging moves it
            let before = window?.frame.origin ?? .zero
            window?.performDrag(with: event)
            let after = window?.frame.origin ?? .zero
            if hypot(after.x - before.x, after.y - before.y) < 4 { onDockClick?() } else { onDockMoved?() }
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if let id = hitAction(at: p) {
            onAction?(id)
            return
        }
        window?.performDrag(with: event)          // the frame itself drags the tablet
    }
}
