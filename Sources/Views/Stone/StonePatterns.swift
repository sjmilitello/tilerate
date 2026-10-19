import simd
import UIKit

/// Stone drawn from its pattern and colours (owner, 2026-10-17): the
/// picker's swatches and preview, and stone in 3-D and the PDF pictures.
/// Each pattern is a photo of real stone (owner, 2026-10-18: the patterns
/// drawn from noise weren't realistic), kept as a map of where its markings
/// are, and recoloured: the base colour where the stone is at its middle
/// tone, the markings colour where its veins, flecks or bands are, the
/// second colour at their soft edges, and the other side of the middle tone
/// a little lighter (or darker). The maps are `StoneMap-<pattern>` in the
/// asset catalogue, made from ambientCG textures (CC0, public domain; see
/// `StoneMaps.source`), shrunk to 1024 px so they still tile.
enum StonePatterns {
    /// The picker's colours (owner, 2026-10-18): eight families, each in
    /// even steps light to dark (OKLCH), fitted to the colours measured from
    /// Cambria's 159 quartz designs and the common US granites and marbles —
    /// every one of those within a close match. Whites by undertone; cool and
    /// warm grays (not greige) down to black; gold, red, blue and green with
    /// a full run each, and a soapstone green-gray.
    static let families: [(name: String, colours: [String])] = [
        ("Whites", ["#FAFAFA", "#F0F4F8", "#F7F3EB", "#F7EEDB", "#E7E6E3"]),
        ("Cool gray", ["#D7DFE8", "#BDC5CE", "#A4ACB4", "#8C939B", "#747B83", "#5A6169", "#424850", "#282F35", "#12171B", "#050607"]),
        ("Warm gray", ["#E5DDD2", "#CBC3B8", "#B1AA9F", "#989187", "#80796F", "#665F56", "#4D473E", "#332D24", "#191510"]),
        ("Beige", ["#EAD9BA", "#D9C09D", "#C2A583", "#AC8B69", "#926F51", "#77553C", "#5A3E2B", "#3E281B"]),
        ("Gold", ["#EAD5AB", "#DCB87A", "#C99B5A", "#AE7F3F", "#8E612C", "#674420"]),
        ("Red", ["#EAC8C2", "#DAA198", "#D24C49", "#B00A1D", "#833F27", "#54261F"]),
        ("Blue", ["#CFE1ED", "#99BDD3", "#7996AF", "#27709C", "#384F68", "#172A41"]),
        ("Green", ["#C2D8C5", "#95B49A", "#66927A", "#586A46", "#46504B", "#2E4A34", "#1D2A1D"]),
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
        Renderer.render(look, n: pixels)
    }

    static func cachedPattern(_ look: StoneAppearance, pixels: Int) -> UIImage? {
        cache.object(forKey: "\(look.drawingKey)@\(pixels)" as NSString)
    }

    /// The stone as drawn: its photo, else its pattern. Main thread.
    static func image(_ look: StoneAppearance, pixels: Int) -> UIImage {
        if let id = look.photoID, let photo = TilePhotos.image(id) { return photo }
        return turned(patternImage(look, pixels: pixels), look)
    }

    /// Veins across: the same pixels, turned a quarter (no redrawing).
    static func turned(_ image: UIImage, _ look: StoneAppearance) -> UIImage {
        guard look.runsAcross, let cg = image.cgImage else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .right)
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

/// The photographed stone behind each pattern.
enum StoneMaps {
    /// The photo each map was made from: ambientCG textures (CC0), and thin
    /// and bold veins Pexels photos (free under the Pexels licence; 3847500
    /// by ready made, 2341290 by H&CO; owner's call, 2026-10-18: no CC0 photo
    /// has a Calacatta's long veins).
    static func source(_ p: StoneAppearance.Pattern) -> String {
        switch p {
        case .softVeins: "Pexels 3847500, its left end softened"
        case .thinVeins: "Pexels 3847500"
        case .boldVeins: "Pexels 2341290"
        case .web: "Marble017"
        case .breccia: "Marble014"
        case .sweeping: "Onyx001"
        case .quartziteLinear: "Onyx004"
        case .quartziteCloudy: "Marble012"
        case .graniteFine: "Granite002A"
        case .graniteCoarse: "Granite007A"
        case .solid: "Marble015"
        case .concrete: "Concrete034"
        case .terrazzo: "Terrazzo013"
        case .soapstone: "Marble016"
        case .travertine: "Travertine009"
        case .onyx: "Onyx002"
        case .slate: "Rock020"
        case .woodStraight: "Wood049"
        case .woodRustic: "Wood096"
        }
    }

    /// Whether the photo's markings are darker than its middle tone, so the
    /// rest of it lightens the base; else it darkens it.
    static func darkMarkings(_ p: StoneAppearance.Pattern) -> Bool {
        switch p {
        case .softVeins, .thinVeins, .boldVeins, .sweeping, .breccia, .quartziteCloudy, .graniteFine, .concrete, .terrazzo, .travertine, .woodRustic: true
        default: false
        }
    }

    /// How much stone one map covers, in feet: its real size (owner,
    /// 2026-10-18), so bold veins run like a slab's and granite's flecks stay small.
    static func spanFt(_ p: StoneAppearance.Pattern) -> Double {
        switch p {
        case .sweeping: 7
        case .woodStraight, .woodRustic: 4
        case .boldVeins, .onyx: 6
        case .thinVeins, .quartziteLinear: 5
        case .softVeins, .breccia, .quartziteCloudy, .concrete, .travertine: 4
        case .web, .solid, .soapstone, .slate: 3
        case .graniteCoarse: 2.5
        case .terrazzo: 2
        case .graniteFine: 1.5
        }
    }

    /// The stone's surface (a normal map, from the same photo) for 3-D.
    static func surface(_ p: StoneAppearance.Pattern) -> UIImage? { UIImage(named: "StoneNormal-\(p.rawValue)") }

    /// The map at `n` pixels square: 128 the stone's middle tone, up to 255
    /// fully its markings, down to 0 the other way.
    static func map(_ p: StoneAppearance.Pattern, n: Int) -> [UInt8]? {
        guard let cg = UIImage(named: "StoneMap-\(p.rawValue)")?.cgImage,
              let g = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = g.data else { return nil }
        g.interpolationQuality = .high
        g.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: n * n))
    }
}

private enum Renderer {
    typealias V = SIMD3<Float>

    static func render(_ look: StoneAppearance, n: Int) -> UIImage {
        let n = max(8, n)
        let p = look.pattern
        let base = StonePatterns.rgb(look.base)
        let marks = p.usesMarkings ? StonePatterns.rgb(look.markings) : base * 0.9
        let second = p.usesSecond ? look.second.map(StonePatterns.rgb) : nil
        let other = StoneMaps.darkMarkings(p) ? V(repeating: 255) : V(repeating: 0)
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        let map = StoneMaps.map(p, n: n)
        for i in 0..<(n * n) {
            var c = base
            if let map {
                let d = (Float(map[i]) - 128) / 127
                let v = max(0, min(1, d)), o = max(0, min(1, -d))
                c = c * (1 - o * 0.35) + other * (o * 0.35)
                c = c * (1 - v) + marks * v
                if let second {
                    let x = (v - 0.4) / 0.14
                    let w = exp(-x * x) * 0.85
                    c = c * (1 - w) + second * w
                }
            }
            c = simd_clamp(c, V(repeating: 0), V(repeating: 255))
            bytes[i * 4] = UInt8(c.x); bytes[i * 4 + 1] = UInt8(c.y); bytes[i * 4 + 2] = UInt8(c.z)
        }
        let made: CGImage? = bytes.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        return made.map { UIImage(cgImage: $0) } ?? UIImage()
    }
}
