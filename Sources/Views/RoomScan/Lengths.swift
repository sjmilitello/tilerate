import Foundation

// Lengths (owner's calls, 2026-10-08): every length shown in inches, to the
// nearest sixteenth — 106 1/2″, 13 1/8″, 3/16″ (`inchText`) — and typed the
// way a tape is read, in inches or feet and inches: 106 1/2, 106.5, 3/4,
// 8' 10 1/2", 8'10-1/2. (Feet and inches were shown for a day; inches crowd
// the drawings less — 2′ 10″ is 34″ — and are how a shower is talked about.)
// The fraction reading and reducing come from FabSpecPro's MeasurementParser.

enum Lengths {
    /// A length in inches, rounded to the sixteenth: feet, whole inches, and
    /// the fraction reduced (3/16, 1/2…; 0/16 when none).
    static func parts(inches: Double) -> (negative: Bool, feet: Int, inches: Int, num: Int, den: Int) {
        let negative = inches < 0
        let sixteenths = Int((abs(inches) * 16).rounded())
        var whole = sixteenths / 16
        var num = sixteenths % 16
        var den = 16
        if num > 0 {
            let g = gcd(num, den)
            num /= g
            den /= g
        }
        let feet = whole / 12
        whole %= 12
        return (negative, feet, whole, num, den)
    }

    /// 106 1/2″, 13 1/8″, 3/16″, 0″.
    static func inchesText(feet: Double) -> String {
        let p = parts(inches: feet * 12)
        let sign = p.negative && (p.feet > 0 || p.inches > 0 || p.num > 0) ? "−" : ""
        let whole = p.feet * 12 + p.inches
        let frac = p.num > 0 ? "\(p.num)/\(p.den)" : ""
        if whole > 0 && !frac.isEmpty { return "\(sign)\(whole) \(frac)″" }
        if !frac.isEmpty { return "\(sign)\(frac)″" }
        return "\(sign)\(whole)″"
    }

    /// The same with plain keys, to edit: 106 1/2".
    static func typedInches(_ inches: Double) -> String {
        inchesText(feet: inches / 12).replacingOccurrences(of: "″", with: "\"").replacingOccurrences(of: "−", with: "-")
    }

    /// Inches from what was typed: feet before a ' (or ′), then inches with an
    /// optional fraction ("10 1/2", "10-1/2", "10.5", "1/2"); no ' means it's
    /// all inches. nil when it can't be read (yet).
    static func parse(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "′", with: "'").replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "″", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: ",", with: ".")
        if s.hasSuffix("\"") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let tick = s.firstIndex(of: "'") {
            guard let feet = Double(s[..<tick].trimmingCharacters(in: .whitespaces)) else { return nil }
            var rest = String(s[s.index(after: tick)...]).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("-") { rest.removeFirst() }
            rest = rest.trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return feet * 12 }
            guard let inches = parseInches(rest) else { return nil }
            return feet * 12 + inches
        }
        return parseInches(s)
    }

    /// "10", "10.5", "10 1/2", "10-1/2", "1/2" → inches.
    static func parseInches(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let value = Double(trimmed) { return value }
        let parts = trimmed.replacingOccurrences(of: "-", with: " ").split(separator: " ")
        if parts.count == 2, let whole = Double(parts[0]), let f = fraction(String(parts[1])) { return whole + f }
        if parts.count == 1, let f = fraction(String(parts[0])) { return f }
        return nil
    }

    private static func fraction(_ raw: String) -> Double? {
        let p = raw.split(separator: "/")
        guard p.count == 2, let n = Double(p[0]), let d = Double(p[1]), d != 0 else { return nil }
        return n / d
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
