// The two devices (ATAK tablet and pilot display): measurements, button positions and the vector artwork that is drawn
// when no photo is chosen. Everything is measured on a small "logical" picture, like the Windows version, so the art is
// sharp at any size.
import Cocoa

struct SoftKeySpec {
    let id: String
    let side: Character      // T(op) B(ottom) L(eft) R(ight)
    let x: CGFloat           // centre of the button, logical units
    let y: CGFloat
}

struct Hotspot {
    let id: String
    let rect: CGRect         // logical units
}

// positions on the pilot display were measured on the original 1560 x 1137 photo
private func sk(_ id: String, _ side: Character, _ sx: CGFloat, _ sy: CGFloat) -> SoftKeySpec {
    return SoftKeySpec(id: id, side: side, x: sx * 0.5, y: sy * 569.0 / 1137.0)
}

private func hs(_ id: String, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Hotspot {
    return Hotspot(id: id, rect: CGRect(x: x0 * 0.5, y: y0 * 569.0 / 1137.0, width: (x1 - x0) * 0.5, height: (y1 - y0) * 569.0 / 1137.0))
}

struct Layout {
    let id: String
    let name: String
    let logical: CGSize
    let screen: CGRect
    let holeRadius: CGFloat
    let gear: CGPoint
    let compactLabels: Bool
    let labelAt: CGPoint
    let pageTag: String
    let softKeys: [SoftKeySpec]
    let spots: [Hotspot]

    var isPilot: Bool { return id == "pilot" }

    func height(forWidth w: CGFloat) -> CGFloat { return w * logical.height / logical.width }

    // the round buttons on the frame: id and centre (logical units)
    var roundButtons: [(String, CGPoint)] {
        if isPilot { return [("GEAR", gear)] }
        return [
            ("GEAR", gear),
            ("WEB", CGPoint(x: gear.x - 31, y: gear.y)),
            ("LIVE", CGPoint(x: gear.x - 62, y: gear.y)),
            ("TIMERMENU", CGPoint(x: gear.x - 93, y: gear.y)),
            ("NOTES", CGPoint(x: gear.x - 124, y: gear.y))
        ]
    }

    static let buttonRadius: CGFloat = 13

    static let atak = Layout(
        id: "atak", name: "ATAK tablet", logical: CGSize(width: 774, height: 396),
        screen: CGRect(x: 126, y: 69, width: 522, height: 250), holeRadius: 13, gear: CGPoint(x: 692, y: 50),
        compactLabels: false, labelAt: CGPoint(x: 0, y: 0), pageTag: "tablet", softKeys: [], spots: [])

    static let pilot = Layout(
        id: "pilot", name: "Pilot display", logical: CGSize(width: 780, height: 569),
        screen: CGRect(x: 100, y: 95, width: 582, height: 387), holeRadius: 5, gear: CGPoint(x: 687, y: 28),
        compactLabels: true, labelAt: CGPoint(x: 390, y: 46), pageTag: "mfd",
        softKeys: [
            sk("T1", "T", 337, 50), sk("T2", "T", 466, 50), sk("T3", "T", 594, 50),
            sk("T4", "T", 962, 50), sk("T5", "T", 1093, 50), sk("T6", "T", 1222, 50),
            sk("L1", "L", 48, 377), sk("L2", "L", 48, 476), sk("L3", "L", 48, 574),
            sk("L4", "L", 48, 672), sk("L5", "L", 48, 770), sk("L6", "L", 48, 870),
            sk("R1", "R", 1506, 378), sk("R2", "R", 1506, 477), sk("R3", "R", 1506, 577),
            sk("R4", "R", 1506, 675), sk("R5", "R", 1506, 774), sk("R6", "R", 1506, 872),
            sk("B1", "B", 207, 1082), sk("B2", "B", 347, 1082), sk("B3", "B", 493, 1082),
            sk("B4", "B", 1055, 1082), sk("B5", "B", 1197, 1082), sk("B6", "B", 1341, 1082)
        ],
        spots: [
            hs("VB_UP", 1478, 168, 1548, 215), hs("VB_DN", 1478, 215, 1548, 262),      // VID / BRT : transparency
            hs("BK_UP", 8, 942, 82, 991), hs("BK_DN", 8, 991, 82, 1040),               // BK LT / BRT: size
            hs("VC_UP", 1474, 942, 1545, 991), hs("VC_DN", 1474, 991, 1545, 1040),     // VID / CON : page zoom
            hs("OFF", 8, 262, 82, 304)                                                  // OFF : minimize
        ])

    static func named(_ id: String) -> Layout { return id == "pilot" ? pilot : atak }

    // every button position is the same at any size: the clickable area of a pilot-display button
    static func keyRect(_ k: SoftKeySpec) -> CGRect { return CGRect(x: k.x - 18, y: k.y - 15, width: 36, height: 30) }

    // where a button's text label sits inside the screen
    func keyLabelRect(_ k: SoftKeySpec) -> CGRect {
        let s = screen
        switch k.side {
        case "L": return CGRect(x: s.minX, y: k.y - 8, width: 74, height: 16)
        case "R": return CGRect(x: s.maxX - 74, y: k.y - 8, width: 74, height: 16)
        case "T": return CGRect(x: k.x - 34, y: s.minY, width: 68, height: 17)
        default: return CGRect(x: k.x - 34, y: s.maxY - 17, width: 68, height: 17)
        }
    }
}

// a tiny repeatable "random" generator so camo patterns look the same every time
struct PatternRandom {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) & 0x7FFFFFFF) / CGFloat(0x7FFFFFFF)
    }
}

enum ArtPainter {
    static func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath {
        return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    }

    static func gray(_ v: CGFloat, _ a: CGFloat = 1.0) -> NSColor { return NSColor(white: v, alpha: a) }

    // text in a monospaced bold font; centred on `at` when centred is true, otherwise starting at `at`
    static func text(_ s: String, at p: CGPoint, size: CGFloat, color: NSColor, centered: Bool = true) {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let ns = s as NSString
        let sz = ns.size(withAttributes: attrs)
        let origin = centered ? CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2) : CGPoint(x: p.x, y: p.y - sz.height / 2)
        ns.draw(at: origin, withAttributes: attrs)
    }

    // fills `path` with the theme colours (and camo blotches)
    static func fillBody(_ ctx: CGContext, path: CGPath, area: CGRect, theme: Theme) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(colorsSpace: space, colors: [theme.top.cgColor, theme.bottom.cgColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: area.minY), end: CGPoint(x: 0, y: area.maxY), options: [])
        }
        if !theme.camo.isEmpty {
            var rnd = PatternRandom(s: 12345)
            for i in 0..<90 {
                ctx.setFillColor(theme.camo[i % theme.camo.count].cgColor)
                let w = 30 + rnd.next() * 100
                let h = 18 + rnd.next() * 60
                let x = area.minX + rnd.next() * area.width - w / 2
                let y = area.minY + rnd.next() * area.height - h / 2
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
        }
        ctx.restoreGState()
    }

    // ---------------- ATAK tablet
    static func drawAtak(_ ctx: CGContext, theme: Theme) {
        let body = rounded(CGRect(x: 18, y: 20, width: 738, height: 356), 46)
        fillBody(ctx, path: body, area: CGRect(x: 18, y: 20, width: 738, height: 356), theme: theme)
        // soft edge highlight
        ctx.setStrokeColor(gray(1.0, 0.22).cgColor)
        ctx.setLineWidth(2.0)
        ctx.addPath(rounded(CGRect(x: 19, y: 21, width: 736, height: 354), 45))
        ctx.strokePath()
        // dark ring around the screen
        ctx.setFillColor(gray(0.11).cgColor)
        ctx.addPath(rounded(CGRect(x: 114, y: 57, width: 546, height: 274), 20))
        ctx.fillPath()
        // speaker grille
        ctx.setFillColor(theme.bottom.withAlphaComponent(0.75).cgColor)
        ctx.addPath(rounded(CGRect(x: 668, y: 140, width: 36, height: 70), 12))
        ctx.fillPath()
    }

    // ---------------- pilot display
    static func drawPilot(_ ctx: CGContext, theme: Theme) {
        let area = CGRect(x: 2, y: 2, width: 776, height: 565)
        fillBody(ctx, path: rounded(area, 30), area: area, theme: theme)
        ctx.setStrokeColor(gray(1.0, 0.18).cgColor)
        ctx.setLineWidth(2.0)
        ctx.addPath(rounded(CGRect(x: 4, y: 4, width: 772, height: 561), 29))
        ctx.strokePath()
        // dark ring around the screen
        ctx.setFillColor(gray(0.05).cgColor)
        ctx.addPath(rounded(CGRect(x: 92, y: 87, width: 598, height: 403), 10))
        ctx.fillPath()
        // the 24 soft keys
        for k in Layout.pilot.softKeys {
            let r = Layout.keyRect(k)
            ctx.setFillColor(gray(0.10).cgColor)
            ctx.addPath(rounded(r, 5))
            ctx.fillPath()
            ctx.setStrokeColor(gray(0.34).cgColor)
            ctx.setLineWidth(1.2)
            ctx.addPath(rounded(r.insetBy(dx: 0.6, dy: 0.6), 4.5))
            ctx.strokePath()
            ctx.setStrokeColor(gray(1.0, 0.16).cgColor)
            ctx.move(to: CGPoint(x: r.minX + 5, y: r.minY + 3))
            ctx.addLine(to: CGPoint(x: r.maxX - 5, y: r.minY + 3))
            ctx.strokePath()
        }
        // rocker switches (arrows) and the OFF switch
        for h in Layout.pilot.spots {
            ctx.setFillColor(gray(0.14).cgColor)
            ctx.addPath(rounded(h.rect, 4))
            ctx.fillPath()
            ctx.setStrokeColor(gray(0.34).cgColor)
            ctx.setLineWidth(1.0)
            ctx.addPath(rounded(h.rect.insetBy(dx: 0.5, dy: 0.5), 3.5))
            ctx.strokePath()
            let c = CGPoint(x: h.rect.midX, y: h.rect.midY)
            if h.id.hasSuffix("_UP") || h.id.hasSuffix("_DN") {
                let up = h.id.hasSuffix("_UP")
                let a: CGFloat = 5
                ctx.setFillColor(gray(0.78).cgColor)
                ctx.move(to: CGPoint(x: c.x, y: up ? c.y - a : c.y + a))
                ctx.addLine(to: CGPoint(x: c.x - a, y: up ? c.y + a * 0.6 : c.y - a * 0.6))
                ctx.addLine(to: CGPoint(x: c.x + a, y: up ? c.y + a * 0.6 : c.y - a * 0.6))
                ctx.closePath()
                ctx.fillPath()
            } else {
                text("OFF", at: c, size: 8, color: gray(0.8))
            }
        }
        // small captions for the rockers
        text("BRT", at: CGPoint(x: 756, y: 62), size: 7, color: gray(0.6))
        text("SIZE", at: CGPoint(x: 22, y: 457), size: 7, color: gray(0.6))
        text("ZOOM", at: CGPoint(x: 756, y: 457), size: 7, color: gray(0.6))
    }

    // ---------------- round buttons (settings, address bar, live, timers, notes)
    static func drawRoundButton(_ ctx: CGContext, id: String, center c: CGPoint, lit: Bool, alert: Bool) {
        let gr = Layout.buttonRadius
        var col = lit ? NSColor(srgbRed: 150 / 255.0, green: 205 / 255.0, blue: 90 / 255.0, alpha: 1)
                      : NSColor(srgbRed: 205 / 255.0, green: 212 / 255.0, blue: 192 / 255.0, alpha: 1)
        if alert { col = NSColor(srgbRed: 1.0, green: 175 / 255.0, blue: 35 / 255.0, alpha: 1) }
        let back = NSColor(srgbRed: 30 / 255.0, green: 32 / 255.0, blue: 26 / 255.0, alpha: 1)
        let ringCol = lit || alert ? col : NSColor(srgbRed: 110 / 255.0, green: 120 / 255.0, blue: 95 / 255.0, alpha: 1)
        let box = CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)
        ctx.setFillColor(back.cgColor)
        ctx.fillEllipse(in: box)
        ctx.setStrokeColor(ringCol.cgColor)
        ctx.setLineWidth(1.3)
        ctx.strokeEllipse(in: box.insetBy(dx: 0.7, dy: 0.7))
        ctx.setStrokeColor(col.cgColor)
        ctx.setFillColor(col.cgColor)
        ctx.setLineWidth(1.4)
        let r = gr * 0.55
        switch id {
        case "GEAR":
            ctx.strokeEllipse(in: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24))
            for i in 0..<8 {
                let a = CGFloat(i) * CGFloat.pi / 4
                ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.8, y: c.y + sin(a) * r * 0.8))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * r * 1.2, y: c.y + sin(a) * r * 1.2))
            }
            ctx.strokePath()
        case "WEB":
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.strokeEllipse(in: CGRect(x: c.x - r * 0.45, y: c.y - r, width: r * 0.9, height: r * 2))
            ctx.move(to: CGPoint(x: c.x - r, y: c.y))
            ctx.addLine(to: CGPoint(x: c.x + r, y: c.y))
            ctx.strokePath()
        case "TIMERMENU":
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r + gr * 0.08, width: r * 2, height: r * 2))
            ctx.move(to: CGPoint(x: c.x, y: c.y + gr * 0.08))
            ctx.addLine(to: CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.35))
            ctx.move(to: CGPoint(x: c.x - r * 0.28, y: c.y - r - gr * 0.12))
            ctx.addLine(to: CGPoint(x: c.x + r * 0.28, y: c.y - r - gr * 0.12))
            ctx.strokePath()
        case "NOTES":
            ctx.stroke(CGRect(x: c.x - r * 0.75, y: c.y - r, width: r * 1.5, height: r * 2))
            for i in 0..<3 {
                let yy = c.y - r * 0.45 + CGFloat(i) * r * 0.5
                ctx.move(to: CGPoint(x: c.x - r * 0.45, y: yy))
                ctx.addLine(to: CGPoint(x: c.x + r * 0.45, y: yy))
            }
            ctx.strokePath()
        case "LIVE":
            ctx.stroke(CGRect(x: c.x - r, y: c.y - r * 0.72, width: r * 2, height: r * 1.44))
            ctx.fill(CGRect(x: c.x + r * 0.1, y: c.y + r * 0.02, width: r * 0.7, height: r * 0.5))
        default:
            break
        }
    }
}
