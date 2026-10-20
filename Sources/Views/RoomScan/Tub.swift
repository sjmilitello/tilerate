import Foundation

/// A tub surround's tub on the model (owner, 2026-10-19): placed with a
/// tap like the shower, 60″ × 30″ to start. An alcove tub has three full
/// walls round it: tapped in a corner, a full wall is drawn in at its open
/// end; tapped in a space of three walls, it fills the space. A drop-in sits
/// in a deck whose top and front are tile or stone, 3″ past the tub on each
/// open side, 20″ high; its open end can be closed with a full wall too. Where
/// a deck meets a shower the two tie together: no curb along the deck, and
/// the deck stops at the shower or runs into it as the shower's bench. The
/// walls round a tub are tiled from its rim up. (A freestanding tub is the
/// room's decoration, `ScannedRoom.freestandingTubs`.)
extension AreaTakeoff {
    /// How a tub went in: filling a space of three walls, or in a corner.
    enum TubPlacement { case cove, corner }

    /// Where the tile starts: the rim, or the deck's top (inches).
    var tubRimHeightIn: Double { tubRimIn ?? tubKind.usualRimIn }

    /// The tub's footprint, else the scanned tub's (a tub surround that
    /// hasn't placed its own yet).
    func tubFootprint(in room: ScannedRoom) -> [ScannedRoom.Point] {
        tubRect?.corners ?? (room.tubOutline.count == 4 ? room.tubOutline : [])
    }

    /// For each of the footprint's four edges (corner i to i + 1), the wall
    /// it runs along, if any: parallel and within 0.4′ (as a shower floor's).
    static func tubEdgeWalls(_ c: [ScannedRoom.Point], in room: ScannedRoom) -> [ScannedRoom.Wall?] {
        guard c.count == 4 else { return [] }
        return (0..<4).map { i in
            let a = c[i], b = c[(i + 1) % 4]
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 1.0 / 12 else { return nil }
            let mid = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            return room.walls.filter { w in
                let wx = (w.end.x - w.start.x) / max(w.lengthFt, 1e-9), wy = (w.end.y - w.start.y) / max(w.lengthFt, 1e-9)
                return abs(wx * (b.x - a.x) / len + wy * (b.y - a.y) / len) > 0.98
                    && room.distanceToWall(mid, w) < 0.4
            }.min { room.distanceToWall(mid, $0) < room.distanceToWall(mid, $1) }
        }
    }

    /// Whether edge `a`–`b` lies along one of `polys`' edges (a shower floor
    /// beside the deck): collinear within 0.15′ and overlapping.
    static func edgeTouches(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point, _ polys: [[ScannedRoom.Point]]) -> Bool {
        let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
        let u = ScannedRoom.Point(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
        return polys.contains { p in
            (0..<p.count).contains { i in
                let c = p[i], d = p[(i + 1) % p.count]
                func off(_ q: ScannedRoom.Point) -> Double { abs((q.x - a.x) * -u.y + (q.y - a.y) * u.x) }
                guard off(c) < 0.15, off(d) < 0.15 else { return false }
                let t0 = (c.x - a.x) * u.x + (c.y - a.y) * u.y, t1 = (d.x - a.x) * u.x + (d.y - a.y) * u.y
                return min(len, max(t0, t1)) - max(0, min(t0, t1)) > 0.25
            }
        }
    }

    /// The edges with no wall along them: a drop-in deck's front. An edge a
    /// shower floor meets is front too — unless the deck runs into the
    /// shower as a bench, which covers it.
    func tubOpenEdges(in room: ScannedRoom) -> [(ScannedRoom.Point, ScannedRoom.Point)] {
        guard let r = tubRect else { return [] }
        let c = r.corners, walls = Self.tubEdgeWalls(c, in: room)
        return (0..<4).compactMap { i in
            let a = c[i], b = c[(i + 1) % 4]
            guard walls[i] == nil else { return nil }
            if tubDeckIntoShower, Self.edgeTouches(a, b, tubNeighbors) { return nil }
            return (a, b)
        }
    }

    /// The tub's open ends (its short sides with no wall), where a full wall
    /// can close it in: each as the edge from the back wall out.
    func tubOpenEnds(in room: ScannedRoom) -> [(ScannedRoom.Point, ScannedRoom.Point)] {
        guard let r = tubRect else { return [] }
        let c = r.corners, walls = Self.tubEdgeWalls(c, in: room)
        guard walls.count == 4 else { return [] }
        // The ends are the sides across the long side: edges 1 and 3 when it's along u.
        let ends = r.widthFt >= r.depthFt ? [1, 3] : [0, 2]
        return ends.compactMap { i in
            guard walls[i] == nil, !Self.edgeTouches(c[i], c[(i + 1) % 4], tubNeighbors) else { return nil }
            // From the end touching a wall (the back wall) outward.
            let a = c[i], b = c[(i + 1) % 4]
            let backAtA = room.walls.contains { room.distanceToWall(a, $0) < 0.4 }
            return backAtA ? (a, b) : (b, a)
        }
    }

    /// A full wall drawn in at each open end of the tub, its face flush with
    /// the tub's end, from the back wall out to the tub's front, at the
    /// ceiling, and tiled on the tub's side (owner, 2026-10-19: an alcove tub
    /// has three full walls). It's an ordinary wall drawn in: edited or
    /// deleted like any other.
    mutating func closeTubEnds(in room: inout ScannedRoom, thicknessIn: Double) {
        guard let r = tubRect else { return }
        let mid = r.center, t = thicknessIn / 12
        for (a, b) in tubOpenEnds(in: room) {
            let ex = b.x - a.x, ey = b.y - a.y, len = max(hypot(ex, ey), 1e-9)
            var n = ScannedRoom.Point(x: -ey / len, y: ex / len)
            let em = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if (em.x - mid.x) * n.x + (em.y - mid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
            _ = room.addPlannedWall(from: .init(x: a.x + n.x * t / 2, y: a.y + n.y * t / 2),
                                    to: .init(x: b.x + n.x * t / 2, y: b.y + n.y * t / 2),
                                    heightIn: room.ceilingFt * 12, thicknessIn: thicknessIn)
        }
        tubChanged(from: r, in: room)
    }

    /// A drop-in's tub inside its deck: the deck less the lip on each open side.
    func tubInDeck(in room: ScannedRoom) -> FloorRect? {
        guard tubKind == .dropIn, var r = tubRect else { return nil }
        let walls = Self.tubEdgeWalls(r.corners, in: room)
        guard walls.count == 4 else { return r }
        let lip = tubLipIn / 12
        // Edge 0 runs along u at v = 0, 1 along v at u = width, 2 at v = depth, 3 at u = 0.
        let open = walls.map { $0 == nil }
        let du0 = open[3] ? lip : 0, du1 = open[1] ? lip : 0
        let dv0 = open[0] ? lip : 0, dv1 = open[2] ? lip : 0
        r.origin = .init(x: r.origin.x + r.u.x * du0 + r.v.x * dv0, y: r.origin.y + r.u.y * du0 + r.v.y * dv0)
        r.widthFt = max(1, r.widthFt - du0 - du1)
        r.depthFt = max(1, r.depthFt - dv0 - dv1)
        return r
    }

    /// The deck's top (the deck less the tub's opening) and its front (each
    /// open side × the deck's height), square feet.
    func tubDeckSqft(in room: ScannedRoom) -> (top: Double, front: Double) {
        guard tubKind == .dropIn, let r = tubRect else { return (0, 0) }
        let inner = tubInDeck(in: room) ?? r
        let top = max(0, r.widthFt * r.depthFt - inner.widthFt * inner.depthFt)
        let front = tubOpenEdges(in: room).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } * tubRimHeightIn / 12
        return (top, front)
    }

    /// Where a tap puts the tub (owner, 2026-10-19): in a space of three
    /// walls it fills the space, wall to wall (30″ deep, or the space's depth
    /// if that's under 3½′); else 60″ × 30″ from the nearest inside corner, its
    /// long side against the wall nearer the tap. Kept off `avoid` (another
    /// area's shower floor), on the tap's side of it. The walls it's
    /// against are tiled; nil with no corner near.
    @discardableResult
    mutating func placeTub(near tap: ScannedRoom.Point, in room: ScannedRoom, avoid: [[ScannedRoom.Point]] = []) -> TubPlacement? {
        let old = tubRect
        var how: TubPlacement
        if let cove = room.cove(around: tap) {
            tubRect = FloorRect(origin: cove.origin, u: cove.u, v: cove.v, widthFt: cove.widthFt,
                                depthFt: cove.depthFt < 3.5 ? cove.depthFt : 2.5)
            how = .cove
        } else if let corner = room.insideCorners().min(by: {
            hypot($0.at.x - tap.x, $0.at.y - tap.y) < hypot($1.at.x - tap.x, $1.at.y - tap.y)
        }) {
            func off(_ d: ScannedRoom.Point) -> Double { (tap.x - corner.at.x) * d.x + (tap.y - corner.at.y) * d.y }
            let (u, v) = off(corner.a) >= off(corner.b) ? (corner.a, corner.b) : (corner.b, corner.a)
            tubRect = FloorRect(origin: corner.at, u: u, v: v, widthFt: 5, depthFt: 2.5)
            how = .corner
        } else {
            return nil
        }
        // Beside a shower: the part on the tap's side, ending at its floor.
        for poly in avoid {
            if let r = tubRect, let cut = r.clipped(awayFrom: poly, toward: tap) {
                tubRect = cut
                how = .corner
            }
        }
        if tubKind == .dropIn { growDeck(in: room) }
        tubChanged(from: old, in: room)
        return how
    }

    /// A scanned tub becomes the tub surround's own, to move and change.
    mutating func adoptScannedTub(from room: ScannedRoom) {
        guard tubRect == nil, room.tubOutline.count == 4 else { return }
        let p = room.tubOutline
        let w = hypot(p[1].x - p[0].x, p[1].y - p[0].y), d = hypot(p[3].x - p[0].x, p[3].y - p[0].y)
        guard w > 0.5, d > 0.5 else { return }
        tubRect = FloorRect(origin: p[0], u: .init(x: (p[1].x - p[0].x) / w, y: (p[1].y - p[0].y) / w),
                            v: .init(x: (p[3].x - p[0].x) / d, y: (p[3].y - p[0].y) / d), widthFt: w, depthFt: d)
        floorWidthFt = w; floorDepthFt = d
    }

    /// A different kind of tub: a drop-in's deck grows by the lip on its
    /// open sides, and shrinks back when it's no longer a drop-in.
    mutating func setTubKind(_ k: TubKind, in room: ScannedRoom) {
        guard k != tubKind else { return }
        let old = tubRect
        if tubKind == .dropIn, let inner = tubInDeck(in: room) { tubRect = inner }
        tubKind = k
        tubRimIn = nil
        if k == .dropIn { growDeck(in: room) }
        tubChanged(from: old, in: room)
    }

    /// The deck round the tub now in `tubRect`: the lip added on each open side.
    private mutating func growDeck(in room: ScannedRoom) {
        guard var r = tubRect else { return }
        let walls = Self.tubEdgeWalls(r.corners, in: room)
        guard walls.count == 4 else { return }
        let lip = tubLipIn / 12, open = walls.map { $0 == nil }
        let du0 = open[3] ? lip : 0, du1 = open[1] ? lip : 0, dv0 = open[0] ? lip : 0, dv1 = open[2] ? lip : 0
        r.origin = .init(x: r.origin.x - r.u.x * du0 - r.v.x * dv0, y: r.origin.y - r.u.y * du0 - r.v.y * dv0)
        r.widthFt += du0 + du1
        r.depthFt += dv0 + dv1
        tubRect = r
    }

    /// After the tub is placed, moved, resized or changed: the ceiling over
    /// it takes its size, and the walls it's against are tiled along it —
    /// pieces that ran along the tub before follow it, keeping their height.
    /// A wall drawn in is tiled on its side facing the tub.
    mutating func tubChanged(from old: FloorRect?, in room: ScannedRoom) {
        guard let r = tubRect else { return }
        floorWidthFt = r.widthFt
        floorDepthFt = r.depthFt
        let oldSpans = old.map { Self.tubSpans($0.corners, in: room) } ?? [:]
        var heights: [UUID: Double] = [:]
        pieces.removeAll { p in
            guard let s = oldSpans[p.wallID], abs(p.fromFt - s.lowerBound) < 0.1, abs(p.toFt - s.upperBound) < 0.1 else { return false }
            heights[p.wallID] = p.heightIn
            return true
        }
        let mid = r.center
        for (wallID, span) in Self.tubSpans(r.corners, in: room) {
            guard let w = room.wall(wallID) else { continue }
            if pieces.contains(where: { $0.wallID == wallID && $0.fromFt <= span.lowerBound + 0.05 && $0.toFt >= span.upperBound - 0.05 }) { continue }
            pieces.removeAll { $0.wallID == wallID && $0.fromFt < span.upperBound && $0.toFt > span.lowerBound }
            var face = 0
            if w.planned {
                let n = room.sideNormal(of: w, face: 0, toward: mid)
                let wm = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
                face = n.x * (mid.x - wm.x) + n.y * (mid.y - wm.y) >= 0 ? 0 : 1
            }
            pieces.append(Piece(wallID: wallID, fromFt: span.lowerBound, toFt: span.upperBound,
                                heightIn: heights[wallID] ?? Self.startingHeight(for: .tub, wall: w), face: face))
        }
    }

    /// Each wall the footprint is against, and the stretch of it the tub runs along.
    static func tubSpans(_ c: [ScannedRoom.Point], in room: ScannedRoom) -> [UUID: ClosedRange<Double>] {
        var out: [UUID: ClosedRange<Double>] = [:]
        for (i, w) in tubEdgeWalls(c, in: room).enumerated() {
            guard let w else { continue }
            let a = room.along(c[i], on: w), b = room.along(c[(i + 1) % 4], on: w)
            let lo = max(0, min(a, b)), hi = min(w.lengthFt, max(a, b))
            if hi - lo > 1.0 / 12 { out[w.id] = lo...hi }
        }
        return out
    }

    /// The wall below the rim (or the deck's top) behind the tub: not tiled,
    /// so not counted (owner, 2026-10-19). Each piece's overlap with the
    /// tub's stretch of its wall, up to the rim.
    func tubBelowRimSqft(in room: ScannedRoom) -> Double {
        let c = tubFootprint(in: room)
        guard c.count == 4 else { return 0 }
        let spans = Self.tubSpans(c, in: room)
        let rim = tubRimHeightIn
        return pieces.reduce(0.0) { sum, p in
            guard let s = spans[p.wallID] else { return sum }
            let overlap = min(p.toFt, s.upperBound) - max(p.fromFt, s.lowerBound)
            return overlap > 0 ? sum + overlap * min(rim, p.heightIn) / 12 : sum
        }
    }
}

extension AreaTakeoff.FloorRect {
    /// This rectangle cut back to clear `poly` (another area's floor), along
    /// whichever of its sides does it with the most left, keeping the part on
    /// `tap`'s side; nil when they don't overlap or under a foot would be left.
    func clipped(awayFrom poly: [ScannedRoom.Point], toward tap: ScannedRoom.Point) -> Self? {
        guard poly.count > 2 else { return nil }
        func uOf(_ p: ScannedRoom.Point) -> Double { (p.x - origin.x) * u.x + (p.y - origin.y) * u.y }
        func vOf(_ p: ScannedRoom.Point) -> Double { (p.x - origin.x) * v.x + (p.y - origin.y) * v.y }
        let pu = poly.map(uOf), pv = poly.map(vOf)
        guard pu.max()! > 0.05, pu.min()! < widthFt - 0.05, pv.max()! > 0.05, pv.min()! < depthFt - 0.05 else { return nil }
        var options: [Self] = []
        // Along u (its width), or along v (its depth).
        for alongU in [true, false] {
            let lo = alongU ? pu.min()! : pv.min()!, hi = alongU ? pu.max()! : pv.max()!
            let size = alongU ? widthFt : depthFt
            let t = alongU ? uOf(tap) : vOf(tap)
            var r = self
            if t < (lo + hi) / 2 {
                if alongU { r.widthFt = min(size, lo) } else { r.depthFt = min(size, lo) }
            } else {
                let start = max(0, hi)
                let d = alongU ? u : v
                r.origin = .init(x: origin.x + d.x * start, y: origin.y + d.y * start)
                if alongU { r.widthFt = size - start } else { r.depthFt = size - start }
            }
            if r.widthFt >= 1, r.depthFt >= 1 { options.append(r) }
        }
        return options.max { $0.widthFt * $0.depthFt < $1.widthFt * $1.depthFt }
    }
}

extension AreaTakeoff.FloorRect {
    /// Moved so an edge lies on one of `segments` running alongside it,
    /// within `reach`, each way on its own (owner, 2026-10-19: a shower
    /// dragged up to a tub's deck, or a tub to a shower, catches on it as on
    /// a wall).
    func caught(on segments: [(ScannedRoom.Point, ScannedRoom.Point)], reach: Double) -> Self {
        guard reach > 0 else { return self }
        var out = self
        for (axis, size, other, otherSize) in [(u, widthFt, v, depthFt), (v, depthFt, u, widthFt)] {
            var best: Double? = nil
            for (a, b) in segments {
                let ex = b.x - a.x, ey = b.y - a.y, len = max(hypot(ex, ey), 1e-9)
                guard abs((ex * axis.x + ey * axis.y) / len) < 0.05 else { continue }
                let pos = (a.x - origin.x) * axis.x + (a.y - origin.y) * axis.y
                let s0 = (a.x - origin.x) * other.x + (a.y - origin.y) * other.y
                let s1 = (b.x - origin.x) * other.x + (b.y - origin.y) * other.y
                guard min(otherSize, max(s0, s1)) - max(0, min(s0, s1)) > 0.25 else { continue }
                for edge in [0, size] {
                    let g = pos - edge
                    if abs(g) < reach, abs(g) > 1e-6, abs(g) < abs(best ?? .infinity) { best = g }
                }
            }
            if let g = best { out.origin = .init(x: out.origin.x + axis.x * g, y: out.origin.y + axis.y * g) }
        }
        return out
    }

    /// Turned a quarter about its middle.
    var turnedInPlace: Self {
        let c = center
        var r = self
        r.u = .init(x: -v.x, y: -v.y)
        r.v = u
        r.widthFt = depthFt
        r.depthFt = widthFt
        r.origin = .init(x: c.x - r.u.x * r.widthFt / 2 - r.v.x * r.depthFt / 2, y: c.y - r.u.y * r.widthFt / 2 - r.v.y * r.depthFt / 2)
        return r
    }
}

extension ScannedRoom {
    /// A freestanding tub where a tap puts it: 66″ × 32″, centred there,
    /// square to the room.
    mutating func addFreestandingTub(at p: Point) {
        let a = squaringAngle
        let u = Point(x: cos(a), y: sin(a)), v = Point(x: -sin(a), y: cos(a))
        let w = 66.0 / 12, d = 32.0 / 12
        freestandingTubs.append(.init(origin: .init(x: p.x - u.x * w / 2 - v.x * d / 2, y: p.y - u.y * w / 2 - v.y * d / 2),
                                      u: u, v: v, widthFt: w, depthFt: d))
    }
}

extension EstimateRoom {
    /// Ties each drop-in tub's deck to the showers it meets (owner,
    /// 2026-10-19): the tub knows them (its deck's front stops there, or
    /// not, as a bench covers it), and a deck running into a shower is that
    /// shower's bench — along their back wall from the deck, the deck's
    /// depth and height, 15″ into the shower. Each area changed is measured again.
    mutating func tieTubsAndShowers(prices: StonePrices) {
        guard let scan else { return }
        func open(_ i: Int) -> Bool { sections[i].roomScan == nil && !sections[i].measuredByHand }
        let tubs = sections.indices.filter { open($0) && sections[$0].area == .tub && sections[$0].scanTakeoff?.tubRect != nil }
        let showers = sections.indices.filter {
            open($0) && sections[$0].area == .shower && sections[$0].scanTakeoff?.floor == .drawn && sections[$0].scanTakeoff?.floorRect != nil
        }
        func touching(_ deck: [ScannedRoom.Point], _ floor: [ScannedRoom.Point]) -> Bool {
            (0..<4).contains { AreaTakeoff.edgeTouches(deck[$0], deck[($0 + 1) % 4], [floor]) }
        }
        for ti in tubs {
            var t = sections[ti].scanTakeoff!
            let deck = t.tubRect!.corners
            let near = t.tubKind == .dropIn ? showers.compactMap { si -> [ScannedRoom.Point]? in
                let f = sections[si].scanTakeoff!.floorRect!.corners
                return touching(deck, f) ? f : nil
            } : []
            guard near != t.tubNeighbors else { continue }
            t.tubNeighbors = near
            t.apply(scan, to: &sections[ti], prices: prices)
        }
        for si in showers {
            var s = sections[si].scanTakeoff!
            let floor = s.floorRect!
            var want: [AreaTakeoff.Item] = []
            for ti in tubs {
                let t = sections[ti].scanTakeoff!
                guard t.tubKind == .dropIn, t.tubDeckIntoShower, let r = t.tubRect else { continue }
                let deck = r.corners
                guard let e = (0..<4).first(where: { AreaTakeoff.edgeTouches(deck[$0], deck[($0 + 1) % 4], [floor.corners]) }) else { continue }
                // The back wall both stand against: the deck's wall across the shared edge.
                let walls = AreaTakeoff.tubEdgeWalls(deck, in: scan)
                guard let back = [(e + 1) % 4, (e + 3) % 4].compactMap({ walls[$0] }).first else { continue }
                let a = deck[e], b = deck[(e + 1) % 4]
                let atWall = scan.distanceToWall(a, back) < scan.distanceToWall(b, back) ? a : b
                let along = scan.along(atWall, on: back)
                // Into the shower: toward the floor's middle, along the back wall.
                let into = scan.along(floor.center, on: back) > along ? 1.0 : -1.0
                let length = 15.0 / 12
                let from = into > 0 ? along : along - length, to = into > 0 ? along + length : along
                var bench = s.items.first { $0.fromTubDeck && $0.wallID == back.id } ?? AreaTakeoff.Item()
                bench.kind = .framedBench
                bench.wallID = back.id
                bench.face = 0
                bench.fromFt = max(0, from)
                bench.toFt = min(back.lengthFt, to)
                bench.heightIn = t.tubRimHeightIn
                bench.depthIn = hypot(b.x - a.x, b.y - a.y) * 12
                bench.fromTubDeck = true
                want.append(bench)
            }
            let have = s.items.filter(\.fromTubDeck)
            guard have != want else { continue }
            s.items.removeAll(where: \.fromTubDeck)
            s.items += want
            if !want.isEmpty { s.itemsPlaced = true }
            s.apply(scan, to: &sections[si], prices: prices)
        }
    }
}
