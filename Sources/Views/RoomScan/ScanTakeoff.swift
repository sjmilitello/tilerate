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

    /// Every wall to the ceiling at one height (owner asked 2026-10-12: a
    /// scan gave one wall 99 1/2″ and the rest 86 13/16″): the scanned walls
    /// and the full walls drawn in; half walls keep theirs. Doors, windows
    /// and openings are kept inside their walls.
    mutating func setEveryWallHeight(_ ft: Double) {
        let half = Set(walls.filter { isKneeWall($0) }.map(\.id))
        for i in walls.indices where !half.contains(walls[i].id) { walls[i].heightFt = ft }
        for i in openings.indices {
            guard let id = openings[i].wallID, let w = wall(id) else { continue }
            openings[i].bottomFt = min(openings[i].bottomFt, max(0, w.heightFt - 1.0 / 6))
            openings[i].heightFt = min(openings[i].heightFt, w.heightFt - openings[i].bottomFt)
        }
    }

    /// Whether any wall to the ceiling differs from this height.
    func wallsDiffer(from ft: Double) -> Bool {
        walls.contains { !isKneeWall($0) && abs($0.heightFt - ft) > 1.0 / 192 }
    }

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

    /// Letters every wall A, B, C… in the order you'd meet them going
    /// clockwise round the room on the plan (owner's call, 2026-10-09): from
    /// the top wall, along each outside wall, and straight after it the walls
    /// that run into it (in order along it), each followed by any running on
    /// from that one — so a closet's walls follow the wall they stand on.
    /// Walls not reached that way go last, clockwise round the room. Returns
    /// each wall's old name → new name, for areas that named walls by letter.
    /// Never turns a wall round: only its letter changes.
    @discardableResult
    mutating func reletter() -> [String: String] {
        let order = wallsInMeetingOrder()
        var before: [UUID: String] = [:]
        for w in walls { before[w.id] = name(of: w) }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for (n, id) in order.enumerated() {
            if let i = walls.firstIndex(where: { $0.id == id }) {
                walls[i].label = n < letters.count ? String(letters[n]) : "\(n + 1)"
            }
        }
        lettering = Self.letteringVersion
        var renames: [String: String] = [:]
        for w in walls {
            guard let old = before[w.id] else { continue }
            renames[old] = name(of: w)
            if w.planned { renames["Knee wall \(old.split(separator: " ").last ?? "")"] = name(of: w) }
        }
        return renames.filter { $0.key != $0.value }
    }

    /// A scan saved before brought up to date (`lettering`): walls cut into
    /// sections at dividers, then lettered in the order you meet them.
    /// Returns each old wall name → its new names: one, or one per section
    /// in order along it ("Knee wall X" names too, from before half walls).
    mutating func upgradeLettering() -> [String: [String]] {
        let before = self
        sectionAtDividers()
        reletter()
        var out: [String: [String]] = [:]
        for w in before.walls {
            let now = sections(of: w.id).map { name(of: $0) }
            let old = before.name(of: w)
            if now != [old] { out[old] = now }
            if w.planned, let first = now.first { out["Knee wall \(w.label)"] = [first] }
        }
        return out
    }

    /// The walls' ids in lettering order (`reletter`).
    func wallsInMeetingOrder() -> [UUID] {
        guard !walls.isEmpty else { return [] }
        // As on screen: turned square (`squaringAngle`), y down, so clockwise
        // is the way atan2 grows.
        let a = -squaringAngle, cosA = cos(a), sinA = sin(a)
        func turned(_ p: Point) -> SIMD2<Double> { SIMD2(p.x * cosA - p.y * sinA, p.x * sinA + p.y * cosA) }
        let ends = Dictionary(uniqueKeysWithValues: walls.map { ($0.id, (turned($0.start), turned($0.end))) })
        let joined = 0.5
        func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
        var order: [UUID] = []
        var done = Set<UUID>()

        // The outside walls: from the top wall, left to right, then at each
        // corner the wall turning furthest out (leftmost, walking clockwise).
        let flat = walls.filter { w in
            let (p, q) = ends[w.id]!
            return !w.planned && abs(q.x - p.x) >= abs(q.y - p.y)
        }
        let top = flat.min { l, r in
            let ly = (ends[l.id]!.0.y + ends[l.id]!.1.y) / 2, ry = (ends[r.id]!.0.y + ends[r.id]!.1.y) / 2
            if abs(ly - ry) > joined { return ly < ry }
            return min(ends[l.id]!.0.x, ends[l.id]!.1.x) < min(ends[r.id]!.0.x, ends[r.id]!.1.x)
        } ?? walls[0]
        var outside: [(id: UUID, from: SIMD2<Double>, to: SIMD2<Double>)] = []
        var (from, to) = ends[top.id]!
        if from.x > to.x { swap(&from, &to) }
        outside.append((top.id, from, to)); done.insert(top.id)
        while length(to - outside[0].from) >= joined {
            let dir = to - from
            var best: (id: UUID, from: SIMD2<Double>, to: SIMD2<Double>, turn: Double)?
            for w in walls where !done.contains(w.id) && !w.planned {
                let (p, q) = ends[w.id]!
                for (near, far) in [(p, q), (q, p)] where length(near - to) < joined {
                    let d = far - near
                    var turn = atan2(dir.x * d.y - dir.y * d.x, dir.x * d.x + dir.y * d.y)
                    if turn < -.pi + 0.01 { turn = .pi }  // straight back is never the way round
                    if turn < (best?.turn ?? .infinity) { best = (w.id, near, far, turn) }
                }
            }
            if best == nil {
                // A gap (an opening with no wall): the nearest outside wall end within 8′.
                var gap = 8.0
                for w in walls where !done.contains(w.id) && !w.planned && !PlanDimensions.isPartition(w, in: self) {
                    let (p, q) = ends[w.id]!
                    for (near, far) in [(p, q), (q, p)] where length(near - to) < gap {
                        gap = length(near - to); best = (w.id, near, far, 0)
                    }
                }
            }
            guard let next = best else { break }
            outside.append((next.id, next.from, next.to)); done.insert(next.id)
            from = next.from; to = next.to
        }

        // How far along a wall (walked from → to) a point lies, when it's on it.
        func along(_ p: SIMD2<Double>, _ from: SIMD2<Double>, _ to: SIMD2<Double>) -> Double? {
            let d = to - from, len = length(d)
            guard len > 0.01 else { return nil }
            let u = d / len, v = p - from
            let t = u.x * v.x + u.y * v.y
            let off = abs(u.x * v.y - u.y * v.x)
            return off < 0.35 && t > -joined && t < len + joined ? t : nil
        }
        // A wall, then those running into it, each followed by its own.
        func visit(_ id: UUID, from: SIMD2<Double>, to: SIMD2<Double>) {
            order.append(id); done.insert(id)
            var into: [(t: Double, id: UUID, from: SIMD2<Double>, to: SIMD2<Double>)] = []
            for w in walls where !done.contains(w.id) {
                let (p, q) = ends[w.id]!
                let tp = along(p, from, to), tq = along(q, from, to)
                if let t = tp, tq == nil || t <= tq! { into.append((t, w.id, p, q)) }
                else if let t = tq { into.append((t, w.id, q, p)) }
            }
            for w in into.sorted(by: { $0.t < $1.t }) where !done.contains(w.id) {
                visit(w.id, from: w.from, to: w.to)
            }
        }
        let outsideIDs = Set(outside.map(\.id))
        done = outsideIDs
        for w in outside {
            done.remove(w.id)
            visit(w.id, from: w.from, to: w.to)
        }

        // Anything left (standing on its own): clockwise round the room.
        let rest = walls.filter { !done.contains($0.id) }
        let mids = walls.map { (ends[$0.id]!.0 + ends[$0.id]!.1) / 2 }
        let c = mids.reduce(SIMD2<Double>(0, 0), +) / Double(mids.count)
        order += rest.sorted { l, r in
            let a = (ends[l.id]!.0 + ends[l.id]!.1) / 2 - c, b = (ends[r.id]!.0 + ends[r.id]!.1) / 2 - c
            return atan2(a.y, a.x) < atan2(b.y, b.x)
        }.map(\.id)
        return order
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
    /// with the room, its length to the sixteenth, and onto a wall within
    /// 1½″ (`Steering`) — drawing a new wall and dragging an end alike.
    func plannedEnd(from a: Point, toward b: Point, except: UUID? = nil,
                    step: Double = Steering.stepFt, reach: Double = Steering.catchFt) -> Point {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.01 else { return b }
        // Nearest of the room's four square directions.
        let base = squaringAngle
        let raw = atan2(dy, dx)
        let quarter = Double.pi / 2
        let a0 = base + ((raw - base) / quarter).rounded() * quarter
        let per = (1 / step).rounded()          // 12 or 192 to the foot, exactly
        var len = (length * per).rounded() / per
        // Stop on a wall it nearly reaches.
        let dir = Point(x: cos(a0), y: sin(a0))
        for w in walls where w.id != except {
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = dir.x * ey - dir.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - a.x) * ey - (w.start.y - a.y) * ex) / den
            let s = ((w.start.x - a.x) * dir.y - (w.start.y - a.y) * dir.x) / den
            if t > 0.5, s >= -0.05, s <= 1.05, abs(t - len) < reach { len = t }
        }
        return Point(x: a.x + dir.x * len, y: a.y + dir.y * len)
    }

    /// An existing wall's end dragged to lengthen or shorten it (owner,
    /// 2026-10-08: no jumps): along the wall's own line — never squared up,
    /// so a scanned wall a hair off square doesn't jump sideways — by how far
    /// `target` is along it, to the sixteenth; catching within `reach` only on
    /// a wall it runs into, never on the walls attached at that end (they
    /// move with it) or anything in line with them.
    func lengthenedEnd(of id: UUID, start: Bool, toward target: Point, from base: Wall,
                       reach: Double = Steering.catchFt) -> Point {
        let other = start ? base.end : base.start, end = start ? base.start : base.end
        let l = max(hypot(end.x - other.x, end.y - other.y), 1e-9)
        let dir = Point(x: (end.x - other.x) / l, y: (end.y - other.y) / l)
        var len = Steering.sixteenth((target.x - other.x) * dir.x + (target.y - other.y) * dir.y)
        len = max(len, 0.5)
        // The walls at this end as it is now, and their pieces across a doorway.
        let now = wall(id).map { start ? $0.start : $0.end } ?? end
        var attached = Set<UUID>([id])
        for w in walls where hypot(w.start.x - now.x, w.start.y - now.y) < 0.35 || hypot(w.end.x - now.x, w.end.y - now.y) < 0.35 {
            attached.insert(w.id)
            for piece in inLine(with: w.id) { attached.insert(piece.id) }
        }
        var best = reach
        let raw = len
        for w in walls where !attached.contains(w.id) {
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = dir.x * ey - dir.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - other.x) * ey - (w.start.y - other.y) * ex) / den
            let s = ((w.start.x - other.x) * dir.y - (w.start.y - other.y) * dir.x) / den
            if t > 0.5, s >= -0.05, s <= 1.05, abs(t - raw) < best { best = abs(t - raw); len = t }
        }
        return Point(x: other.x + dir.x * len, y: other.y + dir.y * len)
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
    /// the sixteenth; across, its line snaps within 1½″ to `guides` (e.g. the
    /// shower floor's corners) and other walls' ends; along, an end snaps
    /// onto a wall within 1½″.
    mutating func movePlannedWall(_ original: Wall, by d: Point, guides: [Point] = [], reach: Double = Steering.catchFt) {
        guard let i = walls.firstIndex(where: { $0.id == original.id }), walls[i].planned else { return }
        let dx = original.end.x - original.start.x, dy = original.end.y - original.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let u = Point(x: dx / l, y: dy / l), n = Point(x: -u.y, y: u.x)
        var along = ((d.x * u.x + d.y * u.y) * 192).rounded() / 192
        var across = ((d.x * n.x + d.y * n.y) * 192).rounded() / 192
        // Across: line up with a guide or another wall's end.
        let raw = d.x * n.x + d.y * n.y
        var best = reach
        for p in guides + walls.filter({ $0.id != original.id }).flatMap({ [$0.start, $0.end] }) {
            let c = (p.x - original.start.x) * n.x + (p.y - original.start.y) * n.y
            if abs(c - raw) < best { best = abs(c - raw); across = c }
        }
        // Along: an end onto a wall it nearly touches.
        let rawAlong = d.x * u.x + d.y * u.y
        let base = Point(x: original.start.x + n.x * across, y: original.start.y + n.y * across)
        best = reach
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
        return faceName(of: wall, looking: n) ?? (face == 0 ? "Side 1" : "Side 2")
    }

    /// A scanned wall with the room on both sides (a partition): it can be
    /// tiled on either side or both, like a wall drawn in (owner, 2026-10-09).
    func isDivider(_ w: Wall) -> Bool { !w.planned && PlanDimensions.isPartition(w, in: self) }

    /// The room's middle: its floor outline's, else its walls'.
    var middle: Point {
        let pts = floorOutline.isEmpty ? walls.flatMap { [$0.start, $0.end] } : floorOutline
        return .init(x: pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1)), y: pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1)))
    }

    /// The unit vector square to a wall on one of its sides. A wall drawn in:
    /// face 0 is its left-hand side. A scanned wall: face 0 is the side
    /// toward `target` (an area's floor, else the room's middle) and face 1,
    /// on a divider, the far side.
    func sideNormal(of w: Wall, face: Int, toward target: Point) -> Point {
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        var n = Point(x: -dy / l, y: dx / l)
        if !w.planned {
            let mid = Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
            if (target.x - mid.x) * n.x + (target.y - mid.y) * n.y < 0 { n = Point(x: -n.x, y: -n.y) }
        }
        return face == 1 ? Point(x: -n.x, y: -n.y) : n
    }

    /// "Side facing wall C": the wall a side of `wall` looks toward (`n`,
    /// a unit vector square to it), or nil when it faces none.
    func faceName(of wall: Wall, looking n: Point) -> String? {
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
        return best.map { "Side facing wall \($0.0)" }
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

/// Rounds to the sixteenth, or to a snap point within 1½″ (`Steering`).
func snapped(_ ft: Double, to points: [Double], pull: Double = Steering.catchFt, step: Double = Steering.stepFt) -> Double {
    if let near = points.min(by: { abs($0 - ft) < abs($1 - ft) }), abs(near - ft) <= pull { return near }
    let per = (1 / step).rounded()
    return (ft * per).rounded() / per
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
            + soffitTileSqft(in: room)
    }

    func floorSqft(in room: ScannedRoom) -> Double {
        switch floor {
        case .room:
            // The floor's outline less the other areas' floors (with their
            // curbs), the "no tile" boxes and the tub, each only where it's
            // inside the outline (owner, 2026-10-12).
            let outline = tiledOutline(in: room)
            var sq = FloorGeometry.area(outline)
            for c in cutouts + skipBoxes.map(\.corners) { sq -= FloorGeometry.area(FloorGeometry.clip(outline, to: c)) }
            if excludeTub, room.tubOutline.count > 2 { sq -= FloorGeometry.area(FloorGeometry.clip(outline, to: room.tubOutline)) }
            return max(0, sq - excludeSqft)
        case .size:
            return floorWidthFt * floorDepthFt
        case .drawn:
            return floorRect.map { $0.widthFt * $0.depthFt } ?? 0
        case .none:
            return 0
        }
    }

    /// The outline a Floor area tiles: its own when its edges were dragged, else the scan's.
    func tiledOutline(in room: ScannedRoom) -> [ScannedRoom.Point] {
        if let o = floorOutline, o.count > 2 { return o }
        return room.floorOutline
    }

    /// What this area puts on the floor that a Floor area mustn't tile: a
    /// drawn shower floor, and its curb's strip just outside it.
    func floorFootprints(in room: ScannedRoom, curbWidthFt: Double = 4.5 / 12) -> [[ScannedRoom.Point]] {
        guard floor == .drawn, let r = floorRect else { return [] }
        var out = [r.corners]
        let mid = r.center
        for (a, b) in curbEdges(in: room) {
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
            var n = ScannedRoom.Point(x: -(b.y - a.y) / len, y: (b.x - a.x) / len)
            if ((a.x + b.x) / 2 - mid.x) * n.x + ((a.y + b.y) / 2 - mid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
            out.append([a, b, .init(x: b.x + n.x * curbWidthFt, y: b.y + n.y * curbWidthFt),
                        .init(x: a.x + n.x * curbWidthFt, y: a.y + n.y * curbWidthFt)])
        }
        return out
    }

    /// Cabinets the scanner found become "no tile" boxes, the first time.
    mutating func addScannedSkips(from room: ScannedRoom) {
        guard !scannedSkipsAdded else { return }
        scannedSkipsAdded = true
        for f in room.fixtures where f.kind == "Cabinet" && f.outline.count == 4 {
            let p = f.outline
            let w = hypot(p[1].x - p[0].x, p[1].y - p[0].y), d = hypot(p[3].x - p[0].x, p[3].y - p[0].y)
            guard w > 0.1, d > 0.1 else { continue }
            skipBoxes.append(FloorRect(origin: p[0], u: .init(x: (p[1].x - p[0].x) / w, y: (p[1].y - p[0].y) / w),
                                       v: .init(x: (p[3].x - p[0].x) / d, y: (p[3].y - p[0].y) / d), widthFt: w, depthFt: d))
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
                t.floorWidthFt = (max(w, d) * 192).rounded() / 192
                t.floorDepthFt = (min(w, d) * 192).rounded() / 192
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
        // Stone went on a line per kind before it was grouped: those go.
        for kind in TrimKind.allCases {
            let id = Self.stoneLineID(section.id, kind)
            section.additionsLabor.removeAll { $0.id == id }
        }
        // One line per group (owner, 2026-10-13), each part at its own install
        // price, with the stone material in it unless it's listed apart.
        var materialSqft = 0.0
        for group in StoneGroup.allCases {
            let id = Self.stoneLineID(section.id, group)
            let stone = pieces.filter { $0.part.group == group && $0.stone && $0.lengthFt > 0 }
            var total = 0.0
            // A panel (a niche's back) by its own area; the rest by length,
            // or by length × the usual width.
            func bySqft(_ p: TrimPiece) -> Bool { p.areaSqft != nil ? prices.rate(p.part).bySqft : prices.rate(p.part).usesSqft }
            func sqftOf(_ p: TrimPiece) -> Double {
                let r = prices.rate(p.part)
                return p.areaSqft ?? (r.widthIn > 0 ? p.lengthFt * r.widthIn / 12 : 0)
            }
            for p in stone {
                let rate = prices.rate(p.part)
                total += bySqft(p) ? sqftOf(p) * rate.perSqft : p.lengthFt * rate.perLinFt
                let sqft = sqftOf(p)
                materialSqft += sqft
                if !prices.materialSeparate { total += sqft * prices.materialPerSqft }
            }
            total = (total * 100).rounded() / 100
            guard !stone.isEmpty, total > 0 || stone.contains(where: { $0.lengthFt > 0 }) else {
                section.additionsLabor.removeAll { $0.id == id }
                continue
            }
            // One price throughout: length (or square feet) at that price;
            // else the group's total as one.
            let rates = Set(stone.map { prices.rate($0.part) })
            let modes = Set(stone.map(bySqft)), panels = Set(stone.map { $0.areaSqft != nil })
            let qty: Double, rate: Double, unit: String
            if rates.count == 1, modes.count == 1, panels.count == 1 || modes.first == true, let r = rates.first {
                let feet = stone.reduce(0) { $0 + $1.lengthFt }
                let material = prices.materialSeparate ? 0 : prices.materialPerSqft
                if modes.first == true {
                    qty = (stone.reduce(0) { $0 + sqftOf($1) } * 100).rounded() / 100
                    rate = r.perSqft + material
                    unit = "sq ft"
                } else {
                    qty = (feet * 100).rounded() / 100
                    rate = r.perLinFt + material * r.widthIn / 12
                    unit = "lin ft"
                }
            } else {
                qty = 1
                rate = total
                unit = ""
            }
            if let i = section.additionsLabor.firstIndex(where: { $0.id == id }) {
                section.additionsLabor[i].qty = qty
                // A price changed on the estimate stays while the line's unit does.
                if section.additionsLabor[i].unit != unit || unit.isEmpty {
                    section.additionsLabor[i].unit = unit
                    section.additionsLabor[i].rate = rate
                }
            } else {
                section.additionsLabor.append(AdditionItem(id: id, activity: group.line, qty: qty, rate: rate, unit: unit))
            }
        }
        // The stone material on its own line, when listed apart.
        let materialID = Self.stoneMaterialLineID(section.id)
        if prices.materialSeparate, prices.materialPerSqft > 0, materialSqft > 0 {
            let qty = (materialSqft * 100).rounded() / 100
            if let i = section.additionsMaterials.firstIndex(where: { $0.id == materialID }) {
                section.additionsMaterials[i].qty = qty
            } else {
                section.additionsMaterials.append(AdditionItem(id: materialID, activity: "Stone pieces", qty: qty,
                                                               rate: prices.materialPerSqft, taxable: true, unit: "sq ft"))
            }
        } else {
            section.additionsMaterials.removeAll { $0.id == materialID }
        }
        // What's placed on the walls sets the area's features (owner's call:
        // "Use these measurements" overrides typed counts).
        if itemsPlaced, section.area != .floor {
            section.features = placedFeatures(keeping: section.features)
        }
        // A curbless shower takes Curbless Shower, per sq ft of its floor; a
        // linear drain takes Linear Drain, per foot of drain (owner's calls,
        // 2026-10-08). Their lines keep fixed ids, so a price changed on the
        // estimate stays; they go when the curb or the linear drain does.
        let shower = section.area == .shower && floor == .drawn
        setPriceListLine(prices.curblessItem, id: Self.extraLineID(section.id, 1),
                         qty: shower && curbless ? section.measurements.showerFloorSqft : nil, in: &section)
        let linear = shower ? drainShown().flatMap { $0.kind == .linear ? $0.lengthFt : nil } : nil
        setPriceListLine(prices.linearDrainItem, id: Self.extraLineID(section.id, 2),
                         qty: linear.map { ($0 * 100).rounded() / 100 }, in: &section)
    }

    /// A line from a price list item with this id: added or its quantity
    /// updated when `qty` is set, removed when it's nil.
    private func setPriceListLine(_ item: PriceListItem?, id: UUID, qty: Double?, in section: inout EstimateSection) {
        guard let item, let qty, qty > 0 else {
            section.additionsLabor.removeAll { $0.id == id }
            section.additionsMaterials.removeAll { $0.id == id }
            return
        }
        if let i = section.additionsLabor.firstIndex(where: { $0.id == id }) {
            section.additionsLabor[i].qty = qty
        } else if let i = section.additionsMaterials.firstIndex(where: { $0.id == id }) {
            section.additionsMaterials[i].qty = qty
        } else {
            let perSqft = item.unit == .perSqft
            let line = AdditionItem(id: id, activity: item.name, qty: qty, rate: item.price,
                                    taxable: item.isMaterial && item.taxable, unit: item.unit.quantityLabel,
                                    followsAreaSqft: perSqft, measure: item.measure, minimum: item.minimum)
            if item.isMaterial { section.additionsMaterials.append(line) } else { section.additionsLabor.append(line) }
        }
    }

    /// A curbless or linear drain line's id, the same every time for an area.
    static func extraLineID(_ sectionID: UUID, _ salt: UInt8) -> UUID {
        var bytes = sectionID.uuid
        bytes.12 ^= 0xC3
        bytes.11 ^= salt
        return UUID(uuid: bytes)
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

    /// How deep a niche goes into the wall: a 2×4 stud cavity.
    static let nicheDepthIn = 3.5

    /// Square feet of tile inside a niche: the back, and the sides, top and
    /// sill where they aren't stone.
    func nicheTileSqft(_ n: Item) -> Double {
        let w = n.widthFt, h = n.heightIn / 12, d = Self.nicheDepthIn / 12
        var sqft = partStone(n, "back") ? 0 : w * h        // back
        if !partStone(n, "jambs") { sqft += 2 * d * h }   // sides
        if !partStone(n, "header") { sqft += w * d }      // top
        if !partStone(n, "shelf") { sqft += w * d }       // sill
        return (sqft * 100).rounded() / 100
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
                return SizedFeature(kind: .bench, label: "\(i.kind.name) \(inchText(i.widthFt))", linFt: i.widthFt)
            // Its minimum here; its stone parts on the stone lines (owner,
            // 2026-10-13: the minimum plus the stone).
            case .niche:
                return SizedFeature(kind: .niche, label: "Niche \(inches(i.widthFt * 12)) × \(inches(i.heightIn))",
                                    tile: i.tile, tileSqft: i.tile == nil ? 0 : nicheTileSqft(i))
            case .window:
                return SizedFeature(kind: .window, label: "Window \(inches(i.widthFt * 12)) × \(inches(i.heightIn))")
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

    /// After the shower floor changed (`old` is how it was): a framed bench
    /// whose end was out at the curb line — flush with the curb's outside —
    /// stays there, longer or shorter with the floor (owner, 2026-10-10).
    mutating func benchesFollowFloor(from old: FloorRect, in room: ScannedRoom, curbWidthFt: Double) {
        guard floor == .drawn, floorRect != nil else { return }
        var before = self
        before.floorRect = old
        for i in items.indices where items[i].kind == .framedBench {
            guard let w = room.wall(items[i].wallID),
                  let was = before.benchSpan(on: w, in: room, floating: false, curbWidthFt: curbWidthFt),
                  let now = benchSpan(on: w, in: room, floating: false, curbWidthFt: curbWidthFt) else { continue }
            if abs(items[i].toFt - was.upperBound) < 0.05 { items[i].toFt = now.upperBound }
            if abs(items[i].fromFt - was.lowerBound) < 0.05 { items[i].fromFt = now.lowerBound }
        }
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
    static func stoneLineID(_ sectionID: UUID, _ group: StoneGroup) -> UUID {
        var bytes = sectionID.uuid
        bytes.14 ^= 0x5A
        bytes.13 ^= UInt8(20 + (StoneGroup.allCases.firstIndex(of: group) ?? 0))
        return UUID(uuid: bytes)
    }

    static func stoneMaterialLineID(_ sectionID: UUID) -> UUID {
        var bytes = sectionID.uuid
        bytes.14 ^= 0x5A
        bytes.13 ^= 40
        return UUID(uuid: bytes)
    }

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

/// Every length shown, in inches to the sixteenth: 106 1/2″, 13 1/8″, 3/16″
/// (owner's call, 2026-10-08: inches for everything; see `Lengths`).
func inchText(_ feet: Double) -> String { Lengths.inchesText(feet: feet) }

// MARK: - Curbs, wall caps and jambs

/// What frames a shower or a knee wall: tile by default (part of the wall
/// square feet), or stone, charged per linear foot on its own line.
enum TrimKind: String, CaseIterable {
    case curb, cap, jamb, benchTop, benchFront, niche, window
    /// Ids of the lines stone went on before it was grouped (2026-10-13),
    /// so they're taken off when measured again.
    var salt: Int {
        switch self { case .curb: 1; case .cap: 2; case .jamb: 3; case .benchTop: 4; case .benchFront: 5; case .niche: 6; case .window: 7 }
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
    /// Each part's install price (owner, 2026-10-13), and the stone material.
    var parts: [StonePart: StoneRate] = [:]
    var materialPerSqft: Double = 0
    var materialSeparate: Bool = false
    var defaults = ScanItemDefaults()
    /// The price list's Curbless Shower and Linear Drain, nil once deleted there.
    var curblessItem: PriceListItem? = PriceListItem.curblessShower
    var linearDrainItem: PriceListItem? = PriceListItem.linearDrain
    /// The curb's width on the plan: always 4½″ (owner's call, 2026-10-08).
    /// Admin's stone curb width is the stone on top, which overhangs the
    /// curb, so it doesn't say where the shower floor stops.
    var curbWidthFt: Double { 4.5 / 12 }
    func rate(_ p: StonePart) -> StoneRate {
        if let r = parts[p] { return r }
        switch p.legacy {
        case .curb: return stone[.curb] ?? StoneRate(perLinFt: curb)
        case .cap: return stone[.cap] ?? StoneRate(perLinFt: cap)
        case .jamb: return stone[.jamb] ?? StoneRate(perLinFt: jamb)
        case let item: return stone[item] ?? StoneRate()
        }
    }
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

extension TrimKind {
    var item: StoneItem {
        switch self {
        case .curb: .curb
        case .cap: .cap
        case .jamb: .jamb
        case .benchTop: .benchTop
        case .benchFront: .benchFront
        case .niche: .niche
        case .window: .window
        }
    }
}

extension StonePrices {
    init(rates r: Rates) {
        self.init(curb: r.stoneCurbPerLinFt, cap: r.stoneCapPerLinFt, jamb: r.stoneJambPerLinFt, curbHeightIn: r.curbHeightIn,
                  doorWidthIn: r.showerDoorWidthIn, doorHeightIn: r.showerDoorHeightIn,
                  stone: Dictionary(uniqueKeysWithValues: StoneItem.allCases.map { ($0, r.stoneRate($0)) }),
                  parts: Dictionary(uniqueKeysWithValues: StonePart.allCases.map { ($0, r.stoneRate($0)) }),
                  materialPerSqft: r.stoneMaterialPerSqft, materialSeparate: r.stoneMaterialSeparate,
                  defaults: r.scanDefaults,
                  curblessItem: r.priceList.first { $0.id == PriceListItem.curblessShower.id },
                  linearDrainItem: r.priceList.first { $0.id == PriceListItem.linearDrain.id })
    }
}

/// One curb, wall cap or jamb, worked out from the plan, with the owner's
/// choice applied.
struct TrimPiece: Identifiable, Equatable {
    let key: String
    let kind: TrimKind
    /// A panel's own square feet (a niche's back), else nil.
    var areaSqft: Double? = nil
    /// Which priced part it is (owner, 2026-10-13).
    var part: StonePart = .curbTop
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
        // Curbless: no curbs, and the jambs start at the floor.
        let curb = curbless ? 0 : (self.curbHeightIn ?? curbHeightIn) / 12
        let ceiling = room.ceilingFt
        // The top of the tile: this area's tallest tile on full walls, else the ceiling.
        // A header dropped over the curb: the entry jambs stop at its underside.
        let top = min(pieces.filter { room.wall($0.wallID)?.planned == false }.map { $0.heightIn / 12 }.max() ?? ceiling,
                      entryHeaderBottom(in: room) ?? .infinity)
        let kneeWalls = room.walls.filter { w in room.isKneeWall(w) && pieces.contains { $0.wallID == w.id } }

        if area == .shower, floor == .drawn, let r = floorRect {
            let c = r.corners
            let sides = openSides(in: room)
            // The curb stops at a framed bench.
            let curbRun = curbSides(in: room)
            let width = curbRun.stretches.reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            if width > 0, !curbless {
                out.append(("curb", .curb, "Curb", width))
                // Its faces below the top: wall faces, priced as curb (owner).
                out.append(("curb:inside", .curb, "Curb inside face", width))
                out.append(("curb:outside", .curb, "Curb outside face", width))
            }
            // A framed bench the curb stops at shows its outside end at the entry.
            for b in curbRun.benches {
                out.append(("benchSide:\(b.id)", .benchFront, "\(b.kind.name) outside end", b.depthIn / 12))
            }
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
                        // The entry meets the half wall's face (a corner shower with a
                        // half wall on one curb): its free end, flush with the curb's
                        // outside, is a piece of its own, floor to cap, priced as a
                        // jamb (owner, 2026-10-13).
                        if Self.meetsFace(of: wall, corner: corner) {
                            for start in [true, false] where room.isFreeEnd(of: wall, start: start) {
                                let k = "kneeEnd:\(wall.id):\(start ? "start" : "end")"
                                guard !used.contains(k) else { continue }
                                used.insert(k)
                                out.append((k, .jamb, "Half wall \(wall.label) end", wall.heightFt))
                            }
                        }
                    } else if let bench = curbRun.benches.first(where: { $0.wallID == wall.id }) {
                        // A framed bench here is flush with the curb's outside:
                        // the jamb splits at its top (owner, 2026-10-09) — curb to
                        // bench top, and bench top to the top of the tile.
                        let benchTop = bench.heightIn / 12
                        out.append(("\(key):lower", .jamb, "\(name.capitalized) lower jamb", max(0, benchTop - curb)))
                        out.append(("\(key):upper", .jamb, "\(name.capitalized) upper jamb", max(0, top - benchTop)))
                    } else {
                        out.append((key, .jamb, "\(name.capitalized) jamb", max(0, top - curb)))
                    }
                }
            }
            for w in kneeWalls { out.append(("cap:\(w.id)", .cap, "Wall cap (half wall \(w.label))", w.lengthFt)) }
            // A header on the ceiling over the entry and over each half wall's
            // cap, framing the ceiling tile, so glass can later sit between it
            // and the curb or cap (owner, 2026-10-13). Tile means none; priced
            // like a door header.
            let dropped = Set(soffits.map(\.over))
            if width > 0, !dropped.contains("curb") { out.append(("header:ceiling", .cap, "Ceiling header (over the curb)", width)) }
            for w in kneeWalls where !dropped.contains("cap:\(w.id.uuidString)") {
                out.append(("header:ceiling:\(w.id)", .cap, "Ceiling header (over half wall \(w.label))", w.lengthFt))
            }
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
                var jambTop = header ? min(d.bottomFt + d.heightFt, wallTop) : wallTop
                if let sf = soffits.first(where: { $0.over == "door:\(d.id.uuidString)" }) { jambTop = min(jambTop, room.ceilingFt - sf.dropIn / 12) }
                if !curbless {
                    out.append(("curb:\(d.id)", .curb, "Curb (\(label))", width))
                    out.append(("curb:\(d.id):inside", .curb, "Curb inside face (\(label))", width))
                    out.append(("curb:\(d.id):outside", .curb, "Curb outside face (\(label))", width))
                }
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
        // Each dropped header's underside (owner, 2026-10-13).
        if area == .shower {
            for sf in soffits {
                let len = soffitLengthFt(sf, in: room)
                guard len > 0 else { continue }
                let name = soffitTargets(in: room).first { $0.over == sf.over }?.name.lowercased() ?? "the shower"
                out.append(("soffit:\(sf.id.uuidString)", .cap, "Header \(name)", len))
            }
        }
        // Each bench's top, and a framed bench's front.
        for b in items where b.kind.isBench {
            out.append(("benchTop:\(b.id)", .benchTop, "\(b.kind.name) top", b.widthFt))
            if b.kind == .framedBench { out.append(("benchFront:\(b.id)", .benchFront, "\(b.kind.name) front", b.widthFt)) }
        }
        // A niche's and a window's stone parts (owner, 2026-10-13): each part
        // chosen on its own, starting from the niche's or window's choice.
        var defaults: [String: Bool] = [:]
        for i in items where i.kind == .niche || i.kind == .window {
            let w = i.widthFt, h = i.heightIn / 12
            let label = "\(i.kind.name) \(Int((w * 12).rounded()))″ × \(Int(i.heightIn.rounded()))″"
            let parts: [(String, String, Double)] = i.kind == .niche
                ? [("back", "back", w), ("shelf", "base shelf", w), ("jambs", "jambs", 2 * h), ("header", "header", w),
                   ("dividers", "divider shelves", Double(i.dividers) * w)]
                : [("sill", "sill", w), ("jambs", "jambs", 2 * h), ("header", "header", w)]
            for (part, name, ft) in parts where ft > 0.01 {
                let key = Self.partKey(i, part)
                defaults[key] = partStone(i, part)
                out.append((key, i.kind == .niche ? .niche : .window, "\(label) \(name)", ft))
            }
        }
        let doorIDs = Set(showerDoors(in: room).map(\.id.uuidString))
        return out.map { key, kind, name, ft in
            let choice = trim.first { $0.key == key }
            let length = choice?.lengthFt ?? ft
            let item = items.first { key.contains($0.id.uuidString) }
            // A panel's own area: a niche's back, and a bench's top, front and
            // outside end at the bench's real size (owner, 2026-10-14).
            let area: Double? = item.flatMap { i -> Double? in
                if key.hasSuffix(":back") { return i.widthFt * i.heightIn / 12 }
                if key.hasPrefix("benchTop:") { return length * i.depthIn / 12 }
                if key.hasPrefix("benchFront:") { return length * i.heightIn / 12 }
                if key.hasPrefix("benchSide:") { return length * i.heightIn / 12 }
                return nil
            }
            return TrimPiece(key: key, kind: kind, areaSqft: area, part: Self.stonePart(key, kind: kind, doors: doorIDs, items: items),
                             name: name, measuredFt: ft,
                             lengthFt: choice?.lengthFt ?? ft, stone: choice?.stone ?? defaults[key] ?? false)
        }
    }

    /// A niche's or window's part ("shelf", "jambs", "header", "dividers";
    /// a window's "sill", "jambs", "header"): its key, and whether it's stone
    /// — chosen on its own, else as the niche's or window's old choice had it
    /// (stone all around: every part; shelves only: base shelf and dividers).
    static func partKey(_ i: Item, _ part: String) -> String { "\(i.kind.rawValue):\(i.id):\(part)" }

    func partStone(_ i: Item, _ part: String) -> Bool {
        if let c = trim.first(where: { $0.key == Self.partKey(i, part) }) { return c.stone }
        if i.kind == .window { return i.stone != .tile }
        if part == "back" { return false }
        return part == "shelf" || part == "dividers" ? i.stone != .tile : i.stone == .all
    }

    mutating func setPartStone(_ i: Item, _ part: String, _ on: Bool) {
        let key = Self.partKey(i, part)
        if let k = trim.firstIndex(where: { $0.key == key }) { trim[k].stone = on } else { trim.append(.init(key: key, stone: on)) }
    }

    /// Whether any part of a niche or window is stone.
    func anyStone(_ i: Item) -> Bool {
        (i.kind == .niche ? ["back", "shelf", "jambs", "header", "dividers"] : ["sill", "jambs", "header"]).contains { partStone(i, $0) }
    }

    /// Which priced part a stone piece is, from its key.
    static func stonePart(_ key: String, kind: TrimKind, doors: Set<String>, items: [Item]) -> StonePart {
        let parts = key.split(separator: ":").map(String.init)
        func item(_ id: String) -> Item? { items.first { $0.id.uuidString == id } }
        switch kind {
        case .curb:
            return key.hasSuffix(":inside") ? .curbInside : key.hasSuffix(":outside") ? .curbOutside : .curbTop
        case .cap:
            if key.hasPrefix("header:ceiling") || key.hasPrefix("soffit:") { return .ceilingHeader }
            if key.hasPrefix("header:") { return .doorHeader }
            return .wallCap
        case .jamb:
            return parts.count > 1 && doors.contains(parts[1]) ? .doorJamb : .wallJamb
        case .benchTop:
            return parts.count > 1 && item(parts[1])?.kind == .floatingBench ? .floatingBenchTop : .framedBenchTop
        case .benchFront:
            return key.hasPrefix("benchSide:") ? .framedBenchSide : .framedBenchFront
        case .niche:
            switch parts.last { case "back": return .nicheBack; case "jambs": return .nicheJamb; case "header": return .nicheHeader
                                case "dividers": return .nicheDivider; default: return .nicheShelf }
        case .window:
            switch parts.last { case "jambs": return .windowJamb; case "header": return .windowHeader; default: return .windowSill }
        }
    }

    /// Whether a stone piece of this area is stone (by its key).
    func isStone(_ key: String, in room: ScannedRoom, area: Area?, curbHeightIn: Double = 4) -> Bool {
        trimPieces(in: room, area: area, curbHeightIn: curbHeightIn).first { $0.key == key }?.stone ?? false
    }

    /// A stretch of the shower floor's edge with no wall along it: where
    /// the curb goes. Its ends' walls (nil for an open corner) get jambs.
    struct OpenSide {
        /// The point `t` feet along it from `a`.
        func point(_ t: Double) -> ScannedRoom.Point {
            let l = max(lengthFt, 1e-9)
            return .init(x: a.x + (b.x - a.x) * t / l, y: a.y + (b.y - a.y) * t / l)
        }
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
    /// shower door. None for a curbless shower.
    func curbEdges(in room: ScannedRoom) -> [(ScannedRoom.Point, ScannedRoom.Point)] {
        guard !curbless else { return [] }
        let doors: [(ScannedRoom.Point, ScannedRoom.Point)] = showerDoors(in: room).compactMap { d in
            guard let w = d.wallID.flatMap({ room.wall($0) }) else { return nil }
            let s = room.span(of: d)
            return (room.point(on: w, along: s.lowerBound), room.point(on: w, along: s.upperBound))
        }
        return doors + curbSides(in: room).stretches
    }

    /// Where a wall put on the curb of an open side goes (owner, 2026-10-13:
    /// "the wall should line up with it and extend to the end of the curb"):
    /// along the curb's middle, and on past a corner where another curb
    /// meets it, to the curb's outside corner. Its first face looks into the
    /// shower (the shower on its left). Curbless: on the floor's edge.
    func wallOnCurb(_ side: OpenSide, in room: ScannedRoom, curbWidthFt curb: Double) -> (ScannedRoom.Point, ScannedRoom.Point) {
        var a = side.a, b = side.b
        if let r = floorRect {
            let c = r.corners
            let center = ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
            let n = ScannedRoom.Point(x: -(b.y - a.y), y: b.x - a.x)
            if (center.x - a.x) * n.x + (center.y - a.y) * n.y < 0 { swap(&a, &b) }
        }
        guard curb > 0 else { return (a, b) }
        let l = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
        let u = ScannedRoom.Point(x: (b.x - a.x) / l, y: (b.y - a.y) / l)
        let out = ScannedRoom.Point(x: u.y, y: -u.x)
        let others = openSides(in: room).filter { o in
            !(hypot(o.a.x - side.a.x, o.a.y - side.a.y) < 1e-6 && hypot(o.b.x - side.b.x, o.b.y - side.b.y) < 1e-6)
        }
        func corner(_ p: ScannedRoom.Point) -> Bool {
            others.contains { o in
                let touches = hypot(o.a.x - p.x, o.a.y - p.y) < 0.05 || hypot(o.b.x - p.x, o.b.y - p.y) < 0.05
                let ol = max(o.lengthFt, 1e-9)
                return touches && abs(((o.b.x - o.a.x) * u.x + (o.b.y - o.a.y) * u.y) / ol) < 0.5
            }
        }
        let ea = corner(a) ? curb : 0, eb = corner(b) ? curb : 0
        return (.init(x: a.x - u.x * ea + out.x * curb / 2, y: a.y - u.y * ea + out.y * curb / 2),
                .init(x: b.x + u.x * eb + out.x * curb / 2, y: b.y + u.y * eb + out.y * curb / 2))
    }

    /// The curb as drawn (plan and 3-D): a door's curb and each stretch on
    /// the floor's open sides, keyed for its stone choice. Where two meet at
    /// a corner of the floor (a corner shower) one runs on past the corner
    /// by the curb's width, so they overlap there instead of meeting at the
    /// inside corner with a notch outside (owner, 2026-10-12). Drawing only:
    /// the curb's linear feet are unchanged.
    func curbRuns(in room: ScannedRoom, widthFt: Double) -> [(a: ScannedRoom.Point, b: ScannedRoom.Point, key: String)] {
        guard !curbless else { return [] }
        var runs: [(a: ScannedRoom.Point, b: ScannedRoom.Point, key: String)] = []
        for d in showerDoors(in: room) {
            guard let w = d.wallID.flatMap({ room.wall($0) }) else { continue }
            let s = room.span(of: d)
            runs.append((room.point(on: w, along: s.lowerBound), room.point(on: w, along: s.upperBound), "curb:\(d.id)"))
        }
        runs += curbSides(in: room).stretches.map { ($0.0, $0.1, "curb") }
        func near(_ p: ScannedRoom.Point, _ q: ScannedRoom.Point) -> Bool { hypot(p.x - q.x, p.y - q.y) < 0.05 }
        func dir(_ r: (a: ScannedRoom.Point, b: ScannedRoom.Point, key: String)) -> ScannedRoom.Point {
            let l = max(hypot(r.b.x - r.a.x, r.b.y - r.a.y), 1e-9)
            return .init(x: (r.b.x - r.a.x) / l, y: (r.b.y - r.a.y) / l)
        }
        for i in runs.indices {
            for j in runs.indices where j > i {
                let u = dir(runs[i]), v = dir(runs[j])
                guard abs(u.x * v.y - u.y * v.x) > 0.5 else { continue }   // not in line
                for atStart in [true, false] {
                    let p = atStart ? runs[i].a : runs[i].b
                    guard near(p, runs[j].a) || near(p, runs[j].b) else { continue }
                    let s: Double = atStart ? -1 : 1
                    let q = ScannedRoom.Point(x: p.x + u.x * s * widthFt, y: p.y + u.y * s * widthFt)
                    if atStart { runs[i].a = q } else { runs[i].b = q }
                }
            }
        }
        return runs
    }

    /// Where the curb actually runs: the floor's open sides less any part a
    /// framed bench stands on (owner, 2026-10-09: the curb stops at the
    /// bench), and the framed benches it stops at — their outside ends show
    /// at the entry.
    func curbSides(in room: ScannedRoom) -> (stretches: [(ScannedRoom.Point, ScannedRoom.Point)], benches: [Item]) {
        let sides = openSides(in: room)
        let benches = items.filter { $0.kind == .framedBench }
        var out: [(ScannedRoom.Point, ScannedRoom.Point)] = []
        var stopped = Set<UUID>()
        // A point on the floor's edge is under a bench when it's within the
        // bench's run along its wall and its depth out from the wall.
        func bench(at p: ScannedRoom.Point) -> Item? {
            benches.first { b in
                guard let w = room.wall(b.wallID), w.lengthFt > 0 else { return false }
                let ux = (w.end.x - w.start.x) / w.lengthFt, uy = (w.end.y - w.start.y) / w.lengthFt
                let n = inward(w, face: b.face, in: room)
                let along = (p.x - w.start.x) * ux + (p.y - w.start.y) * uy
                let out = (p.x - w.start.x) * n.x + (p.y - w.start.y) * n.y
                let skin = w.planned ? w.thicknessIn / 24 : 0
                return along > b.fromFt - 0.02 && along < b.toFt + 0.02 && out > -0.05 && out < skin + b.depthIn / 12 + 0.02
            }
        }
        for side in sides {
            let len = side.lengthFt
            let steps = max(1, Int((len * 64).rounded(.up)))
            var startT: Double? = nil
            for k in 0...steps {
                let t = len * Double(k) / Double(steps)
                let p = ScannedRoom.Point(x: side.a.x + (side.b.x - side.a.x) * t / len, y: side.a.y + (side.b.y - side.a.y) * t / len)
                if let b = bench(at: p) {
                    stopped.insert(b.id)
                    if let s0 = startT, t - s0 > 1.0 / 12 { out.append((side.point(s0), side.point(t))) }
                    startT = nil
                } else if startT == nil {
                    startT = t
                }
            }
            if let s0 = startT, len - s0 > 1.0 / 12 { out.append((side.point(s0), side.b)) }
        }
        return (out, benches.filter { stopped.contains($0.id) })
    }

    /// Where a header (soffit) runs, in plan: along the middle of what it's
    /// over — the curb, a half wall, or a doorway in its wall — and its width.
    func soffitLines(_ s: Soffit, in room: ScannedRoom, curbWidthFt: Double = 4.5 / 12)
        -> [(a: ScannedRoom.Point, b: ScannedRoom.Point, widthFt: Double)] {
        let parts = s.over.split(separator: ":").map(String.init)
        switch parts.first {
        case "curb":
            // Over every curb run (a corner shower's two meet at its outside corner).
            guard !curbless, let r = floorRect else { return [] }
            let c = r.corners
            let mid = ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
            return curbRuns(in: room, widthFt: curbWidthFt).filter { $0.key == "curb" }.map { run in
                let l = max(hypot(run.b.x - run.a.x, run.b.y - run.a.y), 1e-9)
                var n = ScannedRoom.Point(x: -(run.b.y - run.a.y) / l, y: (run.b.x - run.a.x) / l)
                let m = ScannedRoom.Point(x: (run.a.x + run.b.x) / 2, y: (run.a.y + run.b.y) / 2)
                if (m.x - mid.x) * n.x + (m.y - mid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
                let o = curbWidthFt / 2
                return (.init(x: run.a.x + n.x * o, y: run.a.y + n.y * o), .init(x: run.b.x + n.x * o, y: run.b.y + n.y * o), curbWidthFt)
            }
        case "cap":
            guard parts.count > 1, let w = room.walls.first(where: { $0.id.uuidString == parts[1] }) else { return [] }
            return [(w.start, w.end, Self.drawnThicknessFt(w))]
        case "door":
            guard parts.count > 1, let d = room.openings.first(where: { $0.id.uuidString == parts[1] }),
                  let w = d.wallID.flatMap({ room.wall($0) }) else { return [] }
            let sp = room.span(of: d)
            return [(room.point(on: w, along: sp.lowerBound), room.point(on: w, along: sp.upperBound), Self.drawnThicknessFt(w))]
        default:
            return []
        }
    }

    /// A header's total length over everything it's over.
    func soffitLengthFt(_ s: Soffit, in room: ScannedRoom) -> Double {
        soffitLines(s, in: room).reduce(0) { $0 + hypot($1.b.x - $1.a.x, $1.b.y - $1.a.y) }
    }

    /// What a header can go over in this area: the curb, each half wall,
    /// each doorway — with a name each, and whether one's already there.
    func soffitTargets(in room: ScannedRoom) -> [(over: String, name: String)] {
        var out: [(String, String)] = []
        if floor == .drawn, floorRect != nil, !curbless, !curbSides(in: room).stretches.isEmpty { out.append(("curb", "Over the curb")) }
        for w in room.walls where room.isKneeWall(w) && pieces.contains(where: { $0.wallID == w.id }) {
            out.append(("cap:\(w.id.uuidString)", "Over half wall \(w.label)"))
        }
        for d in showerDoors(in: room) {
            let wallName = d.wallID.flatMap { room.wall($0) }.map { room.name(of: $0) } ?? "wall"
            out.append(("door:\(d.id.uuidString)", "Over the door in \(wallName.prefix(1).lowercased() + wallName.dropFirst())"))
        }
        return out
    }

    /// Tile on headers: their faces, and their underside unless it's stone.
    func soffitTileSqft(in room: ScannedRoom) -> Double {
        soffits.reduce(0) { sum, s in
            let stone = isStoneChoice("soffit:\(s.id.uuidString)")
            return sum + soffitLines(s, in: room).reduce(0) { t, line in
                t + hypot(line.b.x - line.a.x, line.b.y - line.a.y) * (2 * s.dropIn / 12 + (stone ? 0 : line.widthFt))
            }
        }
    }

    /// Headers as drawn in 3-D: where each runs, its width, bottom and top,
    /// and its underside's stone key.
    struct SoffitBox: Equatable {
        var a: ScannedRoom.Point
        var b: ScannedRoom.Point
        var widthFt: Double
        var bottomFt: Double
        var topFt: Double
        var key: String
    }

    func soffitBoxes(in room: ScannedRoom, curbWidthFt: Double = 4.5 / 12) -> [SoffitBox] {
        soffits.flatMap { s in
            soffitLines(s, in: room, curbWidthFt: curbWidthFt).map { l in
                SoffitBox(a: l.a, b: l.b, widthFt: l.widthFt, bottomFt: room.ceilingFt - s.dropIn / 12,
                          topFt: room.ceilingFt, key: "soffit:\(s.id.uuidString)")
            }
        }
    }

    /// The owner's stone choice for a piece by key (no measuring).
    func isStoneChoice(_ key: String) -> Bool { trim.first { $0.key == key }?.stone ?? false }

    /// The lowest header bottom over the entry (the curb): the jambs stop there.
    func entryHeaderBottom(in room: ScannedRoom) -> Double? {
        soffits.filter { $0.over == "curb" }.map { room.ceilingFt - $0.dropIn / 12 }.min()
    }

    /// Whether the entry, at this corner, meets the wall's face rather than
    /// its end: the wall carries on past the corner (a half wall put on a
    /// corner shower's curb runs the curb's width past it), instead of ending
    /// there.
    static func meetsFace(of wall: ScannedRoom.Wall, corner p: ScannedRoom.Point) -> Bool {
        let l = max(wall.lengthFt, 1e-9)
        let ux = (wall.end.x - wall.start.x) / l, uy = (wall.end.y - wall.start.y) / l
        let along = (p.x - wall.start.x) * ux + (p.y - wall.start.y) * uy
        let reach = drawnThicknessFt(wall) / 2 + 0.05
        return along > reach && along < l - reach
    }

    /// How thick a wall is drawn: a wall drawn in as built; a scanned one as a
    /// drywalled 2×4 wall, 4½″ (owner, 2026-10-13: 3½″ framed, 4½″ with
    /// drywall both sides; a shower's curb snaps flush to the drywalled corner).
    static let scannedWallThicknessFt = 4.5 / 12
    static func drawnThicknessFt(_ w: ScannedRoom.Wall) -> Double { w.planned ? max(w.thicknessIn, 1) / 12 : scannedWallThicknessFt }

    /// Where each entry jamb (and half wall end) is, for drawing (owner,
    /// 2026-10-13): a rectangle standing on the plan — its middle, the way it
    /// faces, its width, and its bottom and top — keyed as `trimPieces` keys
    /// them.
    /// - Against a full wall (or a bench): the strip of wall face above the
    ///   end of the curb, as wide as the curb.
    /// - Against a half wall: the lower jamb on the half wall — its face
    ///   above the curb's end when the entry meets its face (a corner shower
    ///   with a half wall on one curb), else its end; the upper jamb on the
    ///   wall the half wall is attached to, above the cap, as wide as the
    ///   half wall; and, when the entry meets its face, its free end, floor to
    ///   cap.
    struct JambFace: Equatable {
        var key: String
        var center: ScannedRoom.Point
        var facing: ScannedRoom.Point
        var widthFt: Double
        var bottomFt: Double
        var topFt: Double
    }

    func jambFaces(in room: ScannedRoom, curbHeightIn: Double, curbWidthFt: Double = 4.5 / 12) -> [JambFace] {
        guard floor == .drawn, let r = floorRect else { return [] }
        let curb = curbless ? 0 : (self.curbHeightIn ?? curbHeightIn) / 12
        let top = min(pieces.filter { room.wall($0.wallID)?.planned == false }.map { $0.heightIn / 12 }.max() ?? room.ceilingFt,
                      entryHeaderBottom(in: room) ?? .infinity)
        let c = r.corners
        let center = ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        let curbRun = curbSides(in: room)
        var out: [JambFace] = []
        var used = Set<String>()
        func unit(_ w: ScannedRoom.Wall) -> ScannedRoom.Point {
            let l = max(w.lengthFt, 1e-9)
            return .init(x: (w.end.x - w.start.x) / l, y: (w.end.y - w.start.y) / l)
        }
        /// The strip of a wall's face from `p` running `n` for `width`,
        /// facing `into`, on the face of the wall (drawn as thick as it is).
        func faceStrip(_ wall: ScannedRoom.Wall, at p: ScannedRoom.Point, n: ScannedRoom.Point,
                       into: ScannedRoom.Point, width: Double) -> (ScannedRoom.Point, ScannedRoom.Point) {
            let u = unit(wall)
            var wn = ScannedRoom.Point(x: -u.y, y: u.x)
            if wn.x * into.x + wn.y * into.y < 0 { wn = .init(x: -wn.x, y: -wn.y) }
            let off = (p.x - wall.start.x) * wn.x + (p.y - wall.start.y) * wn.y
            let shift = max(0, Self.drawnThicknessFt(wall) / 2 - off)
            return (.init(x: p.x + n.x * width / 2 + wn.x * shift, y: p.y + n.y * width / 2 + wn.y * shift), wn)
        }
        for side in openSides(in: room) {
            let l = max(side.lengthFt, 1e-9)
            let u = ScannedRoom.Point(x: (side.b.x - side.a.x) / l, y: (side.b.y - side.a.y) / l)
            var n = ScannedRoom.Point(x: -u.y, y: u.x)
            let mid = ScannedRoom.Point(x: (side.a.x + side.b.x) / 2, y: (side.a.y + side.b.y) / 2)
            if (mid.x - center.x) * n.x + (mid.y - center.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
            for (corner, wall, into) in [(side.a, side.startWall, u), (side.b, side.endWall, ScannedRoom.Point(x: -u.x, y: -u.y))] {
                guard let wall else { continue }
                let name = sideName(corner, entry: (side.a, side.b), center: center)
                var key = "jamb:\(name)", k = 2
                while used.contains(key) { key = "jamb:\(name):\(k)"; k += 1 }
                used.insert(key)
                func add(_ key: String, _ s: (ScannedRoom.Point, ScannedRoom.Point), _ width: Double, _ lo: Double, _ hi: Double) {
                    guard hi - lo > 0.01 else { return }
                    out.append(JambFace(key: key, center: s.0, facing: s.1, widthFt: width, bottomFt: lo, topFt: hi))
                }
                if room.isKneeWall(wall) {
                    let t = Self.drawnThicknessFt(wall)
                    let wu = unit(wall)
                    let face = Self.meetsFace(of: wall, corner: corner)
                    // Lower: on its face above the curb's end, or its end.
                    if face {
                        add("\(key):lower", faceStrip(wall, at: corner, n: n, into: into, width: curbWidthFt), curbWidthFt, curb, wall.heightFt)
                    } else {
                        // Its end at the corner: the end face, looking out along it.
                        let atStart = hypot(corner.x - wall.start.x, corner.y - wall.start.y) < hypot(corner.x - wall.end.x, corner.y - wall.end.y)
                        let e = atStart ? wall.start : wall.end
                        let d = atStart ? ScannedRoom.Point(x: -wu.x, y: -wu.y) : wu
                        add("\(key):lower", (e, d), t, curb, wall.heightFt)
                    }
                    // Upper: on the wall it's attached to, above the cap.
                    for atStart in [true, false] where !room.isFreeEnd(of: wall, start: atStart) {
                        let q = atStart ? wall.start : wall.end
                        let d = atStart ? wu : ScannedRoom.Point(x: -wu.x, y: -wu.y)   // toward its other end
                        guard let back = room.walls.filter({ $0.id != wall.id && room.distanceToWall(q, $0) < 0.3 })
                                .min(by: { room.distanceToWall(q, $0) < room.distanceToWall(q, $1) }) else { continue }
                        let bu = unit(back)
                        var bn = ScannedRoom.Point(x: -bu.y, y: bu.x)
                        if bn.x * d.x + bn.y * d.y < 0 { bn = .init(x: -bn.x, y: -bn.y) }
                        let off = (q.x - back.start.x) * bn.x + (q.y - back.start.y) * bn.y
                        let shift = max(0, Self.drawnThicknessFt(back) / 2 - off)
                        add("\(key):upper", (.init(x: q.x + bn.x * shift, y: q.y + bn.y * shift), bn), t, wall.heightFt, top)
                        break
                    }
                    // Its free end, flush with the curb's outside.
                    if face {
                        for atStart in [true, false] where room.isFreeEnd(of: wall, start: atStart) {
                            let kk = "kneeEnd:\(wall.id):\(atStart ? "start" : "end")"
                            guard !used.contains(kk) else { continue }
                            used.insert(kk)
                            let e = atStart ? wall.start : wall.end
                            let d = atStart ? ScannedRoom.Point(x: -wu.x, y: -wu.y) : wu
                            add(kk, (e, d), t, 0, wall.heightFt)
                        }
                    }
                } else if let bench = curbRun.benches.first(where: { $0.wallID == wall.id }) {
                    let s = faceStrip(wall, at: corner, n: n, into: into, width: curbWidthFt)
                    add("\(key):lower", s, curbWidthFt, curb, bench.heightIn / 12)
                    add("\(key):upper", s, curbWidthFt, bench.heightIn / 12, top)
                } else {
                    add(key, faceStrip(wall, at: corner, n: n, into: into, width: curbWidthFt), curbWidthFt, curb, top)
                }
            }
        }
        return out
    }

    /// A strip on the underside of something, for drawing: a door's header
    /// (the underside of the top of the doorway, as deep as the wall) and the
    /// ceiling headers over the curb and half wall caps. `a`–`b` runs down
    /// its middle at `heightFt`, facing down.
    struct HeaderStrip: Equatable {
        var key: String
        var a: ScannedRoom.Point
        var b: ScannedRoom.Point
        var widthFt: Double
        var heightFt: Double
    }

    /// Each shower door's jambs (the sides of the doorway, as deep as the
    /// wall, from the curb up to the header) as `JambFace`s, and its header,
    /// and the ceiling headers, keyed as `trimPieces` keys them.
    func doorAndHeaderFaces(in room: ScannedRoom, curbHeightIn: Double, curbWidthFt: Double = 4.5 / 12)
        -> (jambs: [JambFace], headers: [HeaderStrip]) {
        let curb = curbless ? 0 : (self.curbHeightIn ?? curbHeightIn) / 12
        let top = pieces.filter { room.wall($0.wallID)?.planned == false }.map { $0.heightIn / 12 }.max() ?? room.ceilingFt
        let floorMid: ScannedRoom.Point = floorRect.map { r in
            let c = r.corners
            return .init(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        } ?? room.middle
        var jambs: [JambFace] = []
        var headers: [HeaderStrip] = []
        for d in showerDoors(in: room) {
            guard let w = d.wallID.flatMap({ room.wall($0) }), w.lengthFt > 0 else { continue }
            let u = ScannedRoom.Point(x: (w.end.x - w.start.x) / w.lengthFt, y: (w.end.y - w.start.y) / w.lengthFt)
            let s = room.span(of: d)
            let lo = room.point(on: w, along: s.lowerBound), hi = room.point(on: w, along: s.upperBound)
            let t = Self.drawnThicknessFt(w)
            let wallTop = pieces.filter { $0.wallID == w.id }.map { $0.heightIn / 12 }.max() ?? top
            let header = room.hasHeader(d)
            var jambTop = header ? min(d.bottomFt + d.heightFt, wallTop) : wallTop
            if let sf = soffits.first(where: { $0.over == "door:\(d.id.uuidString)" }) { jambTop = min(jambTop, room.ceilingFt - sf.dropIn / 12) }
            for (p, facing) in [(lo, u), (hi, ScannedRoom.Point(x: -u.x, y: -u.y))] {
                let name = sideName(p, entry: (lo, hi), center: floorMid)
                if jambTop - curb > 0.01 {
                    jambs.append(JambFace(key: "jamb:\(d.id):\(name)", center: p, facing: facing, widthFt: t,
                                          bottomFt: curb, topFt: jambTop))
                }
            }
            if header {
                headers.append(HeaderStrip(key: "header:\(d.id)", a: lo, b: hi, widthFt: t, heightFt: d.bottomFt + d.heightFt))
            }
        }
        if floor == .drawn, floorRect != nil {
            let ceiling = room.ceilingFt
            let dropped = Set(soffits.map(\.over))
            if !curbless, !dropped.contains("curb") {
                for run in curbRuns(in: room, widthFt: curbWidthFt) where run.key == "curb" {
                    // Over the curb's middle.
                    let l = max(hypot(run.b.x - run.a.x, run.b.y - run.a.y), 1e-9)
                    var n = ScannedRoom.Point(x: -(run.b.y - run.a.y) / l, y: (run.b.x - run.a.x) / l)
                    let m = ScannedRoom.Point(x: (run.a.x + run.b.x) / 2, y: (run.a.y + run.b.y) / 2)
                    if (m.x - floorMid.x) * n.x + (m.y - floorMid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
                    let o = curbWidthFt / 2
                    headers.append(HeaderStrip(key: "header:ceiling", a: .init(x: run.a.x + n.x * o, y: run.a.y + n.y * o),
                                               b: .init(x: run.b.x + n.x * o, y: run.b.y + n.y * o), widthFt: curbWidthFt, heightFt: ceiling))
                }
            } else {
                for side in openSides(in: room) {
                    headers.append(HeaderStrip(key: "header:ceiling", a: side.a, b: side.b, widthFt: curbWidthFt, heightFt: ceiling))
                }
            }
            for w in room.walls where room.isKneeWall(w) && pieces.contains(where: { $0.wallID == w.id })
                && !dropped.contains("cap:\(w.id.uuidString)") {
                headers.append(HeaderStrip(key: "header:ceiling:\(w.id)", a: w.start, b: w.end,
                                           widthFt: Self.drawnThicknessFt(w), heightFt: ceiling))
            }
        }
        return (jambs, headers)
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
        func mapped(_ r: FloorRect) -> FloorRect {
            let u = c.mapVector(.init(x: r.u.x * r.widthFt, y: r.u.y * r.widthFt))
            let v = c.mapVector(.init(x: r.v.x * r.depthFt, y: r.v.y * r.depthFt))
            let lu = hypot(u.x, u.y), lv = hypot(v.x, v.y)
            return FloorRect(origin: c.map(r.origin), u: .init(x: u.x / max(lu, 1e-9), y: u.y / max(lu, 1e-9)),
                             v: .init(x: v.x / max(lv, 1e-9), y: v.y / max(lv, 1e-9)), widthFt: lu, depthFt: lv)
        }
        if let r = t.floorRect { t.floorRect = mapped(r) }
        // A Floor area's "no tile" boxes, its own outline and the other areas' floors move with the scan.
        t.skipBoxes = t.skipBoxes.map(mapped)
        t.floorOutline = t.floorOutline?.map { c.map($0) }
        t.cutouts = t.cutouts.map { $0.map { c.map($0) } }
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
    /// A cove of three walls around `p`, for a shower to fill: a back wall
    /// and a wall each side running out from it, `p` between them and no
    /// further out than the shorter side wall reaches (the outside corner).
    /// Looked for along the room's square directions; 2–10′ each way. The
    /// floor's corner at the back, `u` across to the other side, `v` out of
    /// the cove; the smallest when there's a choice.
    /// How far a wall's end reaches past its line's end into the wall it
    /// meets there: half that wall's drawn thickness when a wall runs across
    /// its end (its line through the end), else 0. A scanned wall's corner
    /// is that far out (owner, 2026-10-13: "the curb should go to the
    /// corner").
    func endJoinFt(_ w: Wall, start: Bool) -> Double {
        guard !w.planned, w.lengthFt > 0 else { return 0 }
        let p = start ? w.start : w.end
        let ux = (w.end.x - w.start.x) / w.lengthFt, uy = (w.end.y - w.start.y) / w.lengthFt
        let across = walls.filter { o in
            guard o.id != w.id, !o.planned, o.lengthFt > 0 else { return false }
            let dot = abs(((o.end.x - o.start.x) * ux + (o.end.y - o.start.y) * uy) / o.lengthFt)
            return dot < 0.5 && distanceToWall(p, o) < 0.1
        }
        return across.isEmpty ? 0 : AreaTakeoff.drawnThicknessFt(across[0]) / 2
    }

    func cove(around p: Point) -> (origin: Point, u: Point, v: Point, widthFt: Double, depthFt: Double)? {
        let a = squaringAngle
        let dirs = [Point(x: cos(a), y: sin(a)), Point(x: -sin(a), y: cos(a)),
                    Point(x: -cos(a), y: -sin(a)), Point(x: sin(a), y: -cos(a))]
        func dot(_ q: Point, _ r: Point) -> Double { q.x * r.x + q.y * r.y }
        /// The nearest wall a ray from `p` meets, and how far.
        func hit(_ d: Point) -> (wall: Wall, t: Double)? {
            var best: (Wall, Double)?
            for w in walls where w.lengthFt > 0.1 && !isKneeWall(w) {
                let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
                let den = d.x * ey - d.y * ex
                guard abs(den) > 1e-9 else { continue }
                let qx = w.start.x - p.x, qy = w.start.y - p.y
                let t = (qx * ey - qy * ex) / den
                let s = (qx * d.y - qy * d.x) / den
                guard t > 1e-6, s >= -0.02, s <= 1.02, t < (best?.1 ?? .infinity) else { continue }
                best = (w, t)
            }
            return best.map { ($0.0, $0.1) }
        }
        let hits = dirs.map(hit)
        var found: (origin: Point, u: Point, v: Point, widthFt: Double, depthFt: Double)?
        for k in 0..<4 {
            let back = dirs[k], s1 = dirs[(k + 1) % 4], s2 = dirs[(k + 3) % 4], out = dirs[(k + 2) % 4]
            guard let hb = hits[k], let h1 = hits[(k + 1) % 4], let h2 = hits[(k + 3) % 4] else { continue }
            func unit(_ w: Wall) -> Point {
                let l = max(w.lengthFt, 1e-9)
                return .init(x: (w.end.x - w.start.x) / l, y: (w.end.y - w.start.y) / l)
            }
            // The back wall square across, the sides running out from it.
            guard abs(dot(unit(hb.wall), back)) < 0.3, abs(dot(unit(h1.wall), back)) > 0.9,
                  abs(dot(unit(h2.wall), back)) > 0.9 else { continue }
            let b = Point(x: p.x + back.x * hb.t, y: p.y + back.y * hb.t)
            // How far each side wall runs out from the back wall: the cove's depth is the shorter.
            // (over every section of it: a divider partway along a side doesn't end it)
            // Out to the wall's corner: past its line's end into a wall across it.
            func reach(_ w: Wall) -> Double {
                sections(of: w.id).map { w in max(dot(Point(x: w.start.x - b.x, y: w.start.y - b.y), out) + endJoinFt(w, start: true),
                                                  dot(Point(x: w.end.x - b.x, y: w.end.y - b.y), out) + endJoinFt(w, start: false)) }.max() ?? 0
            }
            let depth = min(reach(h1.wall), reach(h2.wall))
            let width = h1.t + h2.t
            // The tap inside it, and nothing across the open side before the corners.
            guard hb.t < depth, width >= 2, width <= 10, depth >= 2, depth <= 10 else { continue }
            if let ho = hits[(k + 2) % 4], ho.t < depth - hb.t + 0.25 { continue }
            // Its open side really open: no wall along that line between the sides.
            let mouth = Point(x: b.x + out.x * depth, y: b.y + out.y * depth)
            let closed = walls.contains { w in
                guard w.id != h1.wall.id, w.id != h2.wall.id, abs(dot(unit(w), back)) < 0.3 else { return false }
                func offLine(_ q: Point) -> Double { abs(dot(Point(x: q.x - mouth.x, y: q.y - mouth.y), back)) }
                guard offLine(w.start) < 0.3, offLine(w.end) < 0.3 else { return false }
                // Across the mouth, from side 1 (−h1) to side 2 (+h2), measured along s2.
                let t0 = dot(Point(x: w.start.x - mouth.x, y: w.start.y - mouth.y), s2)
                let t1 = dot(Point(x: w.end.x - mouth.x, y: w.end.y - mouth.y), s2)
                let lo = max(min(t0, t1), -h1.t), hi = min(max(t0, t1), h2.t)
                return hi - lo > 0.5
            }
            if closed { continue }
            if let f = found, f.widthFt * f.depthFt <= width * depth { continue }
            let origin = Point(x: b.x + s1.x * h1.t, y: b.y + s1.y * h1.t)
            found = (origin, s2, out, width, depth)
        }
        return found
    }

    /// The end of a narrow room or a long alcove (owner, 2026-10-14: a shower
    /// across the end of a sketched room came out as a corner shower): a back
    /// wall with a side wall square to it at each end, 2½–6′ apart, running
    /// out past the tap. The shower goes wall to wall across it.
    func roomEnd(around p: Point) -> (origin: Point, u: Point, v: Point, widthFt: Double, reachFt: Double)? {
        let a = squaringAngle
        let dirs = [Point(x: cos(a), y: sin(a)), Point(x: -sin(a), y: cos(a)),
                    Point(x: -cos(a), y: -sin(a)), Point(x: sin(a), y: -cos(a))]
        func dot(_ q: Point, _ r: Point) -> Double { q.x * r.x + q.y * r.y }
        func hit(_ d: Point) -> (wall: Wall, t: Double)? {
            var best: (Wall, Double)?
            for w in walls where w.lengthFt > 0.1 && !isKneeWall(w) {
                let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
                let den = d.x * ey - d.y * ex
                guard abs(den) > 1e-9 else { continue }
                let qx = w.start.x - p.x, qy = w.start.y - p.y
                let t = (qx * ey - qy * ex) / den
                let s = (qx * d.y - qy * d.x) / den
                guard t > 1e-6, s >= -0.02, s <= 1.02, t < (best?.1 ?? .infinity) else { continue }
                best = (w, t)
            }
            return best.map { ($0.0, $0.1) }
        }
        func unit(_ w: Wall) -> Point {
            let l = max(w.lengthFt, 1e-9)
            return .init(x: (w.end.x - w.start.x) / l, y: (w.end.y - w.start.y) / l)
        }
        let hits = dirs.map(hit)
        var best: (origin: Point, u: Point, v: Point, widthFt: Double, reachFt: Double)?
        for k in 0..<4 {
            let back = dirs[k], s1 = dirs[(k + 1) % 4], s2 = dirs[(k + 3) % 4], out = dirs[(k + 2) % 4]
            guard let hb = hits[k], let h1 = hits[(k + 1) % 4], let h2 = hits[(k + 3) % 4] else { continue }
            guard abs(dot(unit(hb.wall), back)) < 0.3, abs(dot(unit(h1.wall), back)) > 0.9,
                  abs(dot(unit(h2.wall), back)) > 0.9 else { continue }
            let width = h1.t + h2.t
            guard width >= 2.5, width <= 6, hb.t < 6 else { continue }
            let b = Point(x: p.x + back.x * hb.t, y: p.y + back.y * hb.t)
            // How far the room runs out from the back wall (to the far wall, or the sides' ends).
            let far = hits[(k + 2) % 4].map { $0.t + hb.t } ?? 10
            guard far > 3 else { continue }
            // Nearest back wall wins.
            if let f = best, dot(Point(x: f.origin.x - p.x, y: f.origin.y - p.y), back) <= hb.t { continue }
            let origin = Point(x: b.x + s1.x * h1.t, y: b.y + s1.y * h1.t)
            best = (origin, s2, out, width, far)
        }
        return best
    }

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

    /// Where a tap puts the shower (owner's call, 2026-10-08): inside a cove
    /// of three walls, the floor fills it, its curb's outside face flush with
    /// the cove's outside corners (`coveDepthFt`); anywhere else, a 48″ × 48″
    /// floor in the nearest inside corner (as far as its walls go). The walls
    /// round it are tiled. False with no cove or corner near.
    mutating func placeShower(near tap: ScannedRoom.Point, in room: ScannedRoom, curbWidthFt: Double) -> Bool {
        if let cove = room.cove(around: tap) {
            floor = .drawn
            coveDepthFt = cove.depthFt
            floorRect = FloorRect(origin: cove.origin, u: cove.u, v: cove.v, widthFt: cove.widthFt,
                                  depthFt: curbless ? cove.depthFt : max(1, cove.depthFt - curbWidthFt))
            tileWallsAroundFloor(in: room)
            return true
        }
        // The end of a narrow room: wall to wall, 48″ deep (a corner shower's depth).
        if let end = room.roomEnd(around: tap) {
            floor = .drawn
            coveDepthFt = nil
            floorRect = FloorRect(origin: end.origin, u: end.u, v: end.v, widthFt: end.widthFt,
                                  depthFt: min(4, max(1, end.reachFt - 3)))
            tileWallsAroundFloor(in: room)
            return true
        }
        guard let corner = room.insideCorners().min(by: {
            hypot($0.at.x - tap.x, $0.at.y - tap.y) < hypot($1.at.x - tap.x, $1.at.y - tap.y)
        }) else { return false }
        // Along each wall from the corner, as far as it goes.
        func reach(_ dir: ScannedRoom.Point) -> Double {
            room.walls.filter { !$0.planned }.compactMap { w -> Double? in
                let wx = (w.end.x - w.start.x) / max(w.lengthFt, 1e-9), wy = (w.end.y - w.start.y) / max(w.lengthFt, 1e-9)
                guard abs(wx * dir.x + wy * dir.y) > 0.9 else { return nil }
                let mid = ScannedRoom.Point(x: corner.at.x + dir.x * 0.2, y: corner.at.y + dir.y * 0.2)
                return room.distanceToWall(mid, w) < 0.3 ? w.lengthFt : nil
            }.max() ?? 4
        }
        let ra = reach(corner.a), rb = reach(corner.b)
        let (u, v, along, deep) = ra >= rb ? (corner.a, corner.b, ra, rb) : (corner.b, corner.a, rb, ra)
        floor = .drawn
        coveDepthFt = nil
        floorRect = FloorRect(origin: corner.at, u: u, v: v, widthFt: min(4, along), depthFt: min(4, deep))
        tileWallsAroundFloor(in: room)
        return true
    }

    /// Takes the curb off (curbless) or puts it back. A floor filling a cove
    /// runs to the outside corners without one and stops at the curb's inside
    /// face with one; any other floor keeps its size.
    mutating func setCurbless(_ on: Bool, curbWidthFt: Double) {
        curbless = on
        if let cove = coveDepthFt, floorRect != nil {
            floorRect?.depthFt = on ? cove : max(1, cove - curbWidthFt)
        }
    }

    // MARK: The drain

    /// A linear drain's width on the plan.
    static let linearDrainWidthFt = 2.5 / 12
    /// A square drain's size.
    static let centerDrainFt = 4.0 / 12

    /// The drain as it is: the one chosen, kept inside the floor, else a
    /// square drain in the middle of the floor.
    func drainShown() -> Drain? {
        guard let r = floorRect else { return nil }
        guard var d = drain else {
            return Drain(kind: .center, alongWidthFt: r.widthFt / 2, alongDepthFt: r.depthFt / 2)
        }
        if d.kind == .linear {
            let run = d.runsAlongWidth ? r.widthFt : r.depthFt
            d.lengthFt = min(max(d.lengthFt, 2.0 / 12), run)
            let half = d.lengthFt / 2, side = Self.linearDrainWidthFt / 2
            let (wHalf, dHalf) = d.runsAlongWidth ? (half, side) : (side, half)
            d.alongWidthFt = min(max(d.alongWidthFt, wHalf), r.widthFt - wHalf)
            d.alongDepthFt = min(max(d.alongDepthFt, dHalf), r.depthFt - dHalf)
        } else {
            let h = Self.centerDrainFt / 2
            d.alongWidthFt = min(max(d.alongWidthFt, h), r.widthFt - h)
            d.alongDepthFt = min(max(d.alongDepthFt, h), r.depthFt - h)
        }
        return d
    }

    /// A linear drain's starting place: against the floor's longest side
    /// that is a wall, wall to wall.
    func startingLinearDrain(in room: ScannedRoom) -> Drain? {
        guard let r = floorRect else { return nil }
        let c = r.corners
        let open = openSides(in: room)
        func isWall(_ i: Int) -> Bool {
            let a = c[i], b = c[(i + 1) % 4]
            let mid = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            return !open.contains { s in
                let ex = s.b.x - s.a.x, ey = s.b.y - s.a.y, l = max(hypot(ex, ey), 1e-9)
                return abs((mid.x - s.a.x) * -ey / l + (mid.y - s.a.y) * ex / l) < 0.05
            }
        }
        // Sides 0 and 2 run along the width, 1 and 3 along the depth.
        let sides = (0..<4).filter(isWall)
        let pick = (sides.isEmpty ? Array(0..<4) : sides).max { a, b in
            (a % 2 == 0 ? r.widthFt : r.depthFt) < (b % 2 == 0 ? r.widthFt : r.depthFt)
        } ?? 0
        let w = Self.linearDrainWidthFt / 2
        switch pick {
        case 0: return Drain(kind: .linear, alongWidthFt: r.widthFt / 2, alongDepthFt: w, lengthFt: r.widthFt, runsAlongWidth: true)
        case 2: return Drain(kind: .linear, alongWidthFt: r.widthFt / 2, alongDepthFt: r.depthFt - w, lengthFt: r.widthFt, runsAlongWidth: true)
        case 1: return Drain(kind: .linear, alongWidthFt: r.widthFt - w, alongDepthFt: r.depthFt / 2, lengthFt: r.depthFt, runsAlongWidth: false)
        default: return Drain(kind: .linear, alongWidthFt: w, alongDepthFt: r.depthFt / 2, lengthFt: r.depthFt, runsAlongWidth: false)
        }
    }

    /// A linear drain turned a quarter turn about its middle, no longer than the floor allows.
    static func turnedDrain(_ d: Drain, in r: FloorRect) -> Drain {
        var t = d
        t.runsAlongWidth.toggle()
        t.lengthFt = min(d.lengthFt, t.runsAlongWidth ? r.widthFt : r.depthFt)
        return t
    }

    /// The drain's outline on the plan.
    func drainOutline(_ d: Drain) -> [ScannedRoom.Point] {
        floorRect.map { Self.drainOutline(d, in: $0) } ?? []
    }

    static func drainOutline(_ d: Drain, in r: FloorRect) -> [ScannedRoom.Point] {
        let (hw, hd): (Double, Double) = d.kind == .center ? (Self.centerDrainFt / 2, Self.centerDrainFt / 2)
            : d.runsAlongWidth ? (d.lengthFt / 2, Self.linearDrainWidthFt / 2) : (Self.linearDrainWidthFt / 2, d.lengthFt / 2)
        func at(_ a: Double, _ b: Double) -> ScannedRoom.Point {
            .init(x: r.origin.x + r.u.x * a + r.v.x * b, y: r.origin.y + r.u.y * a + r.v.y * b)
        }
        let a = d.alongWidthFt, b = d.alongDepthFt
        return [at(a - hw, b - hd), at(a + hw, b - hd), at(a + hw, b + hd), at(a - hw, b + hd)]
    }

    /// A linear drain moved to `w`, `d` (feet along the floor's width and
    /// depth): its long side snaps flush to a side of the floor (a wall, or
    /// the outside corners of a curbless cove) and its middle to the
    /// floor's middle, within 1½″.
    static func snappedDrain(_ drain: Drain, in r: FloorRect, alongWidth w: Double, alongDepth d: Double,
                             pull: Double = Steering.catchFt) -> Drain {
        var out = drain
        func snap(_ v: Double, _ targets: [Double]) -> Double {
            // To the sixteenth, or to a target within 1½″.
            targets.min { abs($0 - v) < abs($1 - v) }.flatMap { abs($0 - v) < pull ? $0 : nil } ?? (v * 192).rounded() / 192
        }
        let half = linearDrainWidthFt / 2
        if drain.kind == .center {
            out.alongWidthFt = snap(w, [r.widthFt / 2])
            out.alongDepthFt = snap(d, [r.depthFt / 2])
        } else if drain.runsAlongWidth {
            out.alongDepthFt = snap(d, [half, r.depthFt - half, r.depthFt / 2])
            out.alongWidthFt = snap(w, [r.widthFt / 2, drain.lengthFt / 2, r.widthFt - drain.lengthFt / 2])
        } else {
            out.alongWidthFt = snap(w, [half, r.widthFt - half, r.widthFt / 2])
            out.alongDepthFt = snap(d, [r.depthFt / 2, drain.lengthFt / 2, r.depthFt - drain.lengthFt / 2])
        }
        return out
    }

    /// The scanned walls the shower floor stands against, tiled along the
    /// floor's sides: each keeps the height its tile had (else the top of the
    /// wall); walls drawn in and other walls' tile are left alone.
    /// Wall tile that stops at the shower floor's corner where the entry
    /// is runs on to the curb's outside edge (owner, 2026-10-13): for showers
    /// placed before that rule, so opening one brings it up to date. A piece
    /// already past the corner is left as it is.
    mutating func extendTileToCurb(in room: ScannedRoom, curbWidthFt: Double = 4.5 / 12) {
        guard !curbless, floor == .drawn, floorRect != nil else { return }
        for side in openSides(in: room) {
            for (corner, wall) in [(side.a, side.startWall), (side.b, side.endWall)] {
                guard let wall, !wall.planned else { continue }
                let along = room.along(corner, on: wall)
                for i in pieces.indices where pieces[i].wallID == wall.id {
                    if abs(pieces[i].fromFt - along) < 0.15, pieces[i].toFt > along {
                        pieces[i].fromFt = max(-room.endJoinFt(wall, start: true), along - curbWidthFt)
                    } else if abs(pieces[i].toFt - along) < 0.15, pieces[i].fromFt < along {
                        pieces[i].toFt = min(wall.lengthFt + room.endJoinFt(wall, start: false), along + curbWidthFt)
                    }
                }
            }
        }
    }

    /// A shower filling a cove, placed before the cove reached the walls'
    /// corners: its floor deepened to reach them (owner, 2026-10-13: "the
    /// curb should go to the corner"), its walls tiled again.
    mutating func fitCove(in room: ScannedRoom, curbWidthFt: Double = 4.5 / 12) {
        guard floor == .drawn, let r = floorRect, let old = coveDepthFt,
              let cove = room.cove(around: r.center), abs(cove.depthFt - old) > 0.01, abs(cove.widthFt - r.widthFt) < 0.1 else { return }
        floorRect?.depthFt = max(1, r.depthFt + cove.depthFt - old)
        coveDepthFt = cove.depthFt
        tileWallsAroundFloor(in: room)
    }

    /// A floor edge let go within reach of a wall (the 0.4′ that counts as
    /// against it) goes the rest of the way, so a three-wall shower's floor
    /// is tight to all three (owner, 2026-10-14).
    mutating func snapFloorToWalls(in room: ScannedRoom) {
        guard floor == .drawn, var r = floorRect else { return }
        func gap(along a: ScannedRoom.Point, _ b: ScannedRoom.Point, out n: ScannedRoom.Point) -> Double? {
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
            let u = ScannedRoom.Point(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
            var best: Double?
            // The room's own walls (a wall drawn in on the curb stands over the curb, not the floor).
            for w in room.walls where w.lengthFt > 0.1 && !w.planned {
                let wl = w.lengthFt
                guard abs(((w.end.x - w.start.x) * u.x + (w.end.y - w.start.y) * u.y) / wl) > 0.95 else { continue }
                let g = (w.start.x - a.x) * n.x + (w.start.y - a.y) * n.y
                guard g > 0.005, g < 0.4 else { continue }
                // Running along most of the edge.
                let t0 = (w.start.x - a.x) * u.x + (w.start.y - a.y) * u.y, t1 = (w.end.x - a.x) * u.x + (w.end.y - a.y) * u.y
                let overlap = min(len, max(t0, t1)) - max(0, min(t0, t1))
                guard overlap > min(1, len / 2) else { continue }
                best = min(best ?? g, g)
            }
            return best
        }
        let c = r.corners
        // Edge along u at the origin (out: −v), and the far one (out: +v).
        if let g = gap(along: c[0], c[1], out: .init(x: -r.v.x, y: -r.v.y)) {
            r.origin = .init(x: r.origin.x - r.v.x * g, y: r.origin.y - r.v.y * g); r.depthFt += g
        }
        if let g = gap(along: c[3], c[2], out: r.v) { r.depthFt += g }
        // Edge along v at the origin (out: −u), and the far one (out: +u).
        let c2 = r.corners
        if let g = gap(along: c2[0], c2[3], out: .init(x: -r.u.x, y: -r.u.y)) {
            r.origin = .init(x: r.origin.x - r.u.x * g, y: r.origin.y - r.u.y * g); r.widthFt += g
        }
        if let g = gap(along: c2[1], c2[2], out: r.u) { r.widthFt += g }
        floorRect = r
    }

    mutating func tileWallsAroundFloor(in room: ScannedRoom) {
        snapFloorToWalls(in: room)
        guard floor == .drawn, let r = floorRect else { return }
        let c = r.corners
        var kept: [Piece] = pieces.filter { room.wall($0.wallID)?.planned == true }
        var used = Set<UUID>()
        // Wall tile runs on past the floor to the curb's outside edge where
        // the floor's edge at that corner is open (owner, 2026-10-13: "wall
        // tile typically extends to the outside edge of the curb").
        let curb = curbless ? 0 : 4.5 / 12
        let open = openSides(in: room)
        func curbAt(_ p: ScannedRoom.Point, along u: ScannedRoom.Point) -> Double {
            open.contains { side in
                let touches = hypot(side.a.x - p.x, side.a.y - p.y) < 0.05 || hypot(side.b.x - p.x, side.b.y - p.y) < 0.05
                let sl = max(side.lengthFt, 1e-9)
                let across = abs(((side.b.x - side.a.x) * u.x + (side.b.y - side.a.y) * u.y) / sl) < 0.5
                return touches && across
            } ? curb : 0
        }
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            let dx = b.x - a.x, dy = b.y - a.y, l = max(hypot(dx, dy), 1e-9)
            let mid = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            guard let w = room.walls.first(where: { w in
                guard !w.planned else { return false }
                let wx = w.end.x - w.start.x, wy = w.end.y - w.start.y, wl = max(hypot(wx, wy), 1e-9)
                return abs((dx * wx + dy * wy) / (l * wl)) > 0.95 && room.distanceToWall(mid, w) < 0.4
            }) else { continue }
            // Each section of that wall the side runs along (a divider partway along it).
            let u = ScannedRoom.Point(x: dx / l, y: dy / l)
            let extA = curbAt(a, along: u), extB = curbAt(b, along: u)
            for w in room.sections(of: w.id) {
                let ta = room.along(a, on: w), tb = room.along(b, on: w)
                let lo = max(-room.endJoinFt(w, start: true), ta < tb ? ta - extA : tb - extB)
                let hi = min(w.lengthFt + room.endJoinFt(w, start: false), ta < tb ? tb + extB : ta + extA)
                guard hi - lo > 0.1 else { continue }
                let height = pieces.first { $0.wallID == w.id }?.heightIn ?? Self.startingHeight(for: .shower, wall: w)
                let id = used.contains(w.id) ? UUID() : (pieces.first { $0.wallID == w.id }?.id ?? UUID())
                used.insert(w.id)
                kept.append(Piece(id: id, wallID: w.id, fromFt: lo, toFt: hi, heightIn: height))
            }
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

    /// Scanned walls in line with `id` and up to 5′ from it end to end: one
    /// wall the scanner gave in pieces either side of a doorway (owner,
    /// 2026-10-08: "a doorway doesn't create two walls"). They move together.
    func inLine(with id: UUID) -> [Wall] {
        guard let w = wall(id), !w.planned else { return [] }
        var group = [w]
        var grew = true
        while grew {
            grew = false
            for o in walls where !o.planned && !group.contains(where: { $0.id == o.id }) {
                let joined = group.contains { g in
                    let u = Self.unit(g), n = Point(x: -u.y, y: u.x)
                    guard abs(u.x * Self.unit(o).x + u.y * Self.unit(o).y) > 0.996 else { return false }
                    func off(_ p: Point) -> Double { abs((p.x - g.start.x) * n.x + (p.y - g.start.y) * n.y) }
                    guard off(o.start) < 0.15, off(o.end) < 0.15 else { return false }
                    let gap = [Self.dist(g.start, o.start), Self.dist(g.start, o.end),
                               Self.dist(g.end, o.start), Self.dist(g.end, o.end)].min()!
                    return gap <= 5
                }
                if joined { group.append(o); grew = true }
            }
        }
        return group
    }

    /// A wall slid sideways (square to itself) by `d` feet on the plan, to
    /// the sixteenth, with any pieces of it across a doorway (`inLine`),
    /// keeping the room joined: a wall sharing a corner stretches to follow;
    /// an end that meets the middle of another wall slides along it; a wall
    /// running into this one follows it. Doors and windows keep their places
    /// in their walls, and the floor outline follows.
    mutating func moveWall(_ id: UUID, by d: Point) {
        guard let w = wall(id) else { return }
        let u = Self.unit(w), n = Point(x: -u.y, y: u.x)
        let off = ((d.x * n.x + d.y * n.y) * 192).rounded() / 192
        guard abs(off) > 1e-9 else { return }
        let before = self
        let pieces = inLine(with: id).map(\.id)
        for piece in pieces.isEmpty ? [id] : pieces {
            slide(piece, by: Point(x: n.x * off, y: n.y * off))
        }
        followAll(from: before)
    }

    /// One wall slid by `shift` (square to it), keeping the room joined.
    private mutating func slide(_ id: UUID, by shift: Point) {
        guard let w = wall(id) else { return }
        let u = Self.unit(w)
        let before = self
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
    }

    /// One end of a wall moved to `p`. A wall square across that end (the
    /// closet's door wall at the end of a divider) slides with it, whole —
    /// with its pieces across a doorway — so the room stays square; any
    /// other wall sharing the corner follows the corner.
    mutating func moveWallEnd(_ id: UUID, start: Bool, to p: Point) {
        guard let w = wall(id) else { return }
        let before = self
        let old = start ? w.start : w.end
        let u = Self.unit(w)
        if let across = walls.first(where: { o in
            o.id != id && (Self.dist(o.start, old) < 0.35 || Self.dist(o.end, old) < 0.35)
                && abs(Self.unit(o).x * u.x + Self.unit(o).y * u.y) < 0.3
        }) {
            let along = (p.x - old.x) * u.x + (p.y - old.y) * u.y
            let pieces = inLine(with: across.id).map(\.id)
            for piece in pieces.isEmpty ? [across.id] : pieces {
                slide(piece, by: Point(x: u.x * along, y: u.y * along))
            }
            followAll(from: before)
            return
        }
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

    // MARK: Sections

    /// Every scanned wall cut into sections where a divider meets it partway
    /// — a full-height wall, scanned or drawn in, with an end on it — so each
    /// section has its own letter and face-on view (owner, 2026-10-09); and
    /// sections joined again where no divider meets them any more. Half
    /// walls don't divide a wall (it carries on above them), and walls drawn
    /// in are never divided. Sections are in line and joined, so they move as
    /// one wall (`inLine`) and a divider's end moves their joint with it.
    /// Ids are worked out from the wall and the divider, so a drag that
    /// divides a wall at every step gives the section the same id each time.
    /// Returns whether anything changed.
    @discardableResult
    mutating func sectionAtDividers() -> Bool {
        var changed = false
        func divides(_ d: Wall) -> Bool { !isKneeWall(d) && d.lengthFt > 0.25 }
        // Joined again where the divider has gone.
        var merging = true
        while merging {
            merging = false
            for x in walls where x.startsAtDivider {
                guard let p = sectionBefore(x), abs(p.heightFt - x.heightFt) < 0.01 else { continue }
                let joint = x.start
                let divided = walls.contains { d in
                    d.id != x.id && d.id != p.id && divides(d)
                        && (Self.dist(d.start, joint) < 0.35 || Self.dist(d.end, joint) < 0.35)
                }
                guard !divided, let i = walls.firstIndex(where: { $0.id == p.id }) else { continue }
                let before = p.lengthFt
                walls[i].end = x.end
                walls[i].lengthFt = Self.dist(walls[i].start, x.end)
                for j in openings.indices where openings[j].wallID == x.id {
                    openings[j].wallID = p.id
                    openings[j].alongFt = openings[j].alongFt.map { $0 + before }
                }
                walls.removeAll { $0.id == x.id }
                changed = true
                merging = true
                break
            }
        }
        // Divided where a divider's end meets a wall partway.
        var splitting = true
        while splitting {
            splitting = false
            outer: for w in walls where !w.planned {
                for d in walls where d.id != w.id && divides(d) {
                    for (isStart, p) in [(true, d.start), (false, d.end)] where onRun(p, w) {
                        // Not a scan's corner a few inches out: 6″ or more each side.
                        let at = along(p, on: w)
                        guard at >= 0.5, at <= w.lengthFt - 0.5, let second = splitWall(w.id, atFt: at),
                              let k = walls.firstIndex(where: { $0.id == second.id }) else { continue }
                        let id = Self.sectionID(w.id, d.id, isStart)
                        for j in openings.indices where openings[j].wallID == second.id { openings[j].wallID = id }
                        walls[k].id = id
                        walls[k].startsAtDivider = true
                        changed = true
                        splitting = true
                        break outer
                    }
                }
            }
        }
        return changed
    }

    /// A section's id: the same every time for a wall divided by a divider's end.
    static func sectionID(_ wall: UUID, _ divider: UUID, _ start: Bool) -> UUID {
        var a = wall.uuid
        let b = divider.uuid
        withUnsafeMutableBytes(of: &a) { ap in
            withUnsafeBytes(of: b) { bp in
                for i in 0..<16 { ap[i] ^= bp[(i + 5) % 16] }
            }
        }
        a.15 ^= start ? 0x5D : 0xA7
        a.6 = (a.6 & 0x0F) | 0x40
        a.8 = (a.8 & 0x3F) | 0x80
        return UUID(uuid: a)
    }

    /// The sections joined end to end and in line with a wall, itself
    /// included, in order along it (one wall before it was divided).
    func sections(of id: UUID) -> [Wall] {
        guard let w = wall(id), !w.planned else { return wall(id).map { [$0] } ?? [] }
        var run = [w]
        while let first = run.first, first.startsAtDivider,
              let p = sectionBefore(first), !run.contains(where: { $0.id == p.id }) { run.insert(p, at: 0) }
        while let last = run.last, let n = sectionAfter(last), !run.contains(where: { $0.id == n.id }) { run.append(n) }
        return run
    }

    /// The section a divider section follows on from: in line, its end at this one's start.
    private func sectionBefore(_ x: Wall) -> Wall? {
        walls.first { p in
            p.id != x.id && !p.planned && Self.dist(p.end, x.start) < 0.05
                && Self.unit(p).x * Self.unit(x).x + Self.unit(p).y * Self.unit(x).y > 0.999
        }
    }

    /// The section that follows on from this one at a divider.
    private func sectionAfter(_ p: Wall) -> Wall? {
        walls.first { x in x.startsAtDivider && sectionBefore(x)?.id == p.id }
    }

    /// The room with each wall's sections joined back into one wall (the
    /// first section's id): for dimensions, where a wall's overall length
    /// and the stretches between its dividers are what's wanted.
    func joiningSections() -> ScannedRoom {
        var r = self
        for x in walls where x.startsAtDivider {
            guard let xi = r.walls.firstIndex(where: { $0.id == x.id }), let p = r.sectionBefore(r.walls[xi]),
                  let i = r.walls.firstIndex(where: { $0.id == p.id }) else { continue }
            r.walls[i].end = r.walls[xi].end
            r.walls[i].lengthFt = Self.dist(r.walls[i].start, r.walls[i].end)
            r.walls.remove(at: xi)
        }
        return r
    }
}

extension AreaTakeoff {
    /// This area's choices moved with walls edited on the model (`old` is
    /// the room before): split walls take their part of the tile and items,
    /// tile and items keep their places along walls whose start moved, and
    /// stay on walls that got shorter; a full-height piece stays full height.
    func following(old: ScannedRoom, new: ScannedRoom) -> AreaTakeoff {
        var t = self
        // Sections joined again (`sectionAtDividers`): tile and items on a
        // wall that's gone move onto the wall now running over it, in that
        // wall's measure as it was.
        for o in old.walls where new.wall(o.id) == nil {
            let ou = o.lengthFt > 0 ? ScannedRoom.Point(x: (o.end.x - o.start.x) / o.lengthFt, y: (o.end.y - o.start.y) / o.lengthFt) : .init()
            guard let n = new.walls.first(where: { n in
                guard !n.planned, let was = old.wall(n.id), was.lengthFt > 0 else { return false }
                let u = ScannedRoom.Point(x: (was.end.x - was.start.x) / was.lengthFt, y: (was.end.y - was.start.y) / was.lengthFt)
                let off = abs((o.start.x - was.start.x) * -u.y + (o.start.y - was.start.y) * u.x)
                return u.x * ou.x + u.y * ou.y > 0.999 && off < 0.05 && hypot(was.end.x - o.start.x, was.end.y - o.start.y) < 0.05
            }), let was = old.wall(n.id) else { continue }
            let shift = was.lengthFt
            for i in t.pieces.indices where t.pieces[i].wallID == o.id {
                t.pieces[i].wallID = n.id
                t.pieces[i].fromFt += shift
                t.pieces[i].toFt += shift
            }
            for i in t.items.indices where t.items[i].wallID == o.id {
                t.items[i].wallID = n.id
                if !t.items[i].kind.isCorner {
                    t.items[i].fromFt += shift
                    t.items[i].toFt += shift
                }
            }
            // A piece either side of the joint at the same height is one piece again.
            let mine = t.pieces.filter { $0.wallID == n.id }
            for a in mine {
                guard let b = mine.first(where: { abs($0.fromFt - a.toFt) < 1e-6 && $0.heightIn == a.heightIn && $0.face == a.face }),
                      let ai = t.pieces.firstIndex(where: { $0.id == a.id }), t.pieces.contains(where: { $0.id == b.id }) else { continue }
                t.pieces[ai].toFt = b.toFt
                t.pieces.removeAll { $0.id == b.id }
            }
        }
        // Splits next, in the old wall's measure — a wall split more than
        // once at a time (several dividers) part by part, in order.
        var known = Set(old.walls.map(\.id))
        var pending = new.walls.filter { w in w.splitFrom != nil && old.wall(w.id) == nil }
        while let k = pending.firstIndex(where: { known.contains($0.splitFrom!) }) {
            let w = pending.remove(at: k)
            known.insert(w.id)
            let from = w.splitFrom!
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
            for i in t.items.indices where t.items[i].wallID == from {
                if t.items[i].kind.isCorner {
                    // A corner piece at the far end goes with the far part.
                    if !t.items[i].atStart { t.items[i].wallID = w.id }
                } else if t.items[i].fromFt >= at - 1e-9 {
                    t.items[i].wallID = w.id
                    t.items[i].fromFt -= at
                    t.items[i].toFt -= at
                }
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


// MARK: - Floor shapes

/// Areas and overlaps of floor shapes on the plan, in feet.
enum FloorGeometry {
    /// A polygon's area (either winding).
    static func area(_ p: [ScannedRoom.Point]) -> Double {
        guard p.count > 2 else { return 0 }
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return abs(s) / 2
    }

    /// The part of `subject` inside `clip`, a convex shape (a box, a tub's
    /// outline): Sutherland–Hodgman.
    static func clip(_ subject: [ScannedRoom.Point], to clip: [ScannedRoom.Point]) -> [ScannedRoom.Point] {
        guard subject.count > 2, clip.count > 2 else { return [] }
        // Clip edges counter-clockwise, so "inside" is on the left.
        let c = signedArea(clip) < 0 ? Array(clip.reversed()) : clip
        var out = subject
        for i in c.indices {
            let a = c[i], b = c[(i + 1) % c.count]
            func inside(_ p: ScannedRoom.Point) -> Bool { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0 }
            func cross(_ p: ScannedRoom.Point, _ q: ScannedRoom.Point) -> ScannedRoom.Point {
                let ex = b.x - a.x, ey = b.y - a.y
                let d1 = ex * (p.y - a.y) - ey * (p.x - a.x), d2 = ex * (q.y - a.y) - ey * (q.x - a.x)
                let t = d1 / (d1 - d2)
                return .init(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
            }
            let input = out
            out = []
            guard !input.isEmpty else { break }
            for j in input.indices {
                let p = input[j], q = input[(j + 1) % input.count]
                if inside(q) {
                    if !inside(p) { out.append(cross(p, q)) }
                    out.append(q)
                } else if inside(p) {
                    out.append(cross(p, q))
                }
            }
        }
        return out
    }

    private static func signedArea(_ p: [ScannedRoom.Point]) -> Double {
        var s = 0.0
        for i in p.indices { let a = p[i], b = p[(i + 1) % p.count]; s += a.x * b.y - b.x * a.y }
        return s / 2
    }
}


extension EstimateRoom {
    /// Every Floor area measured on the room's scan learns the other areas'
    /// floors (shower floors and their curbs), which it never tiles, and is
    /// measured again (owner, 2026-10-12). Run whenever an area is saved
    /// from the model or the scan changes.
    mutating func refreshFloorCutouts(prices: StonePrices) {
        guard let scan else { return }
        for i in sections.indices {
            guard sections[i].roomScan == nil, !sections[i].measuredByHand,
                  var t = sections[i].scanTakeoff, t.floor == .room else { continue }
            let cuts = sections.indices.filter { $0 != i && sections[$0].roomScan == nil }
                .flatMap { sections[$0].scanTakeoff?.floorFootprints(in: scan, curbWidthFt: prices.curbWidthFt) ?? [] }
            guard cuts != t.cutouts else { continue }
            t.cutouts = cuts
            t.apply(scan, to: &sections[i], prices: prices)
        }
    }
}
