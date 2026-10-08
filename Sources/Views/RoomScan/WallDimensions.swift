import Foundation

// The face-on wall's dimensions, for the same placer as the plan
// (`PlanDimensionPlacer`, adapted from FabSpecPro; TileRate's own copy).
// Wall coordinates go in as plan points: x is feet along the wall from its
// start, y is feet up from the floor.
//
//  - Along the bottom: every door, window, opening, niche, bench and corner
//    piece's sides, end to end, on one row; the wall's length beyond it.
//  - Up the right-hand end: every bottom and top of those, and the top of
//    this area's tile, on one column; the wall's height beyond it.
//  - The chosen door, window, niche or bench: its own width over it and its
//    height beside it — the numbers it's framed and cut to.

enum WallDimensions {
    /// Something on the wall, in feet: along and up.
    struct Span {
        var from: Double, to: Double, bottom: Double, top: Double
    }

    /// Groups for the hierarchy: the length beyond the row, the height beyond the column.
    static let alongID = UUID(uuidString: "6A1E0000-0000-4000-8000-000000000001")!
    static let upID = UUID(uuidString: "6A1E0000-0000-4000-8000-000000000002")!

    static func build(lengthFt: Double, heightFt: Double, spans: [Span], tileTops: [Double],
                      chosen: Span?) -> [PlanDimension] {
        var out: [PlanDimension] = []
        let down = ScannedRoom.Point(x: 0, y: -1), right = ScannedRoom.Point(x: 1, y: 0)
        func p(_ x: Double, _ y: Double) -> ScannedRoom.Point { .init(x: x, y: y) }
        func marks(_ values: [Double], within limit: Double) -> [Double] {
            var at: [Double] = []
            for v in ([0, limit] + values).map({ min(max(0, $0), limit) }).sorted()
            where at.last.map({ v - $0 > 1.0 / 32 }) ?? true { at.append(v) }
            if let last = at.last, limit - last < 1.0 / 32 { at[at.count - 1] = limit }
            return at
        }

        // Along the bottom.
        let along = marks(spans.flatMap { [$0.from, $0.to] }, within: lengthFt)
        if along.count > 2 {
            for k in 1..<along.count {
                let len = along[k] - along[k - 1]
                out.append(PlanDimension(id: "along-\(k)", kind: .chain, a: p(along[k - 1], 0), b: p(along[k], 0),
                                         side: down, value: len, text: inchText(len), ink: .wall,
                                         wallID: alongID, outsideRow: true, offset: 12))
            }
        }
        out.append(PlanDimension(id: "length", kind: .overall, a: p(0, 0), b: p(lengthFt, 0), side: down,
                                 value: lengthFt, text: inchText(lengthFt), ink: .wall,
                                 wallID: alongID, offset: 12))

        // Up the right-hand end.
        let up = marks(spans.flatMap { [$0.bottom, $0.top] } + tileTops, within: heightFt)
        if up.count > 2 {
            for k in 1..<up.count {
                let len = up[k] - up[k - 1]
                out.append(PlanDimension(id: "up-\(k)", kind: .chain, a: p(lengthFt, up[k - 1]), b: p(lengthFt, up[k]),
                                         side: right, value: len, text: inchText(len), ink: .wall,
                                         wallID: upID, outsideRow: true, offset: 12))
            }
        }
        out.append(PlanDimension(id: "height", kind: .overall, a: p(lengthFt, 0), b: p(lengthFt, heightFt), side: right,
                                 value: heightFt, text: inchText(heightFt), ink: .wall,
                                 wallID: upID, offset: 12))

        // The chosen one's own size.
        if let c = chosen, c.to - c.from > 1.0 / 32, c.top - c.bottom > 1.0 / 32 {
            let w = c.to - c.from, h = c.top - c.bottom
            out.append(PlanDimension(id: "chosen-width", kind: .feature, a: p(c.from, c.top), b: p(c.to, c.top),
                                     side: .init(x: 0, y: 1), value: w, text: inchText(w), ink: .opening,
                                     gap: 2, eitherSide: true, offset: 10))
            out.append(PlanDimension(id: "chosen-height", kind: .feature, a: p(c.from, c.bottom), b: p(c.from, c.top),
                                     side: .init(x: -1, y: 0), value: h, text: inchText(h), ink: .opening,
                                     gap: 2, eitherSide: true, offset: 10))
        }
        return out
    }
}
