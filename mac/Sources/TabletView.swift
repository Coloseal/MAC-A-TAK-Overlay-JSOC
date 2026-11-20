// The tablet itself: a vector-drawn rugged tablet (always sharp at any size) with a see-through screen where the web page
// shows, a settings button and an address-bar button. Everything is measured on a 774 x 396 "logical" picture, like the Windows version.
import Cocoa
import WebKit
import QuartzCore

// Small address bar that sits at the top of the tablet's screen.
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

final class TabletView: NSView {
    static let logical = CGSize(width: 774, height: 396)
    static let screenRect = CGRect(x: 126, y: 73, width: 522, height: 250)
    static let holeRadius: CGFloat = 13
    static let gearPoint = CGPoint(x: 692, y: 50)
    static let globePoint = CGPoint(x: 661, y: 50)
    static let buttonRadius: CGFloat = 12
    static let pageWidth: CGFloat = 1050     // the page is laid out this many CSS pixels wide, then scaled to the screen

    var theme: Theme = Themes.all[0] { didSet { needsDisplay = true } }
    var skin: NSImage? { didSet { needsDisplay = true } }
    var onDockClick: (() -> Void)?
    var onGear: (() -> Void)?
    var onGlobe: (() -> Void)?

    let web: WKWebView
    let bar = BarView(frame: .zero)
    private let gearButton = NSButton()
    private let globeButton = NSButton()

    private(set) var contentVisible = false
    var isExpanded = false
    var barVisible = false {
        didSet {
            bar.isHidden = !(barVisible && contentVisible)
            needsLayout = true
        }
    }

    override var isFlipped: Bool { return true }

    init(web: WKWebView) {
        self.web = web
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(web)
        addSubview(bar)
        web.isHidden = true
        bar.isHidden = true
        for (b, symbol, fallback, action) in [
            (gearButton, "gearshape.fill", "S", #selector(gearTapped)),
            (globeButton, "globe", "W", #selector(globeTapped))
        ] {
            b.isBordered = false
            b.target = self
            b.action = action
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                b.image = img
                b.imagePosition = .imageOnly
                b.contentTintColor = NSColor(srgbRed: 0.80, green: 0.83, blue: 0.75, alpha: 1.0)
            } else {
                b.title = fallback
            }
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    @objc func gearTapped() { onGear?() }
    @objc func globeTapped() { onGlobe?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func mouseDown(with event: NSEvent) {
        if !isExpanded {
            onDockClick?()
        } else {
            super.mouseDown(with: event)
        }
    }

    // Show / hide the page and the little buttons (hidden while the tablet is moving or minimized).
    func showContent(_ show: Bool) {
        contentVisible = show
        web.isHidden = !show
        bar.isHidden = !(show && barVisible)
        gearButton.isHidden = !show
        globeButton.isHidden = !show
        needsLayout = true
        needsDisplay = true
    }

    // only the expanded tablet can be dragged by its frame; the minimized one reacts to a click
    override var mouseDownCanMoveWindow: Bool { return isExpanded }

    override func layout() {
        super.layout()
        let s = bounds.width / TabletView.logical.width
        let hole = TabletView.screenRect
        let hx = hole.minX * s
        let hy = hole.minY * s
        let hw = hole.width * s
        let hh = hole.height * s
        web.frame = NSRect(x: hx, y: hy, width: hw, height: hh)
        if barVisible && contentVisible {
            let barH = max(24.0, 15.0 * s)
            bar.frame = NSRect(x: hx, y: hy, width: hw, height: barH)
        }
        if let layer = web.layer {
            layer.cornerRadius = 10.0 * s
            layer.masksToBounds = true
        }
        if contentVisible {
            let z = max(0.25, min(3.0, hw / TabletView.pageWidth))
            if abs(web.pageZoom - z) > 0.001 { web.pageZoom = z }
        }
        let r = TabletView.buttonRadius * s
        gearButton.frame = NSRect(x: TabletView.gearPoint.x * s - r * 0.8, y: TabletView.gearPoint.y * s - r * 0.8, width: r * 1.6, height: r * 1.6)
        globeButton.frame = NSRect(x: TabletView.globePoint.x * s - r * 0.8, y: TabletView.globePoint.y * s - r * 0.8, width: r * 1.6, height: r * 1.6)
    }

    // ---- drawing ----
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let s = bounds.width / TabletView.logical.width
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)

        if let img = skin {
            img.draw(in: NSRect(x: 0, y: 0, width: TabletView.logical.width, height: TabletView.logical.height),
                     from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            drawTablet(ctx)
        }

        // the see-through screen
        ctx.setBlendMode(.clear)
        let hole = CGPath(roundedRect: TabletView.screenRect, cornerWidth: TabletView.holeRadius, cornerHeight: TabletView.holeRadius, transform: nil)
        ctx.addPath(hole)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        if !contentVisible {
            // minimized / moving: dark glass instead of the live page
            ctx.setFillColor(NSColor(srgbRed: 0.03, green: 0.04, blue: 0.03, alpha: 0.94).cgColor)
            ctx.addPath(hole)
            ctx.fillPath()
        }

        // round backdrops behind the two small buttons
        for p in [TabletView.gearPoint, TabletView.globePoint] {
            let r = TabletView.buttonRadius
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.125, blue: 0.10, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor(srgbRed: 0.43, green: 0.47, blue: 0.37, alpha: 1.0).cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: rect.insetBy(dx: 0.6, dy: 0.6))
        }
        ctx.restoreGState()
    }

    private func drawTablet(_ ctx: CGContext) {
        // body with a top-to-bottom colour fade
        let body = CGPath(roundedRect: CGRect(x: 18, y: 20, width: 738, height: 356), cornerWidth: 46, cornerHeight: 46, transform: nil)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(colorsSpace: space, colors: [theme.top.cgColor, theme.bottom.cgColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 20), end: CGPoint(x: 0, y: 376), options: [])
        }
        ctx.restoreGState()

        // soft edge highlight
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.22).cgColor)
        ctx.setLineWidth(2.0)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 19, y: 21, width: 736, height: 354), cornerWidth: 45, cornerHeight: 45, transform: nil))
        ctx.strokePath()

        // dark ring around the screen
        ctx.setFillColor(NSColor(srgbRed: 0.11, green: 0.11, blue: 0.11, alpha: 1.0).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 114, y: 57, width: 546, height: 274), cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.fillPath()

        // speaker grille
        ctx.setFillColor(theme.bottom.withAlphaComponent(0.75).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 668, y: 140, width: 36, height: 70), cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.fillPath()
    }
}
