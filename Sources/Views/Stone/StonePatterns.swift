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
        Renderer.render(look, n: pixels)
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

/// The photographed stone behind each pattern.
enum StoneMaps {
    /// The ambientCG texture each map was made from (CC0).
    static func source(_ p: StoneAppearance.Pattern) -> String {
        switch p {
        case .softVeins: "Marble001"
        case .boldVeins: "Marble006"
        case .web: "Marble017"
        case .breccia: "Marble014"
        case .quartziteLinear: "Onyx004"
        case .quartziteCloudy: "Marble012"
        case .graniteFine: "Granite002A"
        case .graniteCoarse: "Granite003A"
        case .graniteFlowing: "Onyx012"
        case .solid: "Marble015"
        case .concrete: "Concrete034"
        case .terrazzo: "Terrazzo013"
        case .soapstone: "Marble016"
        case .travertine: "Travertine004"
        case .limestone: "Marble026"
        case .onyx: "Onyx002"
        }
    }

    /// Whether the photo's markings are darker than its middle tone, so the
    /// rest of it lightens the base; else it darkens it.
    static func darkMarkings(_ p: StoneAppearance.Pattern) -> Bool {
        switch p {
        case .softVeins, .breccia, .quartziteCloudy, .graniteFine, .graniteCoarse, .concrete, .terrazzo, .limestone: true
        default: false
        }
    }

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
