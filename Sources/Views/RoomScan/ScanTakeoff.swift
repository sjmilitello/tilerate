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
        for o in room.openings where o.wallID == piece.wallID && subtracted.contains(o.id) {
            let s = room.span(of: o)
            let width = max(0, min(s.upperBound, piece.toFt) - max(s.lowerBound, piece.fromFt))
            let tall = max(0, min(o.bottomFt + o.heightFt, height) - max(o.bottomFt, 0))
            area -= width * tall
        }
        return max(0, area)
    }

    func wallsSqft(in room: ScannedRoom) -> Double {
        pieces.reduce(0) { $0 + sqft(of: $1, in: room) }
    }

    func floorSqft(in room: ScannedRoom) -> Double {
        switch floor {
        case .room:
            return max(0, room.floorSqft - (excludeTub ? room.tubSqft : 0) - excludeSqft)
        case .size:
            return floorWidthFt * floorDepthFt
        case .none:
            return 0
        }
    }

    /// A tiled ceiling: the floor's size when one is set, otherwise the room's.
    func ceilingSqft(in room: ScannedRoom) -> Double {
        guard tileCeiling else { return 0 }
        if floorWidthFt > 0, floorDepthFt > 0 { return floorWidthFt * floorDepthFt }
        return room.floorSqft
    }

    /// Openings that fall in one of this area's pieces: the ones to ask about.
    func openingsInPieces(of room: ScannedRoom) -> [ScannedRoom.Opening] {
        room.openings.filter { o in
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
            t.floor = .size
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
    mutating func addPiece(on wall: ScannedRoom.Wall, area: Area?, others: [Piece]) -> Piece? {
        let taken = (pieces + others).filter { $0.wallID == wall.id }.map { $0.fromFt...$0.toFt }.sorted { $0.lowerBound < $1.lowerBound }
        var gaps: [ClosedRange<Double>] = []
        var cursor = 0.0
        for r in taken {
            if r.lowerBound - cursor > 0.25 { gaps.append(cursor...r.lowerBound) }
            cursor = max(cursor, r.upperBound)
        }
        if wall.lengthFt - cursor > 0.25 { gaps.append(cursor...wall.lengthFt) }
        guard let gap = gaps.max(by: { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }) else { return nil }
        let piece = Piece(wallID: wall.id, fromFt: gap.lowerBound, toFt: gap.upperBound,
                          heightIn: Self.startingHeight(for: area, wall: wall))
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

    /// Puts the takeoff's square feet into the area.
    func apply(_ room: ScannedRoom, to section: inout EstimateSection) {
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
            let name = "Wall \(wall.label)"
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
