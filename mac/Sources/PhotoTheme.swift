// Colour themes for the tablet PHOTO (the same method as the Windows version): the tan body of the case is re-coloured while the
// shading, the black rubber, the screen frame and everything that is not tan stay as they are.
import Cocoa

enum PhotoTheme {
    private static var cache: [String: NSImage] = [:]

    static func clearCache() { cache.removeAll() }

    // ---- procedural camo noise (same numbers as the Windows version)
    private static func noiseHash(_ x: Int32, _ y: Int32, _ seed: Int32) -> Float {
        var h: Int32 = x &* 374761393
        h = h &+ (y &* 668265263)
        h = h &+ (seed &* 1442695041)
        let t: Int32 = h ^ (h >> 13)
        h = t &* 1274126177
        h = h ^ (h >> 16)
        return Float(h & 0xFFFFFF) / 16777215.0
    }

    private static func vnoise(_ x: Float, _ y: Float, _ seed: Int32) -> Float {
        let xi = Int32(floor(x)), yi = Int32(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = noiseHash(xi, yi, seed)
        let b = noiseHash(xi + 1, yi, seed)
        let c = noiseHash(xi, yi + 1, seed)
        let d = noiseHash(xi + 1, yi + 1, seed)
        let top = a + (b - a) * u
        let bottom = c + (d - c) * u
        return top + (bottom - top) * v
    }

    private static func fbm(_ x: Float, _ y: Float, _ seed: Int32) -> Float {
        return 0.6 * vnoise(x, y, seed) + 0.3 * vnoise(x * 2, y * 2, seed + 1) + 0.1 * vnoise(x * 4, y * 4, seed + 2)
    }

    private static func baseColor(_ name: String, _ x: Float, _ y: Float) -> (Float, Float, Float) {
        switch name {
        case "Black": return (64, 66, 64)
        case "Ranger Green": return (78, 90, 58)
        case "Arid": return (206, 186, 146)
        case "Navy": return (62, 76, 104)
        case "JG Camo":
            let n1 = fbm(x / 46, y / 46, 11), n2 = fbm(x / 32 + 9, y / 32, 23), n3 = fbm(x / 22, y / 22 + 5, 37)
            if n3 > 0.60 { return (28, 30, 22) }
            if n2 > 0.57 { return (104, 80, 48) }
            if n1 > 0.52 { return (50, 62, 34) }
            return (84, 98, 52)
        case "MultiCam":
            let n1 = fbm(x / 40, y / 40, 5), n2 = fbm(x / 28 + 3, y / 28, 17), n3 = fbm(x / 18, y / 18 + 8, 29)
            if n3 > 0.62 { return (80, 68, 46) }
            if n2 > 0.56 { return (112, 88, 60) }
            if n1 > 0.53 { return (128, 134, 92) }
            return (178, 160, 122)
        default: return (150, 125, 88)
        }
    }

    private static func clamp01(_ v: Float) -> Float { return v < 0 ? 0 : (v > 1 ? 1 : v) }

    // The photo with its tan body painted in the theme's colours. "Coyote Tan" is the photo's own colour.
    // `screen` and `logical` describe where the screen opening is (logical units), so it is left alone.
    static func themed(_ photo: NSImage, name: String, screen: CGRect, logical: CGSize) -> NSImage {
        if name == "Coyote Tan" { return photo }
        guard let cg = photo.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return photo }
        let w = cg.width, h = cg.height
        if w < 8 || h < 8 { return photo }
        let key = "\(name)|\(w)x\(h)"
        if let c = cache[key] { return c }

        var data = [UInt8](repeating: 0, count: w * h * 4)
        let result: CGImage? = data.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let p = base.assumingMemoryBound(to: UInt8.self)

            let kx = Float(w) / Float(logical.width)
            let sx0 = Int(Float(screen.minX) * kx), sx1 = Int(Float(screen.maxX) * kx)
            let sy0 = Int(Float(screen.minY) * Float(h) / Float(logical.height)), sy1 = Int(Float(screen.maxY) * Float(h) / Float(logical.height))
            let invK = Float(logical.width) / Float(w)      // logical units per pixel: camo blotches keep their size at any resolution

            for y in 0..<h {
                for x in 0..<w {
                    if x >= sx0 && x < sx1 && y >= sy0 && y < sy1 { continue }      // the screen opening
                    let i = (y * w + x) * 4
                    let a = Int(p[i + 3])
                    if a < 8 { continue }                                             // outside the case
                    let af = Float(a)
                    let r = min(255, Float(p[i]) * 255 / af)
                    let g = min(255, Float(p[i + 1]) * 255 / af)
                    let b = min(255, Float(p[i + 2]) * 255 / af)
                    let mx = max(r, max(g, b)), mn = min(r, min(g, b))
                    if mx < 10 { continue }
                    let sat = (mx - mn) / mx
                    let lum = 0.299 * r + 0.587 * g + 0.114 * b
                    let tanAmount: Float = clamp01((sat - 0.10) / 0.10) * clamp01((lum - 18) / 20)
                    if tanAmount <= 0 { continue }
                    let col = baseColor(name, Float(x) * invK, Float(y) * invK)
                    let shade: Float = max(0.25, min(1.8, lum / 120))
                    let nr: Float = min(255, col.0 * shade)
                    let ng: Float = min(255, col.1 * shade)
                    let nb: Float = min(255, col.2 * shade)
                    let outR: Float = r + (nr - r) * tanAmount
                    let outG: Float = g + (ng - g) * tanAmount
                    let outB: Float = b + (nb - b) * tanAmount
                    p[i] = UInt8(max(0, min(255, outR * af / 255)))
                    p[i + 1] = UInt8(max(0, min(255, outG * af / 255)))
                    p[i + 2] = UInt8(max(0, min(255, outB * af / 255)))
                }
            }
            return ctx.makeImage()
        }
        guard let img = result else { return photo }
        let out = NSImage(cgImage: img, size: photo.size)
        cache[key] = out
        return out
    }
}
