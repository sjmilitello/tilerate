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
    func isKneeWall(_ w: Wall) -> Bool { w.planned && w.heightFt < ceilingFt - 0.5 / 12 }

    /// "Knee wall E", "New wall E" or "Wall A".
    func name(of w: Wall) -> String {
        isKneeWall(w) ? "Knee wall \(w.label)" : w.planned ? "New wall \(w.label)" : "Wall \(w.label)"
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
func snapped(_ ft: Double, to points: [Double], pull: Double = 0.25) -> Double {
    if let near = points.min(by: { abs($0 - ft) < abs($1 - ft) }), abs(near - ft) <= pull { return near }
    return (ft * 12).rounded() / 12
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
        return max(0, area)
    }

    func wallsSqft(in room: ScannedRoom) -> Double {
        // Tile on a wall that's since been deleted doesn't count.
        pieces.filter { room.wall($0.wallID) != nil }.reduce(0) { $0 + sqft(of: $1, in: room) }
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

    /// The tile height a new piece starts at for this kind of area.
    static func startingHeight(for area: Area?, wall: ScannedRoom.Wall) -> Double {
        let full = (wall.heightFt * 12).rounded(.down)
        switch area {
        case .backsplash: return min(18, full)
        case .tub: return min(84, full)
        default: return full
        }
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
            let lf = (stone.reduce(0) { $0 + $1.lengthFt } * 100).rounded() / 100
            // Caps and headers share a price; the line says which it has.
            let headers = stone.contains { $0.key.hasPrefix("header:") }
            let caps = stone.contains { !$0.key.hasPrefix("header:") }
            let name = kind != .cap ? kind.stoneLine
                : headers && caps ? "Stone wall cap & header" : headers ? "Stone header" : kind.stoneLine
            if lf > 0 {
                if let i = section.additionsLabor.firstIndex(where: { $0.id == id }) {
                    section.additionsLabor[i].qty = lf
                    // Renamed only while it still has a name the app gave it.
                    if TrimKind.capLineNames.contains(section.additionsLabor[i].activity) {
                        section.additionsLabor[i].activity = name
                    }
                } else {
                    section.additionsLabor.append(AdditionItem(id: id, activity: name, qty: lf,
                                                               rate: prices.rate(kind), unit: "lin ft"))
                }
            } else {
                section.additionsLabor.removeAll { $0.id == id }
            }
        }
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
            let existing = section.walls.first { $0.name == name }
            named.append(TiledWall(id: existing?.id ?? UUID(), name: name, sqft: sq, tile: existing?.tile ?? fallback))
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

/// 7.5 → "7′ 6″"
func feetAndInches(_ feet: Double) -> String {
    let totalIn = Int((feet * 12).rounded())
    let ft = totalIn / 12, inch = totalIn % 12
    if ft == 0 { return "\(inch)″" }
    return inch == 0 ? "\(ft)′" : "\(ft)′ \(inch)″"
}

// MARK: - Curbs, wall caps and jambs

/// What frames a shower or a knee wall: tile by default (part of the wall
/// square feet), or stone, charged per linear foot on its own line.
enum TrimKind: String, CaseIterable {
    case curb, cap, jamb
    var salt: Int { switch self { case .curb: 1; case .cap: 2; case .jamb: 3 } }
    var stoneLine: String {
        switch self {
        case .curb: "Stone curb"
        case .cap: "Stone wall cap"
        case .jamb: "Stone jambs"
        }
    }
    /// Names the app gives the cap line (headers are priced as caps).
    static let capLineNames: Set<String> = ["Stone wall cap", "Stone header", "Stone wall cap & header"]
}

/// Stone prices per linear foot and the curb height, from Admin.
struct StonePrices {
    var curb: Double = 0
    var cap: Double = 0
    var jamb: Double = 0
    var curbHeightIn: Double = 4
    /// A new shower door opening's width and height (inches).
    var doorWidthIn: Double = 30
    var doorHeightIn: Double = 80
    func rate(_ k: TrimKind) -> Double {
        switch k { case .curb: curb; case .cap: cap; case .jamb: jamb }
    }
}

extension StonePrices {
    init(rates r: Rates) {
        self.init(curb: r.stoneCurbPerLinFt, cap: r.stoneCapPerLinFt, jamb: r.stoneJambPerLinFt, curbHeightIn: r.curbHeightIn,
                  doorWidthIn: r.showerDoorWidthIn, doorHeightIn: r.showerDoorHeightIn)
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
            for w in kneeWalls { out.append(("cap:\(w.id)", .cap, "Wall cap (knee wall \(w.label))", w.lengthFt)) }
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
                out.append(("cap:\(w.id)", .cap, "Wall cap (knee wall \(w.label))", w.lengthFt))
                for start in [true, false] where room.isFreeEnd(of: w, start: start) {
                    out.append(("jamb:\(w.id):\(start ? "start" : "end")", .jamb, "Knee wall \(w.label) end jamb", w.heightFt))
                }
            }
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
