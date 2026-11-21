// Finds the screen opening in a tablet picture (the see-through hole in the middle of the case) so the web page can fill it
// exactly, whatever its shape - no dark bars around the page.
import Cocoa

struct OpeningShape {
    let rect: CGRect          // bounding box of the opening, in logical units
    let left: [CGFloat]       // for every row of the opening (top to bottom): where it starts, 0...1 across the rect's width
    let right: [CGFloat]      // ... and where it ends

    // the outline in logical units with its origin at the rect's top-left corner (y points down)
    func localPath() -> CGPath {
        let p = CGMutablePath()
        let n = left.count
        let w = rect.width, h = rect.height
        if n < 2 {
            p.addRect(CGRect(x: 0, y: 0, width: w, height: h))
            return p
        }
        let rowH = h / CGFloat(n)
        p.move(to: CGPoint(x: left[0] * w, y: 0))
        for i in 0..<n { p.addLine(to: CGPoint(x: left[i] * w, y: CGFloat(i) * rowH)) }
        p.addLine(to: CGPoint(x: left[n - 1] * w, y: h))
        p.addLine(to: CGPoint(x: right[n - 1] * w, y: h))
        var i = n - 1
        while i >= 0 {
            p.addLine(to: CGPoint(x: right[i] * w, y: CGFloat(i) * rowH))
            i -= 1
        }
        p.closeSubpath()
        return p
    }

    // how far the opening's rounded corners cut in over the top `height` points (at scale k): (left, right) in points
    func topInsets(height: CGFloat, scale k: CGFloat) -> (CGFloat, CGFloat) {
        let n = left.count
        if n < 2 { return (0, 0) }
        let rowH = rect.height * k / CGFloat(n)
        let rows = min(n, max(1, Int((height / rowH).rounded(.up))))
        var l: CGFloat = 0
        var r: CGFloat = 0
        for i in 0..<rows {
            l = max(l, left[i])
            r = max(r, 1 - right[i])
        }
        return (l * rect.width * k, r * rect.width * k)
    }

    // the outline in the tablet's logical coordinates
    func logicalPath() -> CGPath {
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return localPath().copy(using: &t) ?? localPath()
    }

    // The outline for a layer of a view that sits inside the opening: scaled by k (view points per logical unit), moved by
    // `offset` (where the view's top-left corner is, measured from the opening's top-left, in points, y down), and turned
    // upside down when the layer's y axis points up. `height` = the layer's height in points.
    func maskPath(scale k: CGFloat, offset: CGPoint, flipped: Bool, height: CGFloat) -> CGPath {
        var s = CGAffineTransform(scaleX: k, y: k).concatenating(CGAffineTransform(translationX: -offset.x, y: -offset.y))
        let moved = localPath().copy(using: &s) ?? localPath()
        if flipped { return moved }
        var f = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        return moved.copy(using: &f) ?? moved
    }
}

enum OpeningDetector {
    private static var cache: [String: OpeningShape?] = [:]

    // `key` identifies the picture (its file), so a picture is only examined once
    static func detect(_ photo: NSImage, logical: CGSize, key: String) -> OpeningShape? {
        let ck = "\(key)|\(Int(logical.width))x\(Int(logical.height))"
        if let c = cache[ck] { return c }
        let result = analyze(photo, logical: logical)
        cache[ck] = .some(result)
        return result
    }

    private static func analyze(_ photo: NSImage, logical: CGSize) -> OpeningShape? {
        guard let cg = photo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        if w < 16 || h < 16 { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        var clear = [Bool](repeating: false, count: w * h)
        let ok: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let p = base.assumingMemoryBound(to: UInt8.self)
            for k in 0..<(w * h) { clear[k] = p[k * 4 + 3] < 128 }
            return true
        }
        if !ok { return nil }

        // the see-through pixels that are connected to the picture's border are "outside"; the rest is the opening
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func seed(_ x: Int, _ y: Int) {
            let k = y * w + x
            if clear[k] && !outside[k] {
                outside[k] = true
                stack.append(k)
            }
        }
        for x in 0..<w { seed(x, 0); seed(x, h - 1) }
        for y in 0..<h { seed(0, y); seed(w - 1, y) }
        while let k = stack.popLast() {
            let x = k % w, y = k / w
            if x > 0 { seed(x - 1, y) }
            if x < w - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < h - 1 { seed(x, y + 1) }
        }

        var minX = w, maxX = -1, minY = h, maxY = -1, count = 0
        var rowL = [Int](repeating: w, count: h)
        var rowR = [Int](repeating: -1, count: h)
        for y in 0..<h {
            for x in 0..<w where clear[y * w + x] && !outside[y * w + x] {
                count += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                if x < rowL[y] { rowL[y] = x }
                if x > rowR[y] { rowR[y] = x }
            }
        }
        // no real opening (e.g. a photo with the screen still in it): nothing to fit
        if count < (w * h) / 50 || maxX - minX < w / 4 || maxY - minY < h / 4 { return nil }

        let bw = CGFloat(maxX - minX + 1), bh = CGFloat(maxY - minY + 1)
        var left: [CGFloat] = []
        var right: [CGFloat] = []
        var lastL: CGFloat = 0, lastR: CGFloat = 1
        for y in minY...maxY {
            if rowR[y] >= rowL[y] {
                lastL = CGFloat(rowL[y] - minX) / bw
                lastR = CGFloat(rowR[y] - minX + 1) / bw
            }
            left.append(max(0, min(1, lastL)))
            right.append(max(0, min(1, lastR)))
        }
        let kx = logical.width / CGFloat(w), ky = logical.height / CGFloat(h)
        let rect = CGRect(x: CGFloat(minX) * kx, y: CGFloat(minY) * ky, width: bw * kx, height: bh * ky)
        return OpeningShape(rect: rect, left: left, right: right)
    }
}
