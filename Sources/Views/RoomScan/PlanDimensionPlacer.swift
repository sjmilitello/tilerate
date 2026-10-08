import CoreGraphics

// Laying the room's dimensions out on screen without a clash. Adapted from
// FabSpecPro's SheetPlacer and SheetLayout (TileRate's own copy — nothing is
// shared, and FabSpecPro is never changed for it). What came across:
//
//  - Everything drawn claims its space first — walls and edges as lines,
//    wall letters as boxes — and a number may only go where nothing is.
//  - Lanes: each dimension's extension lines are reserved before any number
//    is placed, so no number sits across another dimension's extension line.
//  - D1/D2: a dimension line doesn't cross another dimension line, and an
//    extension line doesn't cross another dimension's line.
//  - D3: a number sits nearer the edge it measures than any other parallel
//    edge running past it, so it reads as that edge's.
//  - Stagger: numbers on parallel lines close together don't sit side by side.
//  - Hierarchy: inside stretches and things in the room nearest their edges;
//    a wall's overall length always furthest out.
// Each dimension tries rungs 13 pt apart, and along each rung the middle,
// then either side; a number too long for its line sits beside it, else
// past an end. If
// nothing is clean it takes the least crowded spot — a dimension is never
// left out.
//
// Not brought across: FabSpecPro's grid index (a room has a few dozen
// claims, not thousands), leaders, and the sheet margin search.

struct PlanDimensionPlacer {
    struct Placed {
        var dimension: PlanDimension
        /// The dimension line, in points.
        var line: (CGPoint, CGPoint)
        var witnesses: [(CGPoint, CGPoint)]
        var labelCenter: CGPoint
        /// Radians, kept upright.
        var angle: CGFloat
        var labelSize: CGSize
        /// The number's box on screen (axis-aligned, padding included).
        var box: CGRect
        /// Whether every rule held, or it took the least crowded spot.
        var clean: Bool
    }

    // Claims.
    private(set) var boxes: [CGRect] = []
    private(set) var labelOnlyBoxes: [CGRect] = []
    private(set) var lines: [(a: CGPoint, b: CGPoint)] = []
    private(set) var dimensionLines: [(a: CGPoint, b: CGPoint)] = []
    private(set) var witnessLines: [(a: CGPoint, b: CGPoint)] = []
    private(set) var lanes: [(a: CGPoint, b: CGPoint)] = []
    private(set) var dimLabels: [(along: CGPoint, center: CGPoint, half: CGFloat)] = []
    /// Edges a number could be read against (D3).
    var edges: [(a: CGPoint, b: CGPoint)] = []
    /// What's drawn — walls, floor, curb, tub — apart from dimension work.
    private(set) var obstacles: [(a: CGPoint, b: CGPoint)] = []
    /// The screen. A number for something on screen stays on it.
    var page: CGRect?

    /// Rungs apart: room for a 9.5 pt number between two dimension lines.
    static let step: CGFloat = 13
    static let rungs = 5

    mutating func claim(_ rect: CGRect) { boxes.append(rect) }
    mutating func claimForLabelsOnly(_ rect: CGRect) { labelOnlyBoxes.append(rect) }
    mutating func claim(from a: CGPoint, to b: CGPoint) {
        lines.append((a, b))
        obstacles.append((a, b))
    }

    // MARK: Laying out

    /// Places every dimension. `at` maps plan feet to points; `measure` gives
    /// a number's size as drawn.
    mutating func layout(_ dims: [PlanDimension], at: (ScannedRoom.Point) -> CGPoint,
                         measure: (String) -> CGSize) -> [Placed] {
        struct Prepared {
            var d: PlanDimension
            var pa: CGPoint, pb: CGPoint, ns: CGPoint, u: CGPoint, length: CGFloat
            var base: CGFloat, size: CGSize, angle: CGFloat
            var lanes: Set<Int> = []
        }
        var prepared: [Prepared] = dims.compactMap { d in
            let pa = at(d.a), pb = at(d.b)
            let length = hypot(pb.x - pa.x, pb.y - pa.y)
            guard length > 2 else { return nil }
            let q = at(.init(x: d.a.x + d.side.x, y: d.a.y + d.side.y))
            let ln = max(hypot(q.x - pa.x, q.y - pa.y), 1e-6)
            let ns = CGPoint(x: (q.x - pa.x) / ln, y: (q.y - pa.y) / ln)
            let u = CGPoint(x: (pb.x - pa.x) / length, y: (pb.y - pa.y) / length)
            var angle = atan2(u.y, u.x)
            if angle > .pi / 2 { angle -= .pi } else if angle < -.pi / 2 { angle += .pi }
            let usual: CGFloat = switch d.kind {
            case .overall: 24
            case .chain: d.outsideRow ? 24 : 14
            case .feature: d.ink == .bench ? 12 : 14
            }
            let base = d.offset.map { CGFloat($0) } ?? usual
            return Prepared(d: d, pa: pa, pb: pb, ns: ns, u: u, length: length,
                            base: base, size: measure(d.text), angle: angle)
        }
        // Lanes first: where every extension line will run, as far as its first two rungs.
        for i in prepared.indices {
            let p = prepared[i]
            let reach = p.base + Self.step + 5
            for e in [p.pa, p.pb] {
                lanes.append((shift(e, p.ns, CGFloat(p.d.gap)), shift(e, p.ns, reach)))
                prepared[i].lanes.insert(lanes.count - 1)
            }
        }
        // Nearest first: inside stretches and things in the room, then overalls;
        // short ones before long, since they have fewer places to go.
        func rank(_ k: PlanDimension.Kind) -> Int { k == .overall ? 1 : 0 }
        prepared.sort { (rank($0.d.kind), $0.length) < (rank($1.d.kind), $1.length) }

        // How far out each wall's side is already used, for the hierarchy.
        var used: [String: CGFloat] = [:]
        func sideKey(_ p: Prepared) -> String? {
            guard let id = p.d.wallID else { return nil }
            return "\(id)|\(Int((p.d.side.x * 2).rounded()))|\(Int((p.d.side.y * 2).rounded()))"
        }

        var out: [Placed] = []
        for p in prepared {
            var start = p.base
            if p.d.kind == .overall, let key = sideKey(p), let beyond = used[key] { start = max(start, beyond + Self.step) }
            struct Pick { var off: CGFloat; var center: CGPoint; var ns: CGPoint; var text: String; var size: CGSize; var score: Int }
            var chosen: Pick?
            var fallback: Pick?
            let onScreen = page.map { $0.contains(p.pa) && $0.contains(p.pb) } ?? false
            // Its own words, then the number alone (a curb's length without "Curb").
            let texts = [p.d.text] + (p.d.shortText.map { [$0] } ?? [])
            // Its own side, then (a partition) the other.
            let sides = p.d.eitherSide ? [p.ns, CGPoint(x: -p.ns.x, y: -p.ns.y)] : [p.ns]
            search: for (ti, text) in texts.enumerated() {
              let size = ti == 0 ? p.size : measure(text)
              // Along the line, and across it.
              let w = size.width + 8, h = size.height + 2
              let bw = abs(cos(p.angle)) * w + abs(sin(p.angle)) * h
              let bh = abs(sin(p.angle)) * w + abs(cos(p.angle)) * h
              for (s, ns) in sides.enumerated() {
                for rung in 0..<Self.rungs {
                    let off = start + CGFloat(rung) * Self.step
                    let a = shift(p.pa, ns, off), b = shift(p.pb, ns, off)
                    let wit = [(shift(p.pa, ns, CGFloat(p.d.gap)), shift(p.pa, ns, off + 5)),
                               (shift(p.pb, ns, CGFloat(p.d.gap)), shift(p.pb, ns, off + 5))]
                    let crossing = crossesDimensionWork(line: (a, b), witnesses: wit)
                    // Along the line if the number fits between the ends; else
                    // beside its middle, away from the edge, or past an end.
                    var spots: [(CGPoint, (CGPoint, CGPoint)?)] = []
                    if p.length >= w + 10 {
                        for t in [0.5, 0.35, 0.65, 0.2, 0.8] as [CGFloat] {
                            spots.append((CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), nil))
                        }
                    } else {
                        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                        spots.append((shift(mid, ns, h / 2 + 3), nil))
                        let past = w / 2 + 6
                        spots.append((shift(b, p.u, past), (b, shift(b, p.u, past - w / 2))))
                        spots.append((shift(a, p.u, -past), (a, shift(a, p.u, -past + w / 2))))
                    }
                    for (c, run) in spots {
                        let box = CGRect(x: c.x - bw / 2, y: c.y - bh / 2, width: bw, height: bh)
                        let clear = isClear(box, ignoringLanes: p.lanes)
                        // Half its length along the line (the text runs along it).
                        let stagger = staggerConflicts(along: p.u, center: c, half: w / 2)
                        let misread = misreads(label: c, own: (p.pa, p.pb))
                        // A line run out past its end mustn't cross a wall to get there.
                        let throughWall = run.map { r in obstacles.contains { Self.crossesCleanly(r.0, r.1, $0.a, $0.b) } } ?? false
                        let offPage = onScreen && !(page?.contains(box) ?? true)
                        let pick = Pick(off: off, center: c, ns: ns, text: text, size: size,
                                        score: (crossing ? 4 : 0) + crowding(box) * 3 + stagger + (misread ? 2 : 0)
                                            + (throughWall ? 6 : 0) + (offPage ? 8 : 0) + rung + s * 2 + ti)
                        if !crossing, clear, stagger == 0, !misread, !throughWall, !offPage {
                            chosen = pick
                            break search
                        }
                        if fallback == nil || pick.score < fallback!.score { fallback = pick }
                    }
                }
              }
            }
            let clean = chosen != nil
            guard let pick = chosen ?? fallback else { continue }
            let w = pick.size.width + 8, h = pick.size.height + 2
            let bw = abs(cos(p.angle)) * w + abs(sin(p.angle)) * h
            let bh = abs(sin(p.angle)) * w + abs(cos(p.angle)) * h
            let a = shift(p.pa, pick.ns, pick.off), b = shift(p.pb, pick.ns, pick.off)
            let wit = [(shift(p.pa, pick.ns, CGFloat(p.d.gap)), shift(p.pa, pick.ns, pick.off + 5)),
                       (shift(p.pb, pick.ns, CGFloat(p.d.gap)), shift(p.pb, pick.ns, pick.off + 5))]
            let box = CGRect(x: pick.center.x - bw / 2, y: pick.center.y - bh / 2, width: bw, height: bh)
            // The line runs out to a number placed past its end.
            var line = (a, b)
            let t = (pick.center.x - a.x) * p.u.x + (pick.center.y - a.y) * p.u.y
            if t > p.length { line.1 = shift(a, p.u, t - w / 2) }
            if t < 0 { line.0 = shift(a, p.u, t + w / 2) }
            dimensionLines.append((line.0, line.1)); lines.append((line.0, line.1))
            for wl in wit { witnessLines.append((wl.0, wl.1)); lines.append((wl.0, wl.1)) }
            boxes.append(box)
            dimLabels.append((p.u, pick.center, w / 2))
            if let key = sideKey(p) { used[key] = max(used[key] ?? 0, pick.off) }
            var d = p.d
            d.text = pick.text
            out.append(Placed(dimension: d, line: line, witnesses: wit, labelCenter: pick.center,
                              angle: p.angle, labelSize: pick.size, box: box, clean: clean))
        }
        return out
    }

    private func shift(_ p: CGPoint, _ n: CGPoint, _ d: CGFloat) -> CGPoint {
        CGPoint(x: p.x + n.x * d, y: p.y + n.y * d)
    }

    // MARK: Queries

    /// Nothing claimed in the way: no box, no line through it, no other
    /// dimension's extension-line lane.
    func isClear(_ rect: CGRect, ignoringLanes: Set<Int> = []) -> Bool {
        if boxes.contains(where: { $0.intersects(rect) }) { return false }
        if labelOnlyBoxes.contains(where: { $0.intersects(rect) }) { return false }
        if lines.contains(where: { Self.segmentIntersectsRect($0.a, $0.b, rect) }) { return false }
        for (i, l) in lanes.enumerated() where !ignoringLanes.contains(i) {
            if Self.segmentIntersectsRect(l.a, l.b, rect) { return false }
        }
        return true
    }

    /// How many things a box sits on — the fallback's measure of a bad spot.
    func crowding(_ rect: CGRect) -> Int {
        boxes.filter { $0.intersects(rect) }.count * 2
            + labelOnlyBoxes.filter { $0.intersects(rect) }.count
            + lines.filter { Self.segmentIntersectsRect($0.a, $0.b, rect) }.count
    }

    /// D1/D2: the line or its extension lines would cross a dimension line
    /// already drawn, or the line would cross an extension line already drawn.
    func crossesDimensionWork(line: (CGPoint, CGPoint), witnesses: [(CGPoint, CGPoint)]) -> Bool {
        for d in dimensionLines {
            if Self.crossesCleanly(line.0, line.1, d.a, d.b) { return true }
            for w in witnesses where Self.crossesCleanly(w.0, w.1, d.a, d.b) { return true }
        }
        for w in witnessLines where Self.crossesCleanly(line.0, line.1, w.a, w.b) { return true }
        return false
    }

    /// Stagger: another number on a parallel line close by whose extent along
    /// the line overlaps this one's.
    func staggerConflicts(along: CGPoint, center: CGPoint, half: CGFloat) -> Int {
        var n = 0
        for other in dimLabels {
            guard abs(along.x * other.along.x + along.y * other.along.y) > 0.9 else { continue }
            let dx = center.x - other.center.x, dy = center.y - other.center.y
            guard abs(dx * -along.y + dy * along.x) < 20 else { continue }
            if abs(dx * along.x + dy * along.y) < half + other.half + 6 { n += 1 }
        }
        return n
    }

    /// D3: the number would sit nearer another parallel edge running past it
    /// than the edge it measures.
    func misreads(label: CGPoint, own: (CGPoint, CGPoint)) -> Bool {
        let ol = hypot(own.1.x - own.0.x, own.1.y - own.0.y)
        guard ol > 1e-6 else { return false }
        let u = CGPoint(x: (own.1.x - own.0.x) / ol, y: (own.1.y - own.0.y) / ol)
        func dist(_ a: CGPoint, _ dir: CGPoint, _ p: CGPoint) -> CGFloat {
            abs((p.x - a.x) * dir.y - (p.y - a.y) * dir.x)
        }
        let ownD = dist(own.0, u, label)
        for e in edges {
            let l = hypot(e.b.x - e.a.x, e.b.y - e.a.y)
            guard l > 1e-6 else { continue }
            let v = CGPoint(x: (e.b.x - e.a.x) / l, y: (e.b.y - e.a.y) / l)
            guard abs(u.x * v.y - u.y * v.x) < 0.09 else { continue }
            // The measured edge itself, or one in line with it.
            if dist(own.0, u, e.a) < 1 { continue }
            let t = (label.x - e.a.x) * v.x + (label.y - e.a.y) * v.y
            guard t > 0, t < l else { continue }
            if dist(e.a, v, label) + 0.5 < ownD { return true }
        }
        return false
    }

    // MARK: Segment geometry

    /// Crossing with half a point of margin, so lines meeting at an end or
    /// running along one another don't count.
    static func crossesCleanly(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func orient(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let l1 = max(hypot(p2.x - p1.x, p2.y - p1.y), 1e-6)
        let l2 = max(hypot(p4.x - p3.x, p4.y - p3.y), 1e-6)
        let d1 = orient(p3, p4, p1) / l2, d2 = orient(p3, p4, p2) / l2
        let d3 = orient(p1, p2, p3) / l1, d4 = orient(p1, p2, p4) / l1
        let e: CGFloat = 0.5
        return ((d1 > e && d2 < -e) || (d1 < -e && d2 > e))
            && ((d3 > e && d4 < -e) || (d3 < -e && d4 > e))
    }

    static func segmentIntersectsRect(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> Bool {
        if r.contains(a) || r.contains(b) { return true }
        let tl = CGPoint(x: r.minX, y: r.minY), tr = CGPoint(x: r.maxX, y: r.minY)
        let bl = CGPoint(x: r.minX, y: r.maxY), br = CGPoint(x: r.maxX, y: r.maxY)
        return segmentsCross(a, b, tl, tr) || segmentsCross(a, b, tr, br)
            || segmentsCross(a, b, br, bl) || segmentsCross(a, b, bl, tl)
    }

    static func segmentsCross(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func orient(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let d1 = orient(p3, p4, p1), d2 = orient(p3, p4, p2)
        let d3 = orient(p1, p2, p3), d4 = orient(p1, p2, p4)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}
