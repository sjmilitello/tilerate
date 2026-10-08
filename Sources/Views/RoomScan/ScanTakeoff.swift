import Foundation

// The square feet one area takes from a room scan (AreaTakeoff): stretches
// of walls tiled to their own heights, less the openings ticked, and the
// floor and ceiling. Nothing is subtracted unless ticked (owner's call,
// 2026-10-07), and only the part of an opening inside the tiled stretch.

extension ScannedRoom {
    func wall(_ id: UUID) -> Wall? { walls.first { $0.id == id } }

    /// The point `along` feet from a wall's start, on the plan.
    func point(on wall: Wall, along: Double) -> Point {
        let t = wall.lengthFt > 0 ? along / wall.lengthFt : 0
        return Point(x: wall.start.x + (wall.end.x - wall.start.x) * t,
                     y: wall.start.y + (wall.end.y - wall.start.y) * t)
    }

    /// How far along a wall a plan point falls (its projection), clamped to the wall.
    func along(_ p: Point, on wall: Wall) -> Double {
        let dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return 0 }
        let t = ((p.x - wall.start.x) * dx + (p.y - wall.start.y) * dy) / len2
        return min(max(t, 0), 1) * wall.lengthFt
    }

    /// An opening's stretch along its wall; the whole wall's middle when the
    /// scan didn't say where.
    func span(of o: Opening) -> ClosedRange<Double> {
        let wallLength = o.wallID.flatMap { wall($0) }?.lengthFt ?? o.widthFt
        let mid = o.alongFt ?? wallLength / 2
        return max(0, mid - o.widthFt / 2)...min(wallLength, mid + o.widthFt / 2)
    }

    /// The angle the room's walls make with the plan's axes (between −45°
    /// and 45°), from the walls' directions weighted by their length: turning
    /// the plan by minus this squares the room up on screen.
    var squaringAngle: Double {
        var sx = 0.0, sy = 0.0
        for w in walls {
            let a = atan2(w.end.y - w.start.y, w.end.x - w.start.x)
            sx += w.lengthFt * cos(4 * a)
            sy += w.lengthFt * sin(4 * a)
        }
        guard sx != 0 || sy != 0 else { return 0 }
        return atan2(sy, sx) / 4
    }

    // MARK: Planned walls

    /// The ceiling: the tallest scanned wall.
    var ceilingFt: Double { walls.filter { !$0.planned }.map(\.heightFt).max() ?? 8 }

    /// A planned wall lower than the ceiling: it has a cap. A planned wall
    /// to the ceiling is a full wall (e.g. one with a shower door in it).
    /// (Within 3″ of the ceiling counts as full: a scan's ceiling is rarely a whole inch.)
    func isKneeWall(_ w: Wall) -> Bool { w.planned && w.heightFt < ceilingFt - 3.0 / 12 }

    /// "Half wall E", "New wall E" or "Wall A".
    func name(of w: Wall) -> String {
        isKneeWall(w) ? "Half wall \(w.label)" : w.planned ? "New wall \(w.label)" : "Wall \(w.label)"
    }

    /// True when a shower door has a header over it: its top is below the
    /// wall's top. Dragged up to the ceiling, it has none.
    func hasHeader(_ door: Opening) -> Bool {
        guard let w = door.wallID.flatMap({ wall($0) }) else { return false }
        return door.bottomFt + door.heightFt < w.heightFt - 0.5 / 12
    }

    /// A shower door opening on a wall, centred at `along` and kept on the wall.
    mutating func addShowerDoor(on w: Wall, along: Double, widthIn: Double, heightIn: Double) -> Opening {
        let width = min(widthIn / 12, w.lengthFt)
        let mid = min(max(along, width / 2), w.lengthFt - width / 2)
        let o = Opening(kind: .showerDoor, wallID: w.id, widthFt: width, heightFt: min(heightIn / 12, w.heightFt),
                        bottomFt: 0, alongFt: mid)
        openings.append(o)
        return o
    }

    /// The next free wall letter after the scanned ones.
    var nextWallLabel: String {
        let used = Set(walls.map(\.label))
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" where !used.contains(String(ch)) { return String(ch) }
        return "\(walls.count + 1)"
    }

    /// A point moved onto a nearby wall (within `pull` feet), else left alone.
    func snappedToWall(_ p: Point, pull: Double = 0.6, except: UUID? = nil) -> Point {
        var best = p, bestGap = pull
        for w in walls where w.id != except {
            let q = point(on: w, along: along(p, on: w))
            let gap = ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
            if gap < bestGap { best = q; bestGap = gap }
        }
        return best
    }

    /// The end of a new or moved planned wall: straightened to run square
    /// with the room, its length rounded to the inch, and onto a wall it
    /// nearly reaches.
    func plannedEnd(from a: Point, toward b: Point, except: UUID? = nil) -> Point {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.01 else { return b }
        // Nearest of the room's four square directions.
        let base = squaringAngle
        let raw = atan2(dy, dx)
        let step = Double.pi / 2
        let a0 = base + ((raw - base) / step).rounded() * step
        var len = (length * 12).rounded() / 12
        // Stop on a wall it nearly reaches.
        let dir = Point(x: cos(a0), y: sin(a0))
        for w in walls where w.id != except {
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = dir.x * ey - dir.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - a.x) * ey - (w.start.y - a.y) * ex) / den
            let s = ((w.start.x - a.x) * dir.y - (w.start.y - a.y) * dir.x) / den
            if t > 0.5, s >= -0.05, s <= 1.05, abs(t - len) < 0.5 { len = t }
        }
        return Point(x: a.x + dir.x * len, y: a.y + dir.y * len)
    }

    /// A planned wall from `a` to `b`, `heightIn` high and `thicknessIn` thick.
    mutating func addPlannedWall(from a: Point, to b: Point, heightIn: Double, thicknessIn: Double) -> Wall {
        let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        let w = Wall(label: nextWallLabel, lengthFt: length, heightFt: heightIn / 12, start: a, end: b,
                     planned: true, thicknessIn: thicknessIn)
        walls.append(w)
        return w
    }

    /// A planned wall already lying along `a`–`b` (parallel, within 3″,
    /// sharing most of its length): adding another there would hide one
    /// under the other.
    func plannedWall(along a: Point, _ b: Point) -> Wall? {
        let dx = b.x - a.x, dy = b.y - a.y, l = (dx * dx + dy * dy).squareRoot()
        guard l > 0.01 else { return nil }
        let u = Point(x: dx / l, y: dy / l)
        return walls.first { w in
            guard w.planned else { return false }
            func off(_ p: Point) -> Double { abs((p.x - a.x) * -u.y + (p.y - a.y) * u.x) }
            guard off(w.start) < 0.25, off(w.end) < 0.25 else { return false }
            let t0 = (w.start.x - a.x) * u.x + (w.start.y - a.y) * u.y
            let t1 = (w.end.x - a.x) * u.x + (w.end.y - a.y) * u.y
            let shared = min(l, max(t0, t1)) - max(0, min(t0, t1))
            return shared > 0.5 * min(l, w.lengthFt)
        }
    }

    /// Moves one end of a planned wall, keeping its length up to date.
    mutating func movePlannedEnd(_ id: UUID, start: Bool, to p: Point) {
        guard let i = walls.firstIndex(where: { $0.id == id }), walls[i].planned else { return }
        if start { walls[i].start = p } else { walls[i].end = p }
        let w = walls[i]
        walls[i].lengthFt = ((w.end.x - w.start.x) * (w.end.x - w.start.x) + (w.end.y - w.start.y) * (w.end.y - w.start.y)).squareRoot()
    }

    /// A planned wall moved whole, by `d` feet from where it was
    /// (`original`), keeping its length, tile and door. Each way rounds to
    /// the inch; across, its line snaps within 3″ to `guides` (e.g. the
    /// shower floor's corners) and other walls' ends; along, an end snaps
    /// onto a wall within 3″.
    mutating func movePlannedWall(_ original: Wall, by d: Point, guides: [Point] = []) {
        guard let i = walls.firstIndex(where: { $0.id == original.id }), walls[i].planned else { return }
        let dx = original.end.x - original.start.x, dy = original.end.y - original.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let u = Point(x: dx / l, y: dy / l), n = Point(x: -u.y, y: u.x)
        var along = ((d.x * u.x + d.y * u.y) * 12).rounded() / 12
        var across = ((d.x * n.x + d.y * n.y) * 12).rounded() / 12
        // Across: line up with a guide or another wall's end.
        let raw = d.x * n.x + d.y * n.y
        var best = 0.25
        for p in guides + walls.filter({ $0.id != original.id }).flatMap({ [$0.start, $0.end] }) {
            let c = (p.x - original.start.x) * n.x + (p.y - original.start.y) * n.y
            if abs(c - raw) < best { best = abs(c - raw); across = c }
        }
        // Along: an end onto a wall it nearly touches.
        let rawAlong = d.x * u.x + d.y * u.y
        let base = Point(x: original.start.x + n.x * across, y: original.start.y + n.y * across)
        best = 0.25
        for w in walls where w.id != original.id {
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = u.x * ey - u.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - base.x) * ey - (w.start.y - base.y) * ex) / den
            let s = ((w.start.x - base.x) * u.y - (w.start.y - base.y) * u.x) / den
            guard s >= -0.05, s <= 1.05 else { continue }
            for shift in [t, t - original.lengthFt] where abs(shift - rawAlong) < best {
                best = abs(shift - rawAlong)
                along = shift
            }
        }
        let move = Point(x: u.x * along + n.x * across, y: u.y * along + n.y * across)
        walls[i].start = Point(x: original.start.x + move.x, y: original.start.y + move.y)
        walls[i].end = Point(x: original.end.x + move.x, y: original.end.y + move.y)
    }

    /// True when a wall's end isn't against another wall: an exposed end.
    func isFreeEnd(of wall: Wall, start: Bool) -> Bool {
        let p = start ? wall.start : wall.end
        return !walls.contains { w in
            w.id != wall.id && distanceToWall(p, w) < 0.3
        }
    }

    /// "facing wall B": which wall a face of a planned wall looks toward.
    func faceName(of wall: Wall, face: Int) -> String {
        let dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        var n = Point(x: -dy / l, y: dx / l)
        if face == 1 { n = Point(x: -n.x, y: -n.y) }
        let mid = Point(x: (wall.start.x + wall.end.x) / 2, y: (wall.start.y + wall.end.y) / 2)
        var best: (String, Double)? = nil
        for w in walls where w.id != wall.id {
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = n.x * ey - n.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - mid.x) * ey - (w.start.y - mid.y) * ex) / den
            let s = ((w.start.x - mid.x) * n.y - (w.start.y - mid.y) * n.x) / den
            if t > 0.05, s >= 0, s <= 1, t < (best?.1 ?? .infinity) { best = (w.label, t) }
        }
        return best.map { "Side facing wall \($0.0)" } ?? (face == 0 ? "Side 1" : "Side 2")
    }

    /// The bathtub's footprint, in square feet.
    var tubSqft: Double { ScannedRoom.area(tubOutline) }

    /// Neat places for a piece's ends on a wall: its ends, openings' edges,
    /// where the bathtub meets it, and other areas' ends.
    func snapPoints(on wall: Wall, others: [AreaTakeoff.Piece] = []) -> [Double] {
        var points: [Double] = [0, wall.lengthFt]
        for o in openings where o.wallID == wall.id {
            let s = span(of: o)
            points += [s.lowerBound, s.upperBound]
        }
        if tubOutline.count > 2 {
            // The tub's corners that sit against this wall.
            for c in tubOutline where distanceToWall(c, wall) < 0.75 {
                points.append(along(c, on: wall))
            }
        }
        for p in others where p.wallID == wall.id { points += [p.fromFt, p.toFt] }
        return points
    }

    func distanceToWall(_ p: Point, _ wall: Wall) -> Double {
        let q = point(on: wall, along: along(p, on: wall))
        return ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
    }
}

/// Rounds to the nearest inch, or to a snap point within `pull` feet.
func snapped(_ ft: Double, to points: [Double], pull: Double = 0.25, step: Double = 1.0 / 12) -> Double {
    if let near = points.min(by: { abs($0 - ft) < abs($1 - ft) }), abs(near - ft) <= pull { return near }
    return (ft / step).rounded() * step
}

extension AreaTakeoff {
    /// A piece's tiled square feet, less the part of each ticked opening
    /// inside it.
    func sqft(of piece: Piece, in room: ScannedRoom) -> Double {
        let height = piece.heightIn / 12
        var area = max(0, piece.toFt - piece.fromFt) * height
        for o in room.openings where o.wallID == piece.wallID && (subtracted.contains(o.id) || o.kind == .showerDoor) {
            let s = room.span(of: o)
            let width = max(0, min(s.upperBound, piece.toFt) - max(s.lowerBound, piece.fromFt))
            let tall = max(0, min(o.bottomFt + o.heightFt, height) - max(o.bottomFt, 0))
            area -= width * tall
        }
        // A window placed here: never tiled.
        for w in items where w.kind == .window && w.wallID == piece.wallID {
            let width = max(0, min(w.toFt, piece.toFt) - max(w.fromFt, piece.fromFt))
            let tall = max(0, min((w.bottomIn + w.heightIn) / 12, height) - max(w.bottomIn / 12, 0))
            area -= width * tall
        }
        return max(0, area)
    }

    /// Tile on benches: a framed bench's top and front, a floating bench's
    /// top, unless switched to stone.
    func benchTileSqft(in room: ScannedRoom) -> Double {
        let parts = trimPieces(in: room, area: .shower, curbHeightIn: 4)
        return items.filter(\.kind.isBench).reduce(0) { total, b in
            let top = parts.first { $0.key == "benchTop:\(b.id)" }
            let front = parts.first { $0.key == "benchFront:\(b.id)" }
            var sq = 0.0
            if top?.stone != true { sq += b.widthFt * b.depthIn / 12 }
            if b.kind == .framedBench, front?.stone != true { sq += b.widthFt * b.heightIn / 12 }
            return total + sq
        }
    }

    func wallsSqft(in room: ScannedRoom) -> Double {
        // Tile on a wall that's since been deleted doesn't count; tile on benches does.
        pieces.filter { room.wall($0.wallID) != nil }.reduce(0) { $0 + sqft(of: $1, in: room) } + benchTileSqft(in: room)
    }

    func floorSqft(in room: ScannedRoom) -> Double {
        switch floor {
        case .room:
            return max(0, room.floorSqft - (excludeTub ? room.tubSqft : 0) - excludeSqft)
        case .size:
            return floorWidthFt * floorDepthFt
        case .drawn:
            return floorRect.map { $0.widthFt * $0.depthFt } ?? 0
        case .none:
            return 0
        }
    }

    /// A tiled ceiling: the floor's size when one is set, otherwise the room's.
    func ceilingSqft(in room: ScannedRoom) -> Double {
        guard tileCeiling else { return 0 }
        if floor == .drawn, let r = floorRect { return r.widthFt * r.depthFt }
        if floorWidthFt > 0, floorDepthFt > 0 { return floorWidthFt * floorDepthFt }
        return room.floorSqft
    }

    /// Openings that fall in one of this area's pieces: the ones to ask about.
    func openingsInPieces(of room: ScannedRoom) -> [ScannedRoom.Opening] {
        room.openings.filter { o in
            guard o.kind != .showerDoor else { return false }
            let s = room.span(of: o)
            return pieces.contains { p in
                p.wallID == o.wallID && s.upperBound > p.fromFt + 0.01 && s.lowerBound < p.toFt - 0.01
                    && o.bottomFt < p.heightIn / 12
            }
        }
    }

    /// Where an area starts the first time it opens the scan.
    static func starting(for area: Area?, room: ScannedRoom, otherAreas: [EstimateSection]) -> AreaTakeoff {
        var t = AreaTakeoff()
        switch area {
        case .floor:
            t.floor = .room
            t.excludeTub = room.tubSqft > 0
            // A shower's floor in the same room is a separate item.
            t.excludeSqft = otherAreas.filter { $0.area == .shower }.reduce(0) { $0 + $1.measurements.showerFloorSqft }
        case .shower:
            t.floor = .drawn
        case .tub:
            if room.tubOutline.count > 2 {
                let (w, d) = boundingSize(room.tubOutline)
                t.floorWidthFt = (max(w, d) * 12).rounded() / 12
                t.floorDepthFt = (min(w, d) * 12).rounded() / 12
            }
        default:
            break
        }
        return t
    }

    /// The tile height a new piece starts at for this kind of area: the top
    /// of the wall, except a backsplash (owner's rule, 2026-10-08).
    static func startingHeight(for area: Area?, wall: ScannedRoom.Wall) -> Double {
        let full = (wall.heightFt * 12).rounded(.down)
        return area == .backsplash ? min(18, full) : full
    }

    /// A new piece on a wall: its longest stretch not already used by this
    /// area or another, at the starting height.
    mutating func addPiece(on wall: ScannedRoom.Wall, area: Area?, others: [Piece], face: Int = 0) -> Piece? {
        let taken = (pieces + others).filter { $0.wallID == wall.id && $0.face == face }
            .map { $0.fromFt...$0.toFt }.sorted { $0.lowerBound < $1.lowerBound }
        var gaps: [ClosedRange<Double>] = []
        var cursor = 0.0
        for r in taken {
            if r.lowerBound - cursor > 0.25 { gaps.append(cursor...r.lowerBound) }
            cursor = max(cursor, r.upperBound)
        }
        if wall.lengthFt - cursor > 0.25 { gaps.append(cursor...wall.lengthFt) }
        guard let gap = gaps.max(by: { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }) else { return nil }
        let piece = Piece(wallID: wall.id, fromFt: gap.lowerBound, toFt: gap.upperBound,
                          heightIn: Self.startingHeight(for: area, wall: wall), face: face)
        pieces.append(piece)
        return piece
    }

    /// A shower floor's width and depth from its wall pieces: the longest
    /// piece, and the longest piece on a wall at right angles to it.
    func suggestedFloorSize(in room: ScannedRoom) -> (width: Double, depth: Double)? {
        let sorted = pieces.sorted { ($0.toFt - $0.fromFt) > ($1.toFt - $1.fromFt) }
        guard let first = sorted.first, let w1 = room.wall(first.wallID) else { return nil }
        func dir(_ w: ScannedRoom.Wall) -> (Double, Double) {
            let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
            let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            return (dx / l, dy / l)
        }
        let d1 = dir(w1)
        guard let second = sorted.dropFirst().first(where: { p in
            guard let w = room.wall(p.wallID) else { return false }
            let d = dir(w)
            return abs(d1.0 * d.0 + d1.1 * d.1) < 0.5
        }) else { return nil }
        return (first.toFt - first.fromFt, second.toFt - second.fromFt)
    }

    /// A shower floor placed in the corner the shower's walls make: the
    /// longest piece and the longest piece at right angles to it, each side
    /// as long as its piece. A shower on one wall gets a 3′ deep rectangle
    /// out from it. nil without pieces.
    func suggestedFloorRect(in room: ScannedRoom) -> FloorRect? {
        let sorted = pieces.sorted { ($0.toFt - $0.fromFt) > ($1.toFt - $1.fromFt) }
        guard let first = sorted.first, let w1 = room.wall(first.wallID) else { return nil }
        let ends1 = (room.point(on: w1, along: first.fromFt), room.point(on: w1, along: first.toFt))
        let len1 = first.toFt - first.fromFt
        let inward1 = inwardNormal(of: w1, in: room)

        func unit(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> ScannedRoom.Point {
            let dx = b.x - a.x, dy = b.y - a.y
            let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            return .init(x: dx / l, y: dy / l)
        }
        func d(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> Double {
            ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
        }

        let along1 = unit(ends1.0, ends1.1)
        if let second = sorted.dropFirst().first(where: { p in
            guard let w = room.wall(p.wallID) else { return false }
            let a = unit(w.start, w.end)
            return abs(a.x * along1.x + a.y * along1.y) < 0.5
        }), let w2 = room.wall(second.wallID) {
            let ends2 = (room.point(on: w2, along: second.fromFt), room.point(on: w2, along: second.toFt))
            // The corner: the pair of ends closest together.
            let pairs = [(ends1.0, ends2.0), (ends1.0, ends2.1), (ends1.1, ends2.0), (ends1.1, ends2.1)]
            let corner = pairs.min { d($0.0, $0.1) < d($1.0, $1.1) }!
            let far1 = d(corner.0, ends1.0) < d(corner.0, ends1.1) ? ends1.1 : ends1.0
            let far2 = d(corner.1, ends2.0) < d(corner.1, ends2.1) ? ends2.1 : ends2.0
            return FloorRect(origin: corner.0, u: unit(corner.0, far1), v: unit(corner.1, far2),
                             widthFt: len1, depthFt: second.toFt - second.fromFt)
        }
        return FloorRect(origin: ends1.0, u: along1, v: inward1, widthFt: len1, depthFt: 3)
    }

    /// The unit vector from a wall into the room.
    private func inwardNormal(of wall: ScannedRoom.Wall, in room: ScannedRoom) -> ScannedRoom.Point {
        let dx = wall.end.x - wall.start.x, dy = wall.end.y - wall.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        var n = ScannedRoom.Point(x: -dy / l, y: dx / l)
        let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
        let cx = pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1))
        let cy = pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1))
        if (cx - wall.start.x) * n.x + (cy - wall.start.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
        return n
    }

    /// Puts the takeoff's square feet into the area, and stone curbs, caps
    /// and jambs on their own lines (`stoneLines`).
    func apply(_ room: ScannedRoom, to section: inout EstimateSection, prices: StonePrices = .init()) {
        section.scanTakeoff = self
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let walls = r2(wallsSqft(in: room))
        switch section.area {
        case .floor:
            section.measurements.sqft = r2(floorSqft(in: room))
        case .wall, .backsplash, .fireplace:
            section.measurements.sqft = walls
        case .shower:
            setWalls(room, total: walls, keyPath: \.showerWallsSqft, section: &section)
            section.measurements.showerFloorSqft = r2(floorSqft(in: room))
            section.measurements.ceilingSqft = r2(ceilingSqft(in: room))
        case .tub:
            setWalls(room, total: walls, keyPath: \.sqft, section: &section)
            section.measurements.ceilingSqft = r2(ceilingSqft(in: room))
        case nil:
            break
        }
        let pieces = trimPieces(in: room, area: section.area, curbHeightIn: prices.curbHeightIn)
        for kind in TrimKind.allCases {
            let id = Self.stoneLineID(section.id, kind)
            let stone = pieces.filter { $0.kind == kind && $0.stone }
            let rate = prices.rate(kind)
            let feet = stone.reduce(0) { $0 + $1.lengthFt }
            // By the square foot once a width is set and chosen in Admin.
            let lf = ((rate.usesSqft ? rate.sqft(linFt: feet) : feet) * 100).rounded() / 100
            let unit = rate.usesSqft ? "sq ft" : "lin ft"
            let price = rate.usesSqft ? rate.perSqft : rate.perLinFt
            // Caps and headers share a price; the line says which it has.
            let headers = stone.contains { $0.key.hasPrefix("header:") }
            let caps = stone.contains { !$0.key.hasPrefix("header:") }
            let name = kind != .cap ? kind.stoneLine
                : headers && caps ? "Stone wall cap & header" : headers ? "Stone header" : kind.stoneLine
            if lf > 0 {
                if let i = section.additionsLabor.firstIndex(where: { $0.id == id }) {
                    section.additionsLabor[i].qty = lf
                    if section.additionsLabor[i].unit != unit {
                        section.additionsLabor[i].unit = unit
                        section.additionsLabor[i].rate = price
                    }
                    // Renamed only while it still has a name the app gave it.
                    if TrimKind.capLineNames.contains(section.additionsLabor[i].activity) {
                        section.additionsLabor[i].activity = name
                    }
                } else {
                    section.additionsLabor.append(AdditionItem(id: id, activity: name, qty: lf, rate: price, unit: unit))
                }
            } else {
                section.additionsLabor.removeAll { $0.id == id }
            }
        }
        // What's placed on the walls sets the area's features (owner's call:
        // "Use these measurements" overrides typed counts).
        if itemsPlaced, section.area != .floor {
            section.features = placedFeatures(keeping: section.features)
        }
    }

    /// Linear feet of stone in a niche: all around is the top, sides, base
    /// shelf and dividers; shelves only is the base shelf and dividers.
    static func nicheStoneFt(_ n: Item) -> Double {
        let w = n.widthFt, h = n.heightIn / 12
        switch n.stone {
        case .tile: return 0
        case .all: return 2 * (w + h) + Double(n.dividers) * w
        case .shelves: return Double(1 + n.dividers) * w
        }
    }

    /// A stone window wrap: all the way round.
    static func windowStoneFt(_ w: Item) -> Double {
        w.stone == .tile ? 0 : 2 * (w.widthFt + w.heightIn / 12)
    }

    /// The area's features from what's placed: counts of each, and each
    /// bench, niche and window with its size for pricing.
    func placedFeatures(keeping old: Features) -> Features {
        var f = old
        func count(_ k: Item.Kind) -> Int { items.filter { $0.kind == k }.count }
        f.niches = count(.niche)
        f.windows = count(.window)
        f.shelves = count(.cornerShelf)
        f.footrests = count(.cornerFootrest)
        f.seats = count(.cornerSeat)
        f.benches = count(.framedBench) + count(.floatingBench)
        func inches(_ v: Double) -> String { "\(Int((v).rounded()))″" }
        f.sized = items.compactMap { i in
            switch i.kind {
            case .framedBench, .floatingBench:
                return SizedFeature(kind: .bench, label: "\(i.kind.name) \(feetAndInches(i.widthFt))", linFt: i.widthFt)
            case .niche:
                let stone = i.stone == .all ? ", stone all around" : i.stone == .shelves ? ", stone shelves" : ""
                return SizedFeature(kind: .niche, label: "Niche \(inches(i.widthFt * 12)) × \(inches(i.heightIn))\(stone)",
                                    linFt: Self.nicheStoneFt(i), stone: i.stone != .tile)
            case .window:
                return SizedFeature(kind: .window, label: "Window \(inches(i.widthFt * 12)) × \(inches(i.heightIn))\(i.stone == .tile ? "" : ", stone wrap")",
                                    linFt: Self.windowStoneFt(i), stone: i.stone != .tile)
            default:
                return nil
            }
        }
        return f
    }

    // MARK: Placing items

    /// Where a bench goes along a wall: the shower floor's side against that
    /// wall — wall to wall, or a framed bench to flush with the outside of the
    /// curb (`curbWidthFt` past the floor). A floating bench needs a wall at
    /// both ends: nil without. With no floor drawn: this area's tile on the
    /// wall, else the whole wall.
    func benchSpan(on wall: ScannedRoom.Wall, in room: ScannedRoom, floating: Bool, curbWidthFt: Double = 0) -> ClosedRange<Double>? {
        if floor == .drawn, let r = floorRect {
            let c = r.corners
            for i in 0..<4 {
                let a = c[i], b = c[(i + 1) % 4]
                guard room.distanceToWall(a, wall) < 0.4, room.distanceToWall(b, wall) < 0.4 else { continue }
                var lo = room.along(a, on: wall), hi = room.along(b, on: wall)
                var loPoint = a, hiPoint = b
                if lo > hi { swap(&lo, &hi); swap(&loPoint, &hiPoint) }
                let sides = openSides(in: room)
                func open(_ p: ScannedRoom.Point) -> Bool {
                    sides.contains { s in
                        hypot(s.a.x - p.x, s.a.y - p.y) < 0.05 || hypot(s.b.x - p.x, s.b.y - p.y) < 0.05
                    }
                }
                if floating, open(loPoint) || open(hiPoint) { return nil }
                if !floating {
                    if open(loPoint) { lo = max(0, lo - curbWidthFt) }
                    if open(hiPoint) { hi = min(wall.lengthFt, hi + curbWidthFt) }
                }
                return hi - lo > 0.5 ? lo...hi : nil
            }
        }
        let mine = pieces.filter { $0.wallID == wall.id }
        if floating, room.isFreeEnd(of: wall, start: true) || room.isFreeEnd(of: wall, start: false) { return nil }
        if let lo = mine.map(\.fromFt).min(), let hi = mine.map(\.toFt).max(), hi - lo > 0.5 { return lo...hi }
        return 0...wall.lengthFt
    }

    /// A new niche or window in the middle of this area's tile on a wall.
    func middle(of wall: ScannedRoom.Wall, face: Int) -> Double {
        let mine = pieces.filter { $0.wallID == wall.id && $0.face == face }
        guard let lo = mine.map(\.fromFt).min(), let hi = mine.map(\.toFt).max() else { return wall.lengthFt / 2 }
        return (lo + hi) / 2
    }

    /// The unit vector from a wall into the shower (toward its floor's
    /// middle), else into the room; a planned wall's from the face given.
    func inward(_ w: ScannedRoom.Wall, face: Int, in room: ScannedRoom) -> ScannedRoom.Point {
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        var n = ScannedRoom.Point(x: -dy / l, y: dx / l)
        if w.planned { return face == 0 ? n : .init(x: -n.x, y: -n.y) }
        var target: ScannedRoom.Point
        if floor == .drawn, let r = floorRect {
            let c = r.corners
            target = .init(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        } else {
            let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
            target = .init(x: pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1)), y: pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1)))
        }
        let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
        if (target.x - mid.x) * n.x + (target.y - mid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
        return n
    }

    /// A bench's or corner piece's footprint on the plan.
    func footprint(_ item: Item, in room: ScannedRoom) -> [ScannedRoom.Point]? {
        guard let w = room.wall(item.wallID) else { return nil }
        let n = inward(w, face: item.face, in: room)
        let skin = w.planned ? w.thicknessIn / 24 : 0
        func pt(_ along: Double, _ out: Double) -> ScannedRoom.Point {
            let p = room.point(on: w, along: along)
            return .init(x: p.x + n.x * out, y: p.y + n.y * out)
        }
        switch item.kind {
        case .framedBench, .floatingBench:
            let d = skin + item.depthIn / 12
            return [pt(item.fromFt, skin), pt(item.toFt, skin), pt(item.toFt, d), pt(item.fromFt, d)]
        case .cornerShelf, .cornerFootrest, .cornerSeat:
            let size = item.sizeIn / 12
            let corner = item.atStart ? 0.0 : w.lengthFt
            let along = item.atStart ? size : w.lengthFt - size
            return [pt(corner, skin), pt(along, skin), pt(corner, skin + size)]
        default:
            return nil
        }
    }

    /// Benches and corner pieces low enough to walk into that reach into a
    /// shower door's opening: what, and how many inches of the opening.
    func doorClashes(_ door: ScannedRoom.Opening, in room: ScannedRoom) -> [(name: String, inches: Double)] {
        guard let w = door.wallID.flatMap({ room.wall($0) }) else { return [] }
        let s = room.span(of: door)
        let steps = max(2, Int(((s.upperBound - s.lowerBound) * 12).rounded()))
        var out: [(String, Double)] = []
        for item in items where item.wallID != w.id && (item.kind.isBench || item.kind == .cornerSeat || item.kind == .cornerFootrest) {
            guard let poly = footprint(item, in: room), let iw = room.wall(item.wallID) else { continue }
            var inside = 0
            for k in 0...steps {
                let p = room.point(on: w, along: s.lowerBound + (s.upperBound - s.lowerBound) * Double(k) / Double(steps))
                if Self.contains(poly, p) { inside += 1 }
            }
            if inside > 1 {
                let wallName = room.name(of: iw)
                out.append(("The \(item.kind.name.lowercased()) on \(wallName.prefix(1).lowercased() + wallName.dropFirst())", Double(inside - 1)))
            }
        }
        return out
    }

    /// Point in a polygon (on the edge counts).
    static func contains(_ poly: [ScannedRoom.Point], _ p: ScannedRoom.Point) -> Bool {
        var sign = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if abs(cross) < 1e-6 { continue }
            if sign == 0 { sign = cross } else if (sign > 0) != (cross > 0) { return false }
        }
        return true
    }

    /// The end of a wall a corner piece starts at: one that meets another
    /// wall, preferring the start.
    func cornerEnd(of wall: ScannedRoom.Wall, in room: ScannedRoom) -> Bool {
        !room.isFreeEnd(of: wall, start: true) || room.isFreeEnd(of: wall, start: false)
    }

    /// A stone line's id, the same every time for an area and kind, so
    /// re-measuring updates it instead of adding another (its price, once
    /// changed on the estimate, is kept).
    static func stoneLineID(_ sectionID: UUID, _ kind: TrimKind) -> UUID {
        var bytes = sectionID.uuid
        bytes.14 ^= 0x5A
        bytes.13 ^= UInt8(kind.salt)
        return UUID(uuid: bytes)
    }

    /// One total when the walls share a tile; otherwise a wall each, named
    /// by the scan's letter, keeping any tile already chosen for it.
    private func setWalls(_ room: ScannedRoom, total: Double,
                          keyPath: WritableKeyPath<Measurements, Double>, section: inout EstimateSection) {
        if section.walls.isEmpty {
            section.measurements[keyPath: keyPath] = total
            return
        }
        let fallback = section.walls.first?.tile ?? TileChoice()
        var named: [TiledWall] = []
        for wall in room.walls {
            let mine = pieces.filter { $0.wallID == wall.id }
            guard !mine.isEmpty else { continue }
            let name = room.name(of: wall)
            let sq = (mine.reduce(0) { $0 + sqft(of: $1, in: room) } * 100).rounded() / 100
            let existing = section.walls.first { $0.name == name || $0.name == "Knee wall \(wall.label)" }
            named.append(TiledWall(id: existing?.id ?? UUID(), name: name, sqft: sq, tile: existing?.tile ?? fallback))
        }
        let bench = (benchTileSqft(in: room) * 100).rounded() / 100
        if bench > 0 {
            let existing = section.walls.first { $0.name == "Benches" }
            named.append(TiledWall(id: existing?.id ?? UUID(), name: "Benches", sqft: bench, tile: existing?.tile ?? fallback))
        }
        if !named.isEmpty { section.walls = named }
    }
}

/// The width and depth of the box around some points.
func boundingSize(_ points: [ScannedRoom.Point]) -> (Double, Double) {
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
          let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return (0, 0) }
    return (maxX - minX, maxY - minY)
}

/// A dimension, feet and inches to the sixteenth: 8′ 10 1/2″, 6″.
func dimensionText(_ feet: Double) -> String { Lengths.text(feet: feet) }

/// A length to the sixteenth, a whole number of feet without "0″": 7′ 6″, 5′, 13 1/8″.
func feetAndInches(_ feet: Double) -> String { Lengths.text(feet: feet, zeroInches: false) }

// MARK: - Curbs, wall caps and jambs

/// What frames a shower or a knee wall: tile by default (part of the wall
/// square feet), or stone, charged per linear foot on its own line.
enum TrimKind: String, CaseIterable {
    case curb, cap, jamb, benchTop, benchFront
    var salt: Int { switch self { case .curb: 1; case .cap: 2; case .jamb: 3; case .benchTop: 4; case .benchFront: 5 } }
    var item: StoneItem {
        switch self {
        case .curb: .curb
        case .cap: .cap
        case .jamb: .jamb
        case .benchTop: .benchTop
        case .benchFront: .benchFront
        }
    }
    var stoneLine: String {
        switch self {
        case .curb: "Stone curb"
        case .cap: "Stone wall cap"
        case .jamb: "Stone jambs"
        case .benchTop: "Stone bench top"
        case .benchFront: "Stone bench front"
        }
    }
    /// Names the app gives the cap line (headers are priced as caps).
    static let capLineNames: Set<String> = ["Stone wall cap", "Stone header", "Stone wall cap & header"]
}

/// Stone prices, the curb height and starting sizes, from Admin.
struct StonePrices {
    /// Per linear foot, for curb, cap and jamb when `stone` doesn't say.
    var curb: Double = 0
    var cap: Double = 0
    var jamb: Double = 0
    var curbHeightIn: Double = 4
    /// A new shower door opening's width and height (inches).
    var doorWidthIn: Double = 30
    var doorHeightIn: Double = 80
    var stone: [StoneItem: StoneRate] = [:]
    var defaults = ScanItemDefaults()
    func rate(_ k: TrimKind) -> StoneRate {
        if let r = stone[k.item] { return r }
        switch k {
        case .curb: return StoneRate(perLinFt: curb)
        case .cap: return StoneRate(perLinFt: cap)
        case .jamb: return StoneRate(perLinFt: jamb)
        default: return StoneRate()
        }
    }
}

extension StonePrices {
    init(rates r: Rates) {
        self.init(curb: r.stoneCurbPerLinFt, cap: r.stoneCapPerLinFt, jamb: r.stoneJambPerLinFt, curbHeightIn: r.curbHeightIn,
                  doorWidthIn: r.showerDoorWidthIn, doorHeightIn: r.showerDoorHeightIn,
                  stone: Dictionary(uniqueKeysWithValues: StoneItem.allCases.map { ($0, r.stoneRate($0)) }),
                  defaults: r.scanDefaults)
    }
}

/// One curb, wall cap or jamb, worked out from the plan, with the owner's
/// choice applied.
struct TrimPiece: Identifiable, Equatable {
    let key: String
    let kind: TrimKind
    let name: String
    /// As measured from the plan.
    let measuredFt: Double
    var lengthFt: Double
    var stone: Bool
    var id: String { key }
}

extension AreaTakeoff {
    /// The curb, wall caps and jambs this area has.
    /// - Shower with its floor drawn on the plan: the curb along the floor's
    ///   open sides (not against a wall or knee wall); a jamb at each end of
    ///   the entry — from the curb to the top of the tile against a full
    ///   wall, or a lower jamb (curb to cap) and an upper jamb (cap to the
    ///   top of the tile) against a knee wall; and a cap on each knee wall.
    /// - Other areas: a cap on each knee wall they tile, and a jamb on each
    ///   of its open ends, floor to cap.
    func trimPieces(in room: ScannedRoom, area: Area?, curbHeightIn: Double) -> [TrimPiece] {
        var out: [(String, TrimKind, String, Double)] = []
        let curb = (self.curbHeightIn ?? curbHeightIn) / 12
        let ceiling = room.ceilingFt
        // The top of the tile: this area's tallest tile on full walls, else the ceiling.
        let top = pieces.filter { room.wall($0.wallID)?.planned == false }.map { $0.heightIn / 12 }.max() ?? ceiling
        let kneeWalls = room.walls.filter { w in room.isKneeWall(w) && pieces.contains { $0.wallID == w.id } }

        if area == .shower, floor == .drawn, let r = floorRect {
            let c = r.corners
            let sides = openSides(in: room)
            let width = sides.reduce(0.0) { $0 + $1.lengthFt }
            if width > 0 { out.append(("curb", .curb, "Curb", width)) }
            // The entry's ends: a jamb wherever an open side meets a wall.
            let center = ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
            var used = Set<String>()
            for side in sides {
                for (corner, wall) in [(side.a, side.startWall), (side.b, side.endWall)] {
                    guard let wall else { continue }
                    let name = sideName(corner, entry: (side.a, side.b), center: center)
                    var key = "jamb:\(name)", n = 2
                    while used.contains(key) { key = "jamb:\(name):\(n)"; n += 1 }
                    used.insert(key)
                    if room.isKneeWall(wall) {
                        out.append(("\(key):lower", .jamb, "\(name.capitalized) lower jamb", max(0, wall.heightFt - curb)))
                        out.append(("\(key):upper", .jamb, "\(name.capitalized) upper jamb", max(0, top - wall.heightFt)))
                    } else {
                        out.append((key, .jamb, "\(name.capitalized) jamb", max(0, top - curb)))
                    }
                }
            }
            for w in kneeWalls { out.append(("cap:\(w.id)", .cap, "Wall cap (half wall \(w.label))", w.lengthFt)) }
        }
        if area == .shower {
            // Each door opening in a wall this shower tiles: a curb across
            // it, a jamb each side up to the header (or the top of the tile
            // without one), and the header.
            for d in showerDoors(in: room) {
                guard let w = d.wallID.flatMap({ room.wall($0) }) else { continue }
                let s = room.span(of: d)
                let width = s.upperBound - s.lowerBound
                let wallName = room.name(of: w)
                let label = "door in " + wallName.prefix(1).lowercased() + wallName.dropFirst()
                let wallTop = pieces.filter { $0.wallID == w.id }.map { $0.heightIn / 12 }.max() ?? top
                let header = room.hasHeader(d)
                let jambTop = header ? min(d.bottomFt + d.heightFt, wallTop) : wallTop
                out.append(("curb:\(d.id)", .curb, "Curb (\(label))", width))
                for side in ["left", "right"] {
                    out.append(("jamb:\(d.id):\(side)", .jamb, "\(side.capitalized) jamb (\(label))", max(0, jambTop - curb)))
                }
                if header { out.append(("header:\(d.id)", .cap, "Header (\(label))", width)) }
            }
        } else {
            for w in kneeWalls {
                out.append(("cap:\(w.id)", .cap, "Wall cap (half wall \(w.label))", w.lengthFt))
                for start in [true, false] where room.isFreeEnd(of: w, start: start) {
                    out.append(("jamb:\(w.id):\(start ? "start" : "end")", .jamb, "Half wall \(w.label) end jamb", w.heightFt))
                }
            }
        }
        // Each bench's top, and a framed bench's front.
        for b in items where b.kind.isBench {
            out.append(("benchTop:\(b.id)", .benchTop, "\(b.kind.name) top", b.widthFt))
            if b.kind == .framedBench { out.append(("benchFront:\(b.id)", .benchFront, "\(b.kind.name) front", b.widthFt)) }
        }
        return out.map { key, kind, name, ft in
            let choice = trim.first { $0.key == key }
            return TrimPiece(key: key, kind: kind, name: name, measuredFt: ft,
                             lengthFt: choice?.lengthFt ?? ft, stone: choice?.stone ?? false)
        }
    }

    /// A stretch of the shower floor's edge with no wall along it: where
    /// the curb goes. Its ends' walls (nil for an open corner) get jambs.
    struct OpenSide {
        var a: ScannedRoom.Point
        var b: ScannedRoom.Point
        var startWall: ScannedRoom.Wall?
        var endWall: ScannedRoom.Wall?
        var lengthFt: Double { ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() }
    }

    /// The shower floor's open sides: each edge less the stretches a wall
    /// runs along (parallel, within 0.4′), so a knee wall across part of
    /// the front leaves the rest open.
    func openSides(in room: ScannedRoom) -> [OpenSide] {
        guard floor == .drawn, let r = floorRect else { return [] }
        let c = r.corners
        var out: [OpenSide] = []
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            let ex = b.x - a.x, ey = b.y - a.y, length = (ex * ex + ey * ey).squareRoot()
            guard length > 1.0 / 12 else { continue }
            let u = ScannedRoom.Point(x: ex / length, y: ey / length)
            func at(_ t: Double) -> ScannedRoom.Point { .init(x: a.x + u.x * t, y: a.y + u.y * t) }
            // Walls along this edge, as stretches of it.
            var cover: [(lo: Double, hi: Double, wall: ScannedRoom.Wall)] = room.walls.compactMap { w in
                func off(_ p: ScannedRoom.Point) -> Double { abs((p.x - a.x) * -u.y + (p.y - a.y) * u.x) }
                guard off(w.start) < 0.4, off(w.end) < 0.4 else { return nil }
                let t0 = (w.start.x - a.x) * u.x + (w.start.y - a.y) * u.y
                let t1 = (w.end.x - a.x) * u.x + (w.end.y - a.y) * u.y
                let lo = max(0, min(t0, t1)), hi = min(length, max(t0, t1))
                return hi - lo > 1.0 / 12 ? (lo, hi, w) : nil
            }
            cover.sort { $0.lo < $1.lo }
            // The wall at a corner of the floor: one across this edge's end.
            func cornerWall(_ p: ScannedRoom.Point) -> ScannedRoom.Wall? {
                room.walls.filter { w in
                    let wx = w.end.x - w.start.x, wy = w.end.y - w.start.y
                    let wl = max((wx * wx + wy * wy).squareRoot(), 1e-9)
                    return abs((wx * u.x + wy * u.y) / wl) < 0.5 && room.distanceToWall(p, w) < 0.4
                }.min { room.distanceToWall(p, $0) < room.distanceToWall(p, $1) }
            }
            var cursor = 0.0
            var last: ScannedRoom.Wall? = nil
            for k in cover {
                if k.lo - cursor > 1.0 / 12 {
                    out.append(OpenSide(a: at(cursor), b: at(k.lo), startWall: cursor == 0 ? cornerWall(a) : last, endWall: k.wall))
                }
                if k.hi >= cursor { cursor = k.hi; last = k.wall }
            }
            if length - cursor > 1.0 / 12 {
                out.append(OpenSide(a: at(cursor), b: b, startWall: cursor == 0 ? cornerWall(a) : last, endWall: cornerWall(b)))
            }
        }
        return out
    }

    /// Where a new wall goes to close the shower: on the curb, along each
    /// open side.
    func newWallLines(in room: ScannedRoom, thicknessIn: Double = 0) -> [(ScannedRoom.Point, ScannedRoom.Point)] {
        openSides(in: room).map { ($0.a, $0.b) }
    }

    /// A wall being drawn from `a` to `b`: when it runs along an open side of
    /// the shower floor (roughly parallel, within 2′), it takes that side's
    /// place, on the curb (`newWallLines`).
    func snappedNewWall(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point, in room: ScannedRoom,
                        thicknessIn: Double) -> (ScannedRoom.Point, ScannedRoom.Point) {
        let dx = b.x - a.x, dy = b.y - a.y, l = (dx * dx + dy * dy).squareRoot()
        guard l > 0.5 else { return (a, b) }
        let mid = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var best: ((ScannedRoom.Point, ScannedRoom.Point), Double)? = nil
        for (p, q) in newWallLines(in: room, thicknessIn: thicknessIn) {
            let ex = q.x - p.x, ey = q.y - p.y, el = max((ex * ex + ey * ey).squareRoot(), 1e-9)
            guard abs((dx * ex + dy * ey) / (l * el)) > 0.9 else { continue }
            // Distance from the drawn line's middle to the side, across and along.
            let across = abs((mid.x - p.x) * -ey / el + (mid.y - p.y) * ex / el)
            let along = ((mid.x - p.x) * ex + (mid.y - p.y) * ey) / el
            guard across < 2, along > -1, along < el + 1, across < (best?.1 ?? .infinity) else { continue }
            // Keep the direction it was drawn in.
            let same = dx * ex + dy * ey > 0
            best = (same ? (p, q) : (q, p), across)
        }
        return best?.0 ?? (a, b)
    }

    /// Shower door openings in walls this area tiles.
    func showerDoors(in room: ScannedRoom) -> [ScannedRoom.Opening] {
        room.openings.filter { o in o.kind == .showerDoor && pieces.contains { $0.wallID == o.wallID } }
    }

    /// Where the curb goes: the shower floor's open sides, and across each
    /// shower door.
    func curbEdges(in room: ScannedRoom) -> [(ScannedRoom.Point, ScannedRoom.Point)] {
        let doors: [(ScannedRoom.Point, ScannedRoom.Point)] = showerDoors(in: room).compactMap { d in
            guard let w = d.wallID.flatMap({ room.wall($0) }) else { return nil }
            let s = room.span(of: d)
            return (room.point(on: w, along: s.lowerBound), room.point(on: w, along: s.upperBound))
        }
        return doors + openSides(in: room).map { ($0.a, $0.b) }
    }

    /// "left" or "right", as you stand outside the shower facing in.
    private func sideName(_ corner: ScannedRoom.Point, entry: (ScannedRoom.Point, ScannedRoom.Point),
                          center: ScannedRoom.Point) -> String {
        let mid = ScannedRoom.Point(x: (entry.0.x + entry.1.x) / 2, y: (entry.0.y + entry.1.y) / 2)
        // Facing in: from the entry toward the middle of the floor.
        let fx = center.x - mid.x, fy = center.y - mid.y
        // Your right hand (the plan reads like a map, y down the screen).
        let rx = -fy, ry = fx
        return (corner.x - mid.x) * rx + (corner.y - mid.y) * ry > 0 ? "right" : "left"
    }

    /// Linear feet of stone of one kind.
    func stoneFt(_ kind: TrimKind, in room: ScannedRoom, area: Area?, curbHeightIn: Double) -> Double {
        trimPieces(in: room, area: area, curbHeightIn: curbHeightIn).filter { $0.kind == kind && $0.stone }
            .reduce(0) { $0 + $1.lengthFt }
    }
}


// MARK: - Calibrating a scan to tape measurements

extension ScanCalibration {
    /// A plan point moved by the correction.
    func map(_ p: ScannedRoom.Point) -> ScannedRoom.Point {
        let c = cos(angle), s = sin(angle)
        let dx = p.x - center.x, dy = p.y - center.y
        let a = (dx * c + dy * s) * sx, b = (-dx * s + dy * c) * sy
        return .init(x: center.x + a * c - b * s, y: center.y + a * s + b * c)
    }

    /// A direction on the plan stretched by the correction (not moved).
    func mapVector(_ v: ScannedRoom.Point) -> ScannedRoom.Point {
        let c = cos(angle), s = sin(angle)
        let a = (v.x * c + v.y * s) * sx, b = (-v.x * s + v.y * c) * sy
        return .init(x: a * c - b * s, y: a * s + b * c)
    }

    /// Undoes it.
    var inverse: ScanCalibration {
        var i = self
        i.sx = 1 / sx; i.sy = 1 / sy; i.sz = 1 / sz
        return i
    }

    /// What it does to a wall: how much longer (1.01 = 1% longer).
    func lengthFactor(of w: ScannedRoom.Wall) -> Double {
        let d = mapVector(.init(x: w.end.x - w.start.x, y: w.end.y - w.start.y))
        return w.lengthFt > 0 ? hypot(d.x, d.y) / w.lengthFt : 1
    }

    /// The correction that makes the scan match tape measurements (wall id →
    /// inches) and, if given, the ceiling height. Walls running one way set
    /// that way's scale, walls the other way the other's; with walls only
    /// one way (or slanting), the scale is the same both ways.
    static func solve(_ room: ScannedRoom, tapeIn: [UUID: Double], ceilingIn: Double? = nil) -> ScanCalibration {
        var c = ScanCalibration()
        c.angle = room.squaringAngle
        let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
        c.center = .init(x: pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1)),
                         y: pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1)))
        let u = ScannedRoom.Point(x: cos(c.angle), y: sin(c.angle))
        var along: [Double] = [], across: [Double] = [], slanting: [Double] = []
        for (id, inches) in tapeIn where inches > 0 {
            guard let w = room.wall(id), w.lengthFt > 0 else { continue }
            let ratio = inches / (w.lengthFt * 12)
            let du = abs((w.end.x - w.start.x) * u.x + (w.end.y - w.start.y) * u.y) / w.lengthFt
            if du > 0.9 { along.append(ratio) } else if du < 0.44 { across.append(ratio) } else { slanting.append(ratio) }
        }
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let both = mean(along + across + slanting) ?? 1
        c.sx = mean(along) ?? both
        c.sy = mean(across) ?? both
        if let ceilingIn, ceilingIn > 0 { c.sz = ceilingIn / (room.ceilingFt * 12) }
        c.tapeIn = Dictionary(uniqueKeysWithValues: tapeIn.map { ($0.key.uuidString, $0.value) })
        c.ceilingIn = ceilingIn
        return c
    }
}

extension ScannedRoom {
    /// The room corrected: every wall, door, window, the floor, the tub and
    /// fixtures. A shower door and walls drawn in keep their size and
    /// thickness (they're the owner's choices) and move with the room.
    func calibrated(_ c: ScanCalibration, recording: Bool = true) -> ScannedRoom {
        var r = self
        var factor: [UUID: Double] = [:]
        for i in r.walls.indices {
            let w = r.walls[i]
            factor[w.id] = c.lengthFactor(of: w)
            r.walls[i].start = c.map(w.start)
            r.walls[i].end = c.map(w.end)
            r.walls[i].lengthFt = hypot(r.walls[i].end.x - r.walls[i].start.x, r.walls[i].end.y - r.walls[i].start.y)
            if !w.planned { r.walls[i].heightFt = w.heightFt * c.sz }
        }
        for i in r.openings.indices {
            let o = r.openings[i]
            let k = o.wallID.flatMap { factor[$0] } ?? 1
            r.openings[i].alongFt = o.alongFt.map { $0 * k }
            if o.kind != .showerDoor {
                r.openings[i].widthFt = o.widthFt * k
                r.openings[i].heightFt = o.heightFt * c.sz
                r.openings[i].bottomFt = o.bottomFt * c.sz
            }
        }
        r.floorOutline = floorOutline.map(c.map)
        r.floorSqft = floorOutline.count > 2 ? ScannedRoom.area(r.floorOutline) : floorSqft * c.sx * c.sy
        r.tubOutline = tubOutline.map(c.map)
        if r.tubOutline.count == 4 {
            let t = r.tubOutline
            r.tubLengthFt = max(hypot(t[1].x - t[0].x, t[1].y - t[0].y), hypot(t[3].x - t[0].x, t[3].y - t[0].y))
        }
        r.fixtures = fixtures.map { f in
            var f = f
            f.outline = f.outline.map(c.map)
            f.heightFt *= c.sz
            return f
        }
        if recording { r.calibrations.append(c) }
        return r
    }

    /// The last calibration taken back off.
    var uncalibrated: ScannedRoom? {
        guard let last = calibrations.last else { return nil }
        var r = calibrated(last.inverse, recording: false)
        r.calibrations.removeLast()
        return r
    }
}

extension AreaTakeoff {
    /// This area's choices moved with a corrected scan (`before` is the scan
    /// they were made on): tile stretches along their walls, a full-height
    /// piece staying full height, items along their walls and the shower
    /// floor's rectangle. Sizes the owner chose — tile heights, niches,
    /// windows, benches, corner pieces — are kept.
    func calibrated(_ c: ScanCalibration, before: ScannedRoom) -> AreaTakeoff {
        var t = self
        func k(_ id: UUID) -> Double { before.wall(id).map { c.lengthFactor(of: $0) } ?? 1 }
        for i in t.pieces.indices {
            let p = t.pieces[i]
            t.pieces[i].fromFt = p.fromFt * k(p.wallID)
            t.pieces[i].toFt = p.toFt * k(p.wallID)
            if let w = before.wall(p.wallID), !w.planned, abs(p.heightIn - w.heightFt * 12) < 1 {
                t.pieces[i].heightIn = (w.heightFt * c.sz * 12).rounded(.down)
            }
        }
        for i in t.items.indices {
            let it = t.items[i]
            let f = k(it.wallID)
            if it.kind.isBench {
                t.items[i].fromFt = it.fromFt * f
                t.items[i].toFt = it.toFt * f
            } else if !it.kind.isCorner {
                // Keep its size; move its middle.
                let mid = (it.fromFt + it.toFt) / 2 * f, half = it.widthFt / 2
                t.items[i].fromFt = mid - half
                t.items[i].toFt = mid + half
            }
        }
        if let r = t.floorRect {
            let u = c.mapVector(.init(x: r.u.x * r.widthFt, y: r.u.y * r.widthFt))
            let v = c.mapVector(.init(x: r.v.x * r.depthFt, y: r.v.y * r.depthFt))
            let lu = hypot(u.x, u.y), lv = hypot(v.x, v.y)
            t.floorRect = FloorRect(origin: c.map(r.origin), u: .init(x: u.x / max(lu, 1e-9), y: u.y / max(lu, 1e-9)),
                                    v: .init(x: v.x / max(lv, 1e-9), y: v.y / max(lv, 1e-9)), widthFt: lu, depthFt: lv)
        }
        return t
    }
}


// MARK: - Areas suggested from a scan

/// An area a scan seems to have: what it is, where (to highlight on the
/// plan), and the choices it would start with.
struct ScanSuggestion: Identifiable {
    var id: String { title }
    let area: Area
    /// "Floor", "Tub surround", "Possible shower", "Backsplash".
    let title: String
    let outline: [ScannedRoom.Point]
    let takeoff: AreaTakeoff
}

extension ScannedRoom {
    /// What this scan seems to hold, leaving out kinds of area the room
    /// already has. Apple's scanner finds tubs and cabinets but not showers:
    /// a shower is guessed from an alcove of three walls with no tub in it.
    func suggestions(skipping existing: Set<Area> = []) -> [ScanSuggestion] {
        var out: [ScanSuggestion] = []
        if !existing.contains(.shower) {
            for alcove in showerAlcoves() {
                out.append(ScanSuggestion(area: .shower, title: "Possible shower", outline: alcove.floorRect?.corners ?? [],
                                          takeoff: alcove))
            }
        }
        if !existing.contains(.tub), tubOutline.count > 2 {
            var t = AreaTakeoff.starting(for: .tub, room: self, otherAreas: [])
            for w in walls where !w.planned {
                let near = tubOutline.filter { distanceToWall($0, w) < 0.75 }.map { along($0, on: w) }
                guard near.count >= 2, let lo = near.min(), let hi = near.max(), hi - lo > 0.5 else { continue }
                t.pieces.append(.init(wallID: w.id, fromFt: lo, toFt: hi, heightIn: AreaTakeoff.startingHeight(for: .tub, wall: w)))
            }
            out.append(ScanSuggestion(area: .tub, title: "Tub surround", outline: tubOutline, takeoff: t))
        }
        if !existing.contains(.floor), floorOutline.count > 2 {
            out.append(ScanSuggestion(area: .floor, title: "Floor", outline: floorOutline,
                                      takeoff: AreaTakeoff.starting(for: .floor, room: self, otherAreas: [])))
        }
        if !existing.contains(.backsplash) {
            for f in fixtures where (f.kind == "Cabinet" || f.kind == "Sink") && f.outline.count == 4 {
                // The cabinet's back edge against a wall.
                for w in walls where !w.planned {
                    let near = f.outline.filter { distanceToWall($0, w) < 0.6 }.map { along($0, on: w) }
                    guard near.count >= 2, let lo = near.min(), let hi = near.max(), hi - lo > 1 else { continue }
                    var t = AreaTakeoff()
                    t.pieces = [.init(wallID: w.id, fromFt: lo, toFt: hi, heightIn: AreaTakeoff.startingHeight(for: .backsplash, wall: w))]
                    out.append(ScanSuggestion(area: .backsplash, title: "Backsplash", outline: f.outline, takeoff: t))
                    break
                }
                break
            }
        }
        return out
    }

    /// Alcoves that could be a shower: a back wall 2½–7′ long with a wall at
    /// each end running the same way into the room, 2½–7′ deep, no tub in
    /// it, and the room going on past its open side. Each comes as a shower's
    /// starting choices: its three walls tiled full height and its floor drawn.
    func showerAlcoves() -> [AreaTakeoff] {
        let pts = floorOutline.isEmpty ? walls.flatMap { [$0.start, $0.end] } : floorOutline
        let center = Point(x: pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1)),
                           y: pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1)))
        func d(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }
        let real = walls.filter { !$0.planned }
        var out: [AreaTakeoff] = []
        for back in real where back.lengthFt >= 2.5 && back.lengthFt <= 7 {
            let ux = (back.end.x - back.start.x) / back.lengthFt, uy = (back.end.y - back.start.y) / back.lengthFt
            var n = Point(x: -uy, y: ux)
            let mid = Point(x: (back.start.x + back.end.x) / 2, y: (back.start.y + back.end.y) / 2)
            if (center.x - mid.x) * n.x + (center.y - mid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
            /// The wall leaving this corner into the room, and how far it goes.
            func side(at corner: Point) -> (Wall, Double)? {
                for w in real where w.id != back.id {
                    let (near, far) = d(w.start, corner) < 0.4 ? (w.start, w.end) : d(w.end, corner) < 0.4 ? (w.end, w.start) : (nil, nil)
                    guard let near, let far else { continue }
                    let dx = far.x - near.x, dy = far.y - near.y, l = hypot(dx, dy)
                    guard l > 0.1, (dx * n.x + dy * n.y) / l > 0.95 else { continue }
                    return (w, l)
                }
                return nil
            }
            guard let (s1, l1) = side(at: back.start), let (s2, l2) = side(at: back.end) else { continue }
            let depth = min(l1, l2)
            guard depth >= 2.5, depth <= 7 else { continue }
            // The room goes on past the open side.
            guard (center.x - mid.x) * n.x + (center.y - mid.y) * n.y > depth + 1 else { continue }
            var t = AreaTakeoff()
            t.floor = .drawn
            t.floorRect = AreaTakeoff.FloorRect(origin: back.start, u: .init(x: ux, y: uy), v: n,
                                                widthFt: back.lengthFt, depthFt: depth)
            // No tub in it.
            if tubOutline.count > 2 {
                let tc = Point(x: tubOutline.map(\.x).reduce(0, +) / Double(tubOutline.count),
                               y: tubOutline.map(\.y).reduce(0, +) / Double(tubOutline.count))
                if AreaTakeoff.contains(t.floorRect!.corners, tc) { continue }
            }
            t.pieces.append(.init(wallID: back.id, fromFt: 0, toFt: back.lengthFt,
                                  heightIn: AreaTakeoff.startingHeight(for: .shower, wall: back)))
            for (w, corner) in [(s1, back.start), (s2, back.end)] {
                let a = along(corner, on: w)
                let lo = a < w.lengthFt / 2 ? a : max(0, a - depth), hi = a < w.lengthFt / 2 ? min(w.lengthFt, a + depth) : a
                t.pieces.append(.init(wallID: w.id, fromFt: lo, toFt: hi, heightIn: AreaTakeoff.startingHeight(for: .shower, wall: w)))
            }
            out.append(t)
        }
        return out
    }
}


// MARK: - Placing and turning the shower floor

extension AreaTakeoff.FloorRect {
    var center: ScannedRoom.Point {
        let c = corners
        return .init(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
    }

    /// Turned a quarter turn, staying in its corner: width and depth swap,
    /// the corner it was placed from stays put (so a floor in a corner of
    /// walls stays against them).
    var turned: AreaTakeoff.FloorRect {
        var r = self
        r.widthFt = depthFt
        r.depthFt = widthFt
        return r
    }
}

extension ScannedRoom {
    /// Inside corners of the room, where two scanned walls meet: the corner
    /// and the direction along each wall away from it.
    func insideCorners() -> [(at: Point, a: Point, b: Point)] {
        let real = walls.filter { !$0.planned }
        func d(_ p: Point, _ q: Point) -> Double { hypot(p.x - q.x, p.y - q.y) }
        func away(_ w: Wall, from p: Point) -> Point? {
            let (near, far) = d(w.start, p) < 0.4 ? (w.start, w.end) : d(w.end, p) < 0.4 ? (w.end, w.start) : (nil, nil)
            guard let near, let far else { return nil }
            let l = max(hypot(far.x - near.x, far.y - near.y), 1e-9)
            return .init(x: (far.x - near.x) / l, y: (far.y - near.y) / l)
        }
        var out: [(Point, Point, Point)] = []
        for (i, w1) in real.enumerated() {
            for p in [w1.start, w1.end] {
                for w2 in real[(i + 1)...] {
                    guard let a = away(w1, from: p), let b = away(w2, from: p),
                          abs(a.x * b.x + a.y * b.y) < 0.3 else { continue }
                    // Inside the room: a step in along both walls is on the floor.
                    let probe = Point(x: p.x + (a.x + b.x) * 0.5, y: p.y + (a.y + b.y) * 0.5)
                    if floorOutline.count > 2, !AreaTakeoff.inside(floorOutline, probe) { continue }
                    out.append((p, a, b))
                }
            }
        }
        return out
    }
}

extension AreaTakeoff {
    /// Point in any polygon (even–odd).
    static func inside(_ poly: [ScannedRoom.Point], _ p: ScannedRoom.Point) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }

    /// The shower moved to the room's inside corner nearest `tap`: its floor
    /// there at its present size (5′ × 3′ if it has none), the long side along
    /// the longer wall, and the walls round it tiled. nil with no corner.
    mutating func placeShower(near tap: ScannedRoom.Point, in room: ScannedRoom) -> Bool {
        guard let corner = room.insideCorners().min(by: {
            hypot($0.at.x - tap.x, $0.at.y - tap.y) < hypot($1.at.x - tap.x, $1.at.y - tap.y)
        }) else { return false }
        let long = max(floorRect?.widthFt ?? 5, floorRect?.depthFt ?? 3)
        let short = min(floorRect?.widthFt ?? 5, floorRect?.depthFt ?? 3)
        // Along each wall from the corner, as far as it goes.
        func reach(_ dir: ScannedRoom.Point) -> Double {
            room.walls.filter { !$0.planned }.compactMap { w -> Double? in
                // The wall running that way from the corner.
                let wx = (w.end.x - w.start.x) / max(w.lengthFt, 1e-9), wy = (w.end.y - w.start.y) / max(w.lengthFt, 1e-9)
                guard abs(wx * dir.x + wy * dir.y) > 0.9 else { return nil }
                let mid = ScannedRoom.Point(x: corner.at.x + dir.x * 0.2, y: corner.at.y + dir.y * 0.2)
                return room.distanceToWall(mid, w) < 0.3 ? w.lengthFt : nil
            }.max() ?? long
        }
        let ra = reach(corner.a), rb = reach(corner.b)
        let (u, v, along, deep) = ra >= rb ? (corner.a, corner.b, ra, rb) : (corner.b, corner.a, rb, ra)
        floor = .drawn
        floorRect = FloorRect(origin: corner.at, u: u, v: v, widthFt: min(long, along), depthFt: min(short, deep))
        tileWallsAroundFloor(in: room)
        return true
    }

    /// The scanned walls the shower floor stands against, tiled along the
    /// floor's sides: each keeps the height its tile had (else the top of the
    /// wall); walls drawn in and other walls' tile are left alone.
    mutating func tileWallsAroundFloor(in room: ScannedRoom) {
        guard floor == .drawn, let r = floorRect else { return }
        let c = r.corners
        var kept: [Piece] = pieces.filter { room.wall($0.wallID)?.planned == true }
        var used = Set<UUID>()
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            let dx = b.x - a.x, dy = b.y - a.y, l = max(hypot(dx, dy), 1e-9)
            let mid = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            guard let w = room.walls.first(where: { w in
                guard !w.planned else { return false }
                let wx = w.end.x - w.start.x, wy = w.end.y - w.start.y, wl = max(hypot(wx, wy), 1e-9)
                return abs((dx * wx + dy * wy) / (l * wl)) > 0.95 && room.distanceToWall(mid, w) < 0.4
            }) else { continue }
            let lo = min(room.along(a, on: w), room.along(b, on: w)), hi = max(room.along(a, on: w), room.along(b, on: w))
            guard hi - lo > 0.1 else { continue }
            let height = pieces.first { $0.wallID == w.id }?.heightIn ?? Self.startingHeight(for: .shower, wall: w)
            let id = used.contains(w.id) ? UUID() : (pieces.first { $0.wallID == w.id }?.id ?? UUID())
            used.insert(w.id)
            kept.append(Piece(id: id, wallID: w.id, fromFt: lo, toFt: hi, heightIn: height))
        }
        pieces = kept
        items.removeAll { item in room.wall(item.wallID).map { !$0.planned } == true && !kept.contains { $0.wallID == item.wallID } }
    }
}


// MARK: - Editing the scanned room

extension ScannedRoom {
    private static func dist(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }

    /// Where two lines cross (a point and direction each); nil if parallel.
    private static func intersect(_ p: Point, _ u: Point, _ q: Point, _ v: Point) -> Point? {
        let den = u.x * v.y - u.y * v.x
        guard abs(den) > 1e-9 else { return nil }
        let t = ((q.x - p.x) * v.y - (q.y - p.y) * v.x) / den
        return .init(x: p.x + u.x * t, y: p.y + u.y * t)
    }

    private static func unit(_ w: Wall) -> Point {
        let l = max(dist(w.start, w.end), 1e-9)
        return .init(x: (w.end.x - w.start.x) / l, y: (w.end.y - w.start.y) / l)
    }

    /// True when `p` lies on wall `w`'s run, away from its ends.
    private func onRun(_ p: Point, _ w: Wall) -> Bool {
        distanceToWall(p, w) < 0.35 && Self.dist(p, w.start) > 0.35 && Self.dist(p, w.end) > 0.35
    }

    /// A wall slid sideways (square to itself) by `d` feet on the plan,
    /// rounded to the inch, keeping the room joined: a wall sharing a corner
    /// stretches to follow; an end that meets the middle of another wall slides
    /// along it; a wall running into this one follows it. Doors and windows
    /// keep their places in their walls, and the floor outline follows.
    mutating func moveWall(_ id: UUID, by d: Point) {
        guard let w = wall(id) else { return }
        let u = Self.unit(w), n = Point(x: -u.y, y: u.x)
        let off = ((d.x * n.x + d.y * n.y) * 12).rounded() / 12
        guard abs(off) > 1e-9 else { return }
        let before = self
        let shift = Point(x: n.x * off, y: n.y * off)
        let lineP = Point(x: w.start.x + shift.x, y: w.start.y + shift.y)
        // Each end: on another wall's run, it slides along that wall; else it moves with the wall.
        func newEnd(_ old: Point) -> Point {
            if let host = walls.first(where: { $0.id != id && onRun(old, $0) }),
               let p = Self.intersect(lineP, u, host.start, Self.unit(host)) { return p }
            return Point(x: old.x + shift.x, y: old.y + shift.y)
        }
        setEnds(id, start: newEnd(w.start), end: newEnd(w.end), from: before)
        // Walls running into this one follow it.
        for j in walls.indices where walls[j].id != id {
            let o = walls[j]
            for isStart in [true, false] {
                let p = isStart ? o.start : o.end
                guard before.onRun(p, w), let q = Self.intersect(lineP, u, o.start, Self.unit(o)) else { continue }
                if isStart { walls[j].start = q } else { walls[j].end = q }
            }
            walls[j].lengthFt = Self.dist(walls[j].start, walls[j].end)
        }
        followAll(from: before)
    }

    /// One end of a wall moved to `p`: a wall sharing that corner follows.
    mutating func moveWallEnd(_ id: UUID, start: Bool, to p: Point) {
        guard let w = wall(id) else { return }
        let before = self
        setEnds(id, start: start ? p : w.start, end: start ? w.end : p, from: before)
        followAll(from: before)
    }

    /// A wall's ends set, and the walls sharing each old corner moved with it.
    private mutating func setEnds(_ id: UUID, start s: Point, end e: Point, from before: ScannedRoom) {
        guard let i = walls.firstIndex(where: { $0.id == id }) else { return }
        let old = walls[i]
        for (oldP, newP) in [(old.start, s), (old.end, e)] where Self.dist(oldP, newP) > 1e-9 {
            for j in walls.indices where j != i {
                if Self.dist(walls[j].start, oldP) < 0.35 { walls[j].start = newP }
                if Self.dist(walls[j].end, oldP) < 0.35 { walls[j].end = newP }
                walls[j].lengthFt = Self.dist(walls[j].start, walls[j].end)
            }
        }
        walls[i].start = s
        walls[i].end = e
        walls[i].lengthFt = Self.dist(s, e)
    }

    /// After walls moved: doors and windows keep their places along their
    /// walls (and stay on them), and floor-outline corners at moved wall
    /// ends move with them.
    private mutating func followAll(from before: ScannedRoom) {
        for i in openings.indices {
            guard let id = openings[i].wallID, let old = before.wall(id), let new = wall(id),
                  let a = openings[i].alongFt else { continue }
            let u = Self.unit(old)
            let startShift = (new.start.x - old.start.x) * u.x + (new.start.y - old.start.y) * u.y
            let half = openings[i].widthFt / 2
            openings[i].alongFt = min(max(a - startShift, half), max(half, new.lengthFt - half))
        }
        var moved: [(Point, Point)] = []
        for w in before.walls {
            guard let n = wall(w.id) else { continue }
            if Self.dist(w.start, n.start) > 1e-9 { moved.append((w.start, n.start)) }
            if Self.dist(w.end, n.end) > 1e-9 { moved.append((w.end, n.end)) }
        }
        if floorOutline.count > 2, !moved.isEmpty {
            floorOutline = floorOutline.map { p in moved.first { Self.dist($0.0, p) < 0.5 }?.1 ?? p }
            floorSqft = Self.area(floorOutline)
        }
    }

    /// A wall cut in two at `atFt` along it; doors and windows past the cut
    /// go on the second part. Returns the new wall.
    @discardableResult
    mutating func splitWall(_ id: UUID, atFt at: Double) -> Wall? {
        guard let i = walls.firstIndex(where: { $0.id == id }) else { return nil }
        let w = walls[i]
        guard at > 0.25, at < w.lengthFt - 0.25 else { return nil }
        let cut = point(on: w, along: at)
        var second = Wall(label: nextWallLabel, lengthFt: w.lengthFt - at, heightFt: w.heightFt, start: cut, end: w.end,
                          planned: w.planned, thicknessIn: w.thicknessIn)
        second.splitFrom = w.id
        second.splitAtFt = at
        walls[i].end = cut
        walls[i].lengthFt = at
        walls.insert(second, at: i + 1)
        for j in openings.indices where openings[j].wallID == id {
            if let a = openings[j].alongFt, a > at {
                openings[j].wallID = second.id
                openings[j].alongFt = a - at
            }
        }
        return second
    }
}

extension AreaTakeoff {
    /// This area's choices moved with walls edited on the model (`old` is
    /// the room before): split walls take their part of the tile and items,
    /// tile and items keep their places along walls whose start moved, and
    /// stay on walls that got shorter; a full-height piece stays full height.
    func following(old: ScannedRoom, new: ScannedRoom) -> AreaTakeoff {
        var t = self
        // Splits first, in the old wall's measure.
        for w in new.walls {
            guard let from = w.splitFrom, old.wall(from) != nil, old.wall(w.id) == nil else { continue }
            let at = w.splitAtFt
            var moved: [Piece] = []
            for i in t.pieces.indices where t.pieces[i].wallID == from {
                let p = t.pieces[i]
                if p.fromFt >= at - 1e-9 {
                    t.pieces[i].wallID = w.id
                    t.pieces[i].fromFt -= at
                    t.pieces[i].toFt -= at
                } else if p.toFt > at + 1e-9 {
                    t.pieces[i].toFt = at
                    var rest = p
                    rest.id = UUID()
                    rest.wallID = w.id
                    rest.fromFt = 0
                    rest.toFt = p.toFt - at
                    moved.append(rest)
                }
            }
            t.pieces += moved
            for i in t.items.indices where t.items[i].wallID == from && t.items[i].fromFt >= at - 1e-9 {
                t.items[i].wallID = w.id
                t.items[i].fromFt -= at
                t.items[i].toFt -= at
            }
        }
        // Walls whose start moved or that changed length.
        for w in new.walls {
            let before = old.wall(w.id) ?? (w.splitFrom.flatMap { old.wall($0) }.map { o -> ScannedRoom.Wall in
                var part = o; part.start = old.point(on: o, along: w.splitAtFt); part.lengthFt = o.lengthFt - w.splitAtFt; return part
            })
            guard let o = before else { continue }
            let l = max(hypot(o.end.x - o.start.x, o.end.y - o.start.y), 1e-9)
            let u = ScannedRoom.Point(x: (o.end.x - o.start.x) / l, y: (o.end.y - o.start.y) / l)
            let shift = (w.start.x - o.start.x) * u.x + (w.start.y - o.start.y) * u.y
            for i in t.pieces.indices where t.pieces[i].wallID == w.id {
                let full = abs(t.pieces[i].heightIn - (o.heightFt * 12).rounded(.down)) < 1
                t.pieces[i].fromFt = min(max(0, t.pieces[i].fromFt - shift), w.lengthFt)
                t.pieces[i].toFt = min(max(0, t.pieces[i].toFt - shift), w.lengthFt)
                if full { t.pieces[i].heightIn = (w.heightFt * 12).rounded(.down) }
            }
            for i in t.items.indices where t.items[i].wallID == w.id && !t.items[i].kind.isCorner {
                let width = t.items[i].widthFt
                let from = min(max(0, t.items[i].fromFt - shift), max(0, w.lengthFt - width))
                if t.items[i].kind.isBench {
                    t.items[i].fromFt = min(max(0, t.items[i].fromFt - shift), w.lengthFt)
                    t.items[i].toFt = min(max(0, t.items[i].toFt - shift), w.lengthFt)
                } else {
                    t.items[i].fromFt = from
                    t.items[i].toFt = from + width
                }
            }
        }
        t.pieces.removeAll { p in new.wall(p.wallID) == nil || p.toFt - p.fromFt < 1.0 / 24 }
        t.items.removeAll { new.wall($0.wallID) == nil }
        return t
    }
}


// MARK: - Typed distances between walls

extension ScannedRoom {
    /// The nearest wall running the same way on each side of a wall, and how
    /// far apart they are (square to them, in feet; `offset` is signed, along
    /// the wall's left-hand normal).
    func parallelNeighbors(of id: UUID) -> [(wall: Wall, offset: Double)] {
        guard let w = wall(id), w.lengthFt > 0 else { return [] }
        let u = Point(x: (w.end.x - w.start.x) / w.lengthFt, y: (w.end.y - w.start.y) / w.lengthFt)
        let n = Point(x: -u.y, y: u.x)
        var best: [Bool: (Wall, Double)] = [:]
        for o in walls where o.id != id && o.lengthFt > 0.25 {
            let ou = Point(x: (o.end.x - o.start.x) / o.lengthFt, y: (o.end.y - o.start.y) / o.lengthFt)
            guard abs(u.x * ou.x + u.y * ou.y) > 0.98 else { continue }
            let mid = Point(x: (o.start.x + o.end.x) / 2, y: (o.start.y + o.end.y) / 2)
            let off = (mid.x - w.start.x) * n.x + (mid.y - w.start.y) * n.y
            guard abs(off) > 0.1 else { continue }
            let side = off > 0
            if best[side].map({ abs(off) < abs($0.1) }) ?? true { best[side] = (o, off) }
        }
        return best.values.sorted { $0.1 < $1.1 }.map { (wall: $0.0, offset: $0.1) }
    }

    /// A wall slid square to itself so it's `feet` from `other` (a wall
    /// running the same way), on the side it's on now; the room stays joined.
    mutating func setDistance(of id: UUID, from other: UUID, to feet: Double) {
        guard let w = wall(id), w.lengthFt > 0,
              let off = parallelNeighbors(of: id).first(where: { $0.wall.id == other })?.offset else { return }
        let u = Point(x: (w.end.x - w.start.x) / w.lengthFt, y: (w.end.y - w.start.y) / w.lengthFt)
        let n = Point(x: -u.y, y: u.x)
        let delta = off - (off > 0 ? 1 : -1) * max(feet, 1.0 / 12)
        moveWall(id, by: .init(x: n.x * delta, y: n.y * delta))
    }
}
