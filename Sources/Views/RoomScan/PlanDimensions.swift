import Foundation

// The room's dimensions as a model (owner asked 2026-10-08 for "the
// intelligent dimensioning from FabSpecPro"). Adapted from FabSpecPro's
// GeoDimension — the engine builds one list of dimensions and the drawing
// only renders it — as TileRate's own copy: nothing here is shared with
// FabSpecPro, and FabSpecPro's files are never changed for it.
//
// Built in plan feet from the room and the area's choices; laid out on screen
// by `PlanDimensionPlacer` each time the plan is drawn.

struct PlanDimension: Identifiable {
    enum Kind {
        /// A whole scanned wall, outside the room — always the furthest out.
        case overall
        /// One stretch of a wall another wall runs into partway (corner to
        /// partition, partition to corner). Round the outside, the stretches
        /// share one row just inside the overall (FabSpecPro's seam chain), so
        /// two of them never cross in an inside corner; along a partition they
        /// go on the side the other wall comes from.
        case chain
        /// Something in the room: a wall drawn in, the shower floor, the curb, a bench.
        case feature
    }
    enum Ink { case wall, floor, curb, bench, opening }

    var id: String
    var kind: Kind
    /// The two points measured, in plan feet.
    var a: ScannedRoom.Point
    var b: ScannedRoom.Point
    /// Unit normal, plan feet: the side the dimension line goes on.
    var side: ScannedRoom.Point
    /// Feet.
    var value: Double
    var text: String
    /// Shorter words for a tight spot: the number alone.
    var shortText: String? = nil
    var ink: Ink
    /// Points from the measured edge to where the extension lines start.
    var gap: Double = 4
    /// The wall it belongs to and which side, so an overall can be kept
    /// beyond the chains on the same side of the same wall.
    var wallID: UUID? = nil
    /// It may go on the other side when its own side has no clean place —
    /// a partition, with room either side of it.
    var eitherSide = false
    /// A stretch on the row round the outside, where the overall would be
    /// (which then moves one rung further out).
    var outsideRow = false
    /// Points from the edge to the first rung, when not the usual for its kind.
    var offset: Double? = nil
}

enum PlanDimensions {
    /// Every dimension the plan shows.
    static func build(room: ScannedRoom,
                      floor: AreaTakeoff.FloorRect?,
                      curbEdges: [(ScannedRoom.Point, ScannedRoom.Point)],
                      items: [AreaTakeoff.Item],
                      inward: (ScannedRoom.Wall, Int) -> ScannedRoom.Point) -> [PlanDimension] {
        var out: [PlanDimension] = []
        let center = middle(of: room)
        let floorMid = floor.map { r -> ScannedRoom.Point in
            let c = r.corners
            return .init(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        }

        for w in room.walls where w.lengthFt > 0.05 {
            let u = unit(w.start, w.end)
            var n = ScannedRoom.Point(x: -u.y, y: u.x)
            let mid = halfway(w.start, w.end)
            // A scanned wall: outside the room. One drawn in: away from the shower.
            let from = w.planned ? (floorMid ?? center) : center
            if dot(sub(from, mid), n) > 0 { n = neg(n) }
            out.append(PlanDimension(id: "wall-\(w.id)", kind: w.planned ? .feature : .overall,
                                     a: w.start, b: w.end, side: n, value: w.lengthFt,
                                     text: inchText(w.lengthFt), ink: .wall,
                                     gap: w.planned ? 4 + w.thicknessIn / 24 : 4, wallID: w.id,
                                     eitherSide: w.planned || isPartition(w, in: room)))
            // Its stretches, where other walls run into it partway.
            let outside = !w.planned && !isPartition(w, in: room)
            for (k, chain) in stretches(of: w, in: room, onSide: outside ? n : nil).enumerated() {
                for i in 1..<chain.at.count where chain.at[i] - chain.at[i - 1] > 0.05 {
                    let len = chain.at[i] - chain.at[i - 1]
                    out.append(PlanDimension(id: "chain-\(w.id)-\(k)-\(i)", kind: .chain,
                                             a: room.point(on: w, along: chain.at[i - 1]),
                                             b: room.point(on: w, along: chain.at[i]),
                                             side: chain.side, value: len, text: inchText(len),
                                             ink: .wall, wallID: w.id, outsideRow: outside))
                }
            }
        }

        // The shower floor's width and depth, inside it, on the sides away from
        // the curb. A side that is all curb is left to the curb's own number:
        // two numbers on sides that meet would cross in their corner.
        if let r = floor {
            let c = r.corners
            func isCurb(_ p: ScannedRoom.Point, _ q: ScannedRoom.Point) -> Bool {
                curbEdges.contains { e in
                    let m = halfway(e.0, e.1)
                    let along = unit(p, q)
                    return abs(cross(sub(m, p), along)) < 0.1
                }
            }
            let mid = halfway(c[0], c[2])
            func wholeCurb(_ p: ScannedRoom.Point, _ q: ScannedRoom.Point) -> Bool {
                curbEdges.contains { e in
                    (distance(e.0, p) < 0.1 && distance(e.1, q) < 0.1) || (distance(e.0, q) < 0.1 && distance(e.1, p) < 0.1)
                }
            }
            for (p, q, alt, value, name) in [(c[0], c[1], (c[3], c[2]), r.widthFt, "width"),
                                             (c[0], c[3], (c[1], c[2]), r.depthFt, "depth")] {
                if wholeCurb(p, q) || wholeCurb(alt.0, alt.1) { continue }
                let (e0, e1) = isCurb(p, q) && !isCurb(alt.0, alt.1) ? alt : (p, q)
                let toward = unit(halfway(e0, e1), mid)
                out.append(PlanDimension(id: "floor-\(name)", kind: .feature, a: e0, b: e1, side: toward,
                                         value: value, text: inchText(value), ink: .floor, gap: -2))
            }
        }

        // The curb: its length, outside the floor.
        for (k, (a, b)) in curbEdges.enumerated() {
            let len = distance(a, b)
            guard len > 0.05 else { continue }
            let u = unit(a, b)
            var n = ScannedRoom.Point(x: -u.y, y: u.x)
            if let m = floorMid, dot(sub(halfway(a, b), m), n) < 0 { n = neg(n) }
            out.append(PlanDimension(id: "curb-\(k)", kind: .feature, a: a, b: b, side: n, value: len,
                                     text: "Curb \(inchText(len))", shortText: inchText(len), ink: .curb))
        }

        // Framed benches: length along the front, depth at the end.
        for item in items where item.kind == .framedBench {
            guard let w = room.wall(item.wallID) else { continue }
            let n = inward(w, item.face)
            let skin = w.planned ? w.thicknessIn / 24 : 0
            let d = skin + item.depthIn / 12
            func pt(_ along: Double, _ off: Double) -> ScannedRoom.Point {
                let p = room.point(on: w, along: along)
                return .init(x: p.x + n.x * off, y: p.y + n.y * off)
            }
            out.append(PlanDimension(id: "bench-\(item.id)", kind: .feature,
                                     a: pt(item.fromFt, d), b: pt(item.toFt, d), side: n,
                                     value: item.widthFt, text: inchText(item.widthFt), ink: .bench, gap: 2))
            // Its depth, across its far end.
            let u = unit(w.start, w.end)
            let end = item.toFt
            out.append(PlanDimension(id: "bench-depth-\(item.id)", kind: .feature,
                                     a: pt(end, skin), b: pt(end, d), side: u,
                                     value: item.depthIn / 12, text: inchText(item.depthIn / 12),
                                     ink: .bench, gap: 2))
        }
        return out
    }

    /// A wall with an end partway along another wall — a partition, with
    /// room on both sides — rather than one round the outside.
    static func isPartition(_ w: ScannedRoom.Wall, in room: ScannedRoom) -> Bool {
        room.walls.contains { o in
            guard o.id != w.id, o.lengthFt > 0.05 else { return false }
            let u = unit(o.start, o.end), n = ScannedRoom.Point(x: -u.y, y: u.x)
            return [w.start, w.end].contains { p in
                let t = dot(sub(p, o.start), u)
                return abs(dot(sub(p, o.start), n)) < 0.25 && t > 0.1 && t < o.lengthFt - 0.1
            }
        }
    }

    /// Where other walls run into `w` partway along it (within 3″ of its
    /// line, not at its own ends), as feet along it with 0 and its length,
    /// one chain per side they come in from — or all on one row, `onSide`.
    static func stretches(of w: ScannedRoom.Wall, in room: ScannedRoom,
                          onSide: ScannedRoom.Point? = nil) -> [(at: [Double], side: ScannedRoom.Point)] {
        let len = w.lengthFt
        guard len > 0.05 else { return [] }
        let u = unit(w.start, w.end)
        let n = ScannedRoom.Point(x: -u.y, y: u.x)
        var left: [Double] = [], right: [Double] = []
        for o in room.walls where o.id != w.id && o.lengthFt > 0.05 {
            for (p, q) in [(o.start, o.end), (o.end, o.start)] {
                let t = dot(sub(p, w.start), u)
                let d = dot(sub(p, w.start), n)
                guard abs(d) < 0.25, t > 0.1, t < len - 0.1 else { continue }
                if dot(sub(q, w.start), n) > 0 { left.append(t) } else { right.append(t) }
            }
        }
        var out: [(at: [Double], side: ScannedRoom.Point)] = []
        let rows = onSide.map { [(left + right, $0)] } ?? [(left, n), (right, neg(n))]
        for (ts, side) in rows where !ts.isEmpty {
            var at = [0.0]
            for t in ts.sorted() where t - at.last! > 0.05 { at.append(t) }
            if len - at.last! > 0.05 { at.append(len) } else { at[at.count - 1] = len }
            out.append((at, side))
        }
        return out
    }

    // MARK: Plan geometry

    static func middle(of room: ScannedRoom) -> ScannedRoom.Point {
        let n = Double(max(room.walls.count, 1))
        return .init(x: room.walls.map { ($0.start.x + $0.end.x) / 2 }.reduce(0, +) / n,
                     y: room.walls.map { ($0.start.y + $0.end.y) / 2 }.reduce(0, +) / n)
    }
    static func sub(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> ScannedRoom.Point { .init(x: a.x - b.x, y: a.y - b.y) }
    static func neg(_ a: ScannedRoom.Point) -> ScannedRoom.Point { .init(x: -a.x, y: -a.y) }
    static func dot(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> Double { a.x * b.x + a.y * b.y }
    static func cross(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> Double { a.x * b.y - a.y * b.x }
    static func distance(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> Double { hypot(b.x - a.x, b.y - a.y) }
    static func halfway(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> ScannedRoom.Point { .init(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    static func unit(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> ScannedRoom.Point {
        let l = max(distance(a, b), 1e-9)
        return .init(x: (b.x - a.x) / l, y: (b.y - a.y) / l)
    }
}
