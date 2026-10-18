import simd
import UIKit

/// Stone drawn from its pattern and colours (owner, 2026-10-17): the
/// picker's swatches and preview, and stone in 3-D and the PDF pictures.
/// Every pattern is smooth noise shaped into veins, flecks, bands or cells,
/// the same each time it's drawn (fixed seeds), so a stone always looks the same.
enum StonePatterns {
    /// The picker's colours: families across (white & gray, cool gray,
    /// greige, cream & beige, gold & brown, rose, green, blue), light to dark
    /// down, in steps that look even (OKLCH lightness 0.975 to 0.24), muted
    /// the way stone is.
    static let palette: [[String]] = [
        ["#F7F7F7", "#F5F7F9", "#F8F6F4", "#FAF6EF", "#FFF5EB", "#FFF4F2", "#F2F9F4", "#F0F8FF"],
        ["#E4E4E4", "#E2E5E7", "#E7E4E1", "#E9E4DB", "#F0E2D4", "#EFE1DE", "#DEE7E1", "#DAE6F1"],
        ["#CACACA", "#C6CBD0", "#CECAC3", "#D3C9B8", "#E0C5AA", "#DFC3BE", "#BED0C3", "#B6CEE2"],
        ["#ABABAB", "#A4ACB3", "#B1AAA0", "#B8A98F", "#CBA277", "#C9A098", "#98B3A0", "#8BAFCF"],
        ["#898989", "#828A91", "#8F887F", "#96876E", "#A88157", "#A57E77", "#77917F", "#6B8DAC"],
        ["#666666", "#60676E", "#6C655C", "#72644C", "#835E34", "#805C55", "#546D5C", "#486A86"],
        ["#424242", "#3D4349", "#47413A", "#4C412D", "#593B18", "#573A35", "#34483A", "#2A455C"],
        ["#1F1F1F", "#1D2022", "#211F1C", "#231F17", "#291D0F", "#281C1A", "#19221C", "#16212A"],
    ]

    private static let cache = NSCache<NSString, UIImage>()

    /// The stone's pattern drawn `pixels` square (a photo is the caller's:
    /// `TilePhotos` isn't safe off the main thread). Safe from any thread.
    static func patternImage(_ look: StoneAppearance, pixels: Int) -> UIImage {
        let key = "\(look.drawingKey)@\(pixels)" as NSString
        if let i = cache.object(forKey: key) { return i }
        let i = draw(look, pixels: pixels)
        cache.setObject(i, forKey: key)
        return i
    }

    /// Drawn afresh, not cached.
    static func draw(_ look: StoneAppearance, pixels: Int) -> UIImage {
        Renderer(look: look, n: pixels).render()
    }

    static func cachedPattern(_ look: StoneAppearance, pixels: Int) -> UIImage? {
        cache.object(forKey: "\(look.drawingKey)@\(pixels)" as NSString)
    }

    /// The stone as drawn: its photo, else its pattern. Main thread.
    static func image(_ look: StoneAppearance, pixels: Int) -> UIImage {
        if let id = look.photoID, let photo = TilePhotos.image(id) { return photo }
        return patternImage(look, pixels: pixels)
    }

    static func rgb(_ hex: String) -> SIMD3<Float> {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return SIMD3(233, 230, 224) }
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF))
    }

    static func uiColor(_ hex: String) -> UIColor {
        let c = rgb(hex) / 255
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    static func hex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// A small fixed random sequence, the same on every device.
private struct SplitMix {
    var state: UInt64
    init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }
}

private final class Renderer {
    typealias V = SIMD3<Float>
    let look: StoneAppearance
    let n: Int
    let count: Int
    /// Pixel coordinates in pattern units: the square is 4 units across.
    let xx: [Float], yy: [Float]
    /// Sizes were set at 300 pixels; everything in pixels scales from there.
    let s: Float
    private var tables: [Int: [Float]] = [:]

    init(look: StoneAppearance, n: Int) {
        self.look = look
        self.n = max(8, n)
        count = self.n * self.n
        var x = [Float](repeating: 0, count: count), y = x
        for r in 0..<self.n {
            for c in 0..<self.n {
                x[r * self.n + c] = Float(c) / Float(self.n) * 4
                y[r * self.n + c] = Float(r) / Float(self.n) * 4
            }
        }
        xx = x; yy = y
        s = Float(self.n) / 300
    }

    // MARK: Noise

    private func table(_ seed: Int) -> [Float] {
        if let t = tables[seed] { return t }
        var r = SplitMix(seed)
        let t = (0..<4096).map { _ in r.unit() }
        tables[seed] = t
        return t
    }

    /// Smooth value noise, 0…1, repeating every 64 units.
    private func noise(_ x: [Float], _ y: [Float], _ seed: Int) -> [Float] {
        let g = table(seed)
        var out = [Float](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let fx = x[i].rounded(.down), fy = y[i].rounded(.down)
            var tx = x[i] - fx, ty = y[i] - fy
            tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
            let xi = Int(fx) & 63, yi = Int(fy) & 63
            let xj = (xi + 1) & 63, yj = (yi + 1) & 63
            let a = g[yi * 64 + xi], b = g[yi * 64 + xj], c = g[yj * 64 + xi], d = g[yj * 64 + xj]
            out[i] = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
        }
        return out
    }

    /// Layers of noise, each twice as fine and half as strong: 0…1.
    private func fbm(_ x: [Float], _ y: [Float], _ seed: Int, _ octaves: Int = 5) -> [Float] {
        var v = [Float](repeating: 0, count: x.count)
        var amp: Float = 1, total: Float = 0, f: Float = 1
        for o in 0..<octaves {
            let nz = noise(x.map { $0 * f }, y.map { $0 * f }, seed + o)
            for i in 0..<v.count { v[i] += amp * nz[i] }
            total += amp; amp *= 0.5; f *= 2
        }
        return v.map { $0 / total }
    }

    /// fbm of the pixel grid scaled and shifted.
    private func fbm(sx: Float, sy: Float, dx: Float = 0, _ seed: Int, _ octaves: Int = 5) -> [Float] {
        fbm(xx.map { $0 * sx + dx }, yy.map { $0 * sy }, seed, octaves)
    }

    private static func ridge(_ v: Float) -> Float { 1 - abs(2 * v - 1) }

    // MARK: Colour

    private var base: V { StonePatterns.rgb(look.base) }
    private var mark: V { StonePatterns.rgb(look.markings) }
    private var second: V? { look.second.map(StonePatterns.rgb) }

    private func flat(_ c: V) -> [V] { [V](repeating: c, count: count) }

    private func shade(_ img: inout [V], _ nz: [Float], _ amount: Float) {
        for i in 0..<count { img[i] += V(repeating: (nz[i] - 0.5) * amount) }
    }

    private func mix(_ img: inout [V], _ c: V, _ a: [Float]) {
        for i in 0..<count {
            let t = min(max(a[i], 0), 1)
            img[i] = img[i] * (1 - t) + c * t
        }
    }

    private func sparkle(_ img: inout [V], seed: Int, density: Float) {
        var r = SplitMix(seed + 900)
        for i in 0..<count where r.unit() < density {
            img[i] = img[i] * 0.4 + V(repeating: 255 * 0.6)
        }
    }

    // MARK: Patterns

    func render() -> UIImage {
        var overlay: ((CGContext) -> Void)? = nil
        let img: [V]
        switch look.pattern {
        case .softVeins: img = veined(seed: 3, bold: false, vein: mark)
        case .boldVeins: img = bold()
        case .web: img = web()
        case .breccia: img = breccia()
        case .quartziteLinear: img = quartziteLinear()
        case .quartziteCloudy: img = quartziteCloudy()
        case .graniteFine:
            img = solidBase(seed: 12, scale: 1, amount: 30)
            overlay = { self.flecks($0, seed: 12) }
        case .graniteCoarse: img = coarse()
        case .graniteFlowing: img = flowing(granite: true)
        case .solid: img = solidBase(seed: 2, scale: 1.5, amount: 8)
        case .concrete: img = concrete()
        case .terrazzo:
            img = solidBase(seed: 8, scale: 2, amount: 12, octaves: 3)
            overlay = { self.chips($0, seed: 8) }
        case .soapstone: img = soapstone()
        case .travertine:
            img = travertine()
            overlay = { self.pits($0, seed: 54) }
        case .limestone:
            img = limestone()
            overlay = { self.fossils($0, seed: 39) }
        case .onyx: img = onyx()
        }
        return image(img, overlay: overlay)
    }

    private func veined(seed: Int, bold: Bool, vein: V) -> [V] {
        let ang = Float(0.65 + Double(seed % 4) * 0.25)
        let ca = cos(ang), sa = sin(ang)
        let u = (0..<count).map { xx[$0] * ca + yy[$0] * sa }
        let w = (0..<count).map { -xx[$0] * sa + yy[$0] * ca }
        // Stretched along the vein's direction, and warped, so veins run long and flowing.
        let wx = fbm(u.map { $0 * 0.35 }, w.map { $0 * 1.2 }, seed + 3).map { $0 * 2.2 }
        let wy = fbm(u.map { $0 * 0.35 + 9 }, w.map { $0 * 1.2 }, seed + 5).map { $0 * 2.2 }
        let main = fbm((0..<count).map { u[$0] * 0.45 + wx[$0] }, (0..<count).map { w[$0] * 1.4 + wy[$0] }, seed, 6)
        let branch = fbm((0..<count).map { u[$0] * 0.9 + wy[$0] * 1.5 }, (0..<count).map { w[$0] * 2.2 + wx[$0] }, seed + 20, 6)
        let cloud = fbm(sx: 0.8, sy: 0.8, seed + 60, 4)
        var img = flat(base)
        shade(&img, cloud, 16)
        let a = (0..<count).map { i -> Float in
            let r = Self.ridge(main[i])
            let core = pow(r, bold ? 22 : 26), glow = pow(r, bold ? 8 : 7) * (bold ? 0.32 : 0.28)
            return core + glow + pow(Self.ridge(branch[i]), 50) * (bold ? 0.4 : 0.45)
        }
        mix(&img, vein, a)
        return img
    }

    private func bold() -> [V] {
        var img = veined(seed: 5, bold: true, vein: mark)
        // A second colour along some of the veins.
        if let c2 = second {
            let other = veined(seed: 36, bold: false, vein: c2)
            let b = base
            for i in 0..<count {
                let d = other[i] - b
                if abs(d.x) + abs(d.y) + abs(d.z) > 60 { img[i] = other[i] }
            }
        }
        return img
    }

    private func web() -> [V] {
        var img = flat(base)
        shade(&img, fbm(sx: 1, sy: 1, 9, 4), 22)
        var a = [Float](repeating: 0, count: count)
        for k in 0..<3 {
            let f = 1.6 + Float(k) * 0.7
            let nz = fbm(sx: f, sy: f, dx: 5 * Float(k), 9 + 10 * k, 6)
            let p = Float(30 + 10 * k), strength = 1 - Float(k) * 0.2
            for i in 0..<count { a[i] = max(a[i], pow(Self.ridge(nz[i]), p) * strength) }
        }
        mix(&img, mark, a)
        return img
    }

    /// Cells (one jittered point per grid square): each pixel's cell, and
    /// how far it is from the cell's edge, in pixels.
    private func cells(grid g: Int, seed: Int, warp: Float = 0) -> (index: [Int], edge: [Float]) {
        let wx = warp > 0 ? fbm(sx: 1.3, sy: 1.3, seed + 70, 4) : [], wy = warp > 0 ? fbm(sx: 1.3, sy: 1.3, dx: 7, seed + 71, 4) : []
        var r = SplitMix(seed)
        let size = Float(n) / Float(g)
        var pts = [SIMD2<Float>]()
        for cy in 0..<g { for cx in 0..<g {
            pts.append(SIMD2((Float(cx) + r.range(0.1, 0.9)) * size, (Float(cy) + r.range(0.1, 0.9)) * size))
        } }
        var index = [Int](repeating: 0, count: count), edge = [Float](repeating: 0, count: count)
        for py in 0..<n {
            for px in 0..<n {
                let i = py * n + px
                let p = warp > 0 ? SIMD2(Float(px) + (wx[i] - 0.5) * warp * Float(n), Float(py) + (wy[i] - 0.5) * warp * Float(n))
                                 : SIMD2(Float(px), Float(py))
                let cx = min(g - 1, max(0, Int(p.x / size))), cy = min(g - 1, max(0, Int(p.y / size)))
                var d1 = Float.greatestFiniteMagnitude, d2 = d1, best = 0
                for oy in max(0, cy - 2)...min(g - 1, cy + 2) {
                    for ox in max(0, cx - 2)...min(g - 1, cx + 2) {
                        let k = oy * g + ox
                        let d = simd_length(pts[k] - p)
                        if d < d1 { d2 = d1; d1 = d; best = k } else if d < d2 { d2 = d }
                    }
                }
                index[py * n + px] = best
                edge[py * n + px] = d2 - d1
            }
        }
        return (index, edge)
    }

    /// Broken fragments in a darker matrix: wandering, uneven seams.
    private func breccia() -> [V] {
        let (index, edge) = cells(grid: 6, seed: 4, warp: 0.12)
        var r = SplitMix(1004)
        let shades = (0..<36).map { _ in base * r.range(0.86, 1.06) }
        var img = index.map { shades[$0] }
        shade(&img, fbm(sx: 2, sy: 2, 4, 4), 20)
        // Fine veins inside the fragments.
        mix(&img, mark, fbm(sx: 2.4, sy: 2.4, 14, 6).map { pow(Self.ridge($0), 60) * 0.5 })
        let width = fbm(sx: 1.6, sy: 1.6, 24, 4)
        mix(&img, mark, (0..<count).map { i -> Float in
            let w: Float = (1 + width[i] * 5) * s
            let t: Float = 1 - edge[i] / w
            return t * 0.9
        })
        return img
    }

    private func coarse() -> [V] {
        let g = 26
        let (index, edge) = cells(grid: g, seed: 7, warp: 0.05)
        var r = SplitMix(1007)
        let palette: [V] = [base, base * 0.88, mark, (second ?? V(repeating: 255)) * 0.95]
        let weights: [Float] = [0.5, 0.25, 0.15, 0.10]
        let colours = (0..<(g * g)).map { _ -> V in
            var pick = r.unit(), k = 0
            while k < 3, pick > weights[k] { pick -= weights[k]; k += 1 }
            return palette[k] * r.range(0.9, 1.08)
        }
        var img = index.map { colours[$0] }
        shade(&img, fbm(sx: 3, sy: 3, 17, 4), 16)
        mix(&img, base * 0.6, edge.map { (1 - $0 / (1.0 * s)) * 0.12 })
        return img
    }

    private func quartziteLinear() -> [V] {
        let warp = fbm(sx: 0.5, sy: 0.5, 31)
        let along = (0..<count).map { i -> Float in
            let tilt: Float = xx[i] * 0.35
            let bend: Float = (warp[i] - 0.5) * 1.4
            return yy[i] + tilt + bend
        }
        var img = flat(base)
        shade(&img, fbm(sx: 2, sy: 2, 32, 4), 14)
        // Wide soft bands in the second colour, thin crisp lines in the first.
        let wobble = fbm(sx: 1, sy: 1, 33, 3)
        mix(&img, second ?? mark, (0..<count).map { i -> Float in
            let phase: Float = (along[i] * 2.1 + wobble[i] * 3) * Float.pi
            let wave: Float = sin(phase) * 0.5 + 0.5
            return pow(wave, 6) * 0.55
        })
        for (k, line) in [(5.3, 40.0, 0.8), (9.1, 70.0, 0.6), (3.7, 90.0, 0.9)].enumerated() {
            let jitter = fbm(sx: 3, sy: 3, 36 + k, 4)
            let gate = fbm(sx: 1.5, sy: 1.5, 40 + k, 3)
            mix(&img, mark, (0..<count).map { i -> Float in
                guard gate[i] > 0.42 else { return 0 }
                let t = abs(sin((along[i] * Float(line.0) + jitter[i] * 0.8) * .pi))
                return pow(1 - t, Float(line.1)) * Float(line.2)
            })
        }
        sparkle(&img, seed: 31, density: 0.002)
        return img
    }

    private func quartziteCloudy() -> [V] {
        let cloud = fbm(sx: 1.1, sy: 1.1, 33, 6)
        var img = flat(base)
        mix(&img, second ?? mark, cloud.map { min(max(($0 - 0.45) * 2.5, 0), 1) * 0.6 })
        let veins = fbm(sx: 2.2, sy: 2.2, dx: 3, 37, 6)
        mix(&img, mark, veins.map { pow(Self.ridge($0), 40) * 0.7 })
        sparkle(&img, seed: 33, density: 0.004)
        return img
    }

    private func solidBase(seed: Int, scale: Float, amount: Float, octaves: Int = 4) -> [V] {
        var img = flat(base)
        shade(&img, fbm(sx: scale, sy: scale, seed, octaves), amount)
        return img
    }

    private func flowing(granite: Bool) -> [V] {
        let w = fbm(sx: 0.5, sy: 0.5, 35, 5)
        let fine = fbm(sx: 2, sy: 2, 39, 4)
        let mid = second ?? (base + mark) / 2
        var img = (0..<count).map { i -> V in
            let s: Float = yy[i] * 1.6 + w[i] * 5 + fine[i] * 1.4
            let t: Float = sin(s * .pi) * 0.5 + 0.5
            func step(_ a: Float, _ b: Float) -> Float { let x = min(max((t - a) / (b - a), 0), 1); return x * x * (3 - 2 * x) }
            let f1 = step(0.3, 0.55), f2 = step(0.62, 0.95) * 0.75
            let c = base * (1 - f1) + mid * f1
            return c * (1 - f2) + mark * f2
        }
        shade(&img, fbm(sx: 3, sy: 3, 44, 3), 18)
        if granite {
            var r = SplitMix(135)
            for i in 0..<count {
                let u = r.unit()
                if u < 0.05 { img[i] = img[i] * 0.5 + mark * 0.5 } else if u < 0.07 { img[i] = img[i] * 0.5 + V(repeating: 250) * 0.5 }
            }
        }
        return img
    }

    private func concrete() -> [V] {
        var img = flat(base)
        mix(&img, mark, fbm(sx: 0.9, sy: 0.9, 6, 6).map { min(max(($0 - 0.3) * 1.8, 0), 1) * 0.55 })
        var r = SplitMix(106)
        for i in 0..<count {
            if r.unit() < 0.012 { img[i] = img[i] * 0.8 + mark * 0.2 }
            img[i] += V(repeating: (r.unit() - 0.5) * 10)
        }
        return img
    }

    private func soapstone() -> [V] {
        var img = flat(base)
        shade(&img, fbm(sx: 1.5, sy: 1.5, 37, 5), 22)
        for k in 0..<4 {
            let nz = fbm(xx.map { $0 * (1.2 + Float(k) * 0.5) + Float(k) * 3 }, yy.map { $0 * (0.6 + Float(k) * 0.3) }, 37 + 3 * k, 6)
            mix(&img, mark, nz.map { pow(Self.ridge($0), 90) * 0.55 })
        }
        return img
    }

    private func travertine() -> [V] {
        let w = fbm(sx: 0.6, sy: 0.6, 4, 4)
        let streak = fbm(sx: 6, sy: 1.2, 7, 4)
        var img = flat(base)
        mix(&img, mark, (0..<count).map { i -> Float in
            let t = sin((yy[i] * 3.2 + w[i] * 1.5) * .pi) * 0.5 + 0.5 + (streak[i] - 0.5) * 0.6
            return min(max((t - 0.45) * 1.4, 0), 1) * 0.6
        })
        return img
    }

    private func limestone() -> [V] {
        var img = flat(base)
        shade(&img, fbm(sx: 2.5, sy: 2.5, 39, 5), 16)
        var r = SplitMix(139)
        for i in 0..<count where r.unit() < 0.03 { img[i] = img[i] * 0.85 + mark * 0.15 }
        return img
    }

    private func onyx() -> [V] {
        let warp = fbm(sx: 0.8, sy: 0.8, 41, 5)
        let c2 = second
        return (0..<count).map { i -> V in
            let dx = xx[i] - 1.2, dy = yy[i] - 3.6
            let d = (dx * dx + dy * dy * 1.6).squareRoot() + (warp[i] - 0.5) * 1.6
            let t = sin(d * 7.5 * .pi) * 0.5 + 0.5, t2 = sin(d * 23 * .pi) * 0.5 + 0.5
            let a = min(max(pow(t, 3) * 0.75 + pow(t2, 8) * 0.25, 0), 1)
            var c = base * (1 - a) + mark * a
            if let c2 {
                let b = min(max(pow(sin(d * 3.1 * .pi) * 0.5 + 0.5, 10) * 0.6, 0), 1)
                c = c * (1 - b) + c2 * b
            }
            // Lit from behind, brighter towards one side.
            let gx: Float = xx[i] - 2.4, gy: Float = yy[i] - 1.8
            let glow: Float = exp(-(gx * gx + gy * gy) / 4)
            return c * (0.88 + 0.22 * glow)
        }
    }

    // MARK: Shapes drawn on top

    private func flecks(_ g: CGContext, seed: Int) {
        var r = SplitMix(seed + 500)
        let sets: [(V, Int, Float, Float)] = [(mark, 1400, 1, 4), (second ?? V(repeating: 255), 700, 1, 3)]
        for (c, number, lo, hi) in sets {
            for _ in 0..<Int(Float(number) * s * s) {
                let x = r.unit() * Float(n), y = r.unit() * Float(n)
                let d = r.range(lo, hi) * s, h = d * r.range(0.6, 1.4)
                g.setFillColor(red: CGFloat(c.x / 255), green: CGFloat(c.y / 255), blue: CGFloat(c.z / 255),
                               alpha: CGFloat(r.range(0.55, 1)))
                g.fillEllipse(in: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(d), height: CGFloat(h)))
            }
        }
    }

    private func chips(_ g: CGContext, seed: Int) {
        var r = SplitMix(seed + 500)
        let colours = [mark, second ?? V(repeating: 255), V(124, 127, 132), mark]
        for _ in 0..<Int(Float(n * n) / 260) {
            let x = r.unit() * Float(n), y = r.unit() * Float(n), size = r.range(1.5, 7) * s
            let sides = 4 + Int(r.unit() * 3)
            var angles = (0..<sides).map { _ in r.unit() * 2 * .pi }
            angles.sort()
            let c = colours[Int(r.unit() * 4) % 4]
            g.setFillColor(red: CGFloat(c.x / 255), green: CGFloat(c.y / 255), blue: CGFloat(c.z / 255), alpha: 1)
            g.beginPath()
            for (k, a) in angles.enumerated() {
                let p = CGPoint(x: CGFloat(x + size * cos(a) * r.range(0.6, 1.3)), y: CGFloat(y + size * sin(a) * r.range(0.6, 1.3)))
                if k == 0 { g.move(to: p) } else { g.addLine(to: p) }
            }
            g.closePath()
            g.fillPath()
        }
    }

    /// Travertine's pits: small dark holes running with its bands.
    private func pits(_ g: CGContext, seed: Int) {
        var r = SplitMix(seed)
        for _ in 0..<Int(Float(n * n) / 2400) {
            let x = r.unit() * Float(n), y = r.unit() * Float(n)
            let l = r.range(1.5, 7) * s, h = r.range(0.6, 1.6) * s
            g.setFillColor(red: 0.25, green: 0.2, blue: 0.12, alpha: CGFloat(0.3 * r.range(0.4, 1)))
            g.fillEllipse(in: CGRect(x: CGFloat(x - l), y: CGFloat(y - h), width: CGFloat(2 * l), height: CGFloat(2 * h)))
        }
    }

    /// Limestone's little fossil shells.
    private func fossils(_ g: CGContext, seed: Int) {
        var r = SplitMix(seed + 500)
        let c = mark
        g.setStrokeColor(red: CGFloat(c.x / 255), green: CGFloat(c.y / 255), blue: CGFloat(c.z / 255), alpha: 0.35)
        g.setLineWidth(CGFloat(max(1, s)))
        for _ in 0..<Int(Float(n * n) / 16000) {
            let x = r.unit() * Float(n), y = r.unit() * Float(n), rad = r.range(1.5, 4) * s
            let a0 = r.unit() * 2 * .pi
            g.beginPath()
            g.addArc(center: CGPoint(x: CGFloat(x), y: CGFloat(y)), radius: CGFloat(rad),
                     startAngle: CGFloat(a0), endAngle: CGFloat(a0 + 2.2), clockwise: false)
            g.strokePath()
        }
    }

    private func image(_ img: [V], overlay: ((CGContext) -> Void)?) -> UIImage {
        var bytes = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count {
            let c = simd_clamp(img[i], V(repeating: 0), V(repeating: 255))
            bytes[i * 4] = UInt8(c.x); bytes[i * 4 + 1] = UInt8(c.y); bytes[i * 4 + 2] = UInt8(c.z)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let g = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return UIImage() }
        bytes.withUnsafeMutableBytes { buf in
            if let data = g.data { data.copyMemory(from: buf.baseAddress!, byteCount: count * 4) }
        }
        overlay?(g)
        guard let cg = g.makeImage() else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}
