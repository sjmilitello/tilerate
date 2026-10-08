import Foundation

// Lengths on the plan and the walls (owner's call, 2026-10-08): everything in
// feet and inches, to the nearest sixteenth — 8′ 10 1/2″, 13 1/8″, 3/16″ — and
// typed the way a tape is read: 8' 10 1/2", 8'10-1/2, 106 1/2, 106.5, 3/4.
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

    /// 8′ 10 1/2″, 8′ 0″ (or 8′ when `zeroInches` is false), 13 1/8″, 3/16″.
    static func text(feet: Double, zeroInches: Bool = true) -> String {
        let p = parts(inches: feet * 12)
        let sign = p.negative && (p.feet > 0 || p.inches > 0 || p.num > 0) ? "−" : ""
        let frac = p.num > 0 ? "\(p.num)/\(p.den)" : ""
        let inch: String
        if p.inches > 0 && !frac.isEmpty { inch = "\(p.inches) \(frac)″" }
        else if p.inches > 0 { inch = "\(p.inches)″" }
        else if !frac.isEmpty { inch = "\(frac)″" }
        else { inch = "0″" }
        if p.feet == 0 { return sign + inch }
        if inch == "0″" && !zeroInches { return "\(sign)\(p.feet)′" }
        return "\(sign)\(p.feet)′ \(inch)"
    }

    /// The same, written with plain keys so it can be edited: 8' 10 1/2".
    static func typed(inches: Double) -> String {
        text(feet: inches / 12).replacingOccurrences(of: "′", with: "'").replacingOccurrences(of: "″", with: "\"")
            .replacingOccurrences(of: "−", with: "-")
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
