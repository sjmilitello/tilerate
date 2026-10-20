import Foundation

/// Vanities and toilets on the model (owner, 2026-10-19), added from any
/// area's ⋯ like a freestanding tub. A toilet is decoration. A vanity is
/// 36″ × 21″ to start, against the wall nearest the tap, with a stone top
/// 1″ past it on its open sides and its sinks (1, or 2 from 60″ wide), and a
/// backsplash — stone, 4″ to start, or tile, or none — on any of the walls
/// it touches. Each vanity has its own area (a Backsplash area named
/// Vanity) for its tile backsplash, its stone backsplash ("Stone vanity
/// backsplash") and its top and sink cut-outs (materials, when stone
/// material is its own line).
extension ScannedRoom {
    func vanity(_ id: UUID?) -> Vanity? { id.flatMap { id in vanities.first { $0.id == id } } }

    /// The nearest wall to `p`, and where `p` is along it.
    private func nearestWall(to p: Point) -> (Wall, Double)? {
        walls.filter { $0.lengthFt > 0.5 }.min { distanceToWall(p, $0) < distanceToWall(p, $1) }.map { ($0, along(p, on: $0)) }
    }

    /// Something `widthFt` wide and `depthFt` deep against the wall nearest
    /// `p`, centred where `p` is along it (kept on the wall).
    private func againstWall(at p: Point, widthFt: Double, depthFt: Double) -> AreaTakeoff.FloorRect? {
        guard let (w, t) = nearestWall(to: p) else { return nil }
        let u = Point(x: (w.end.x - w.start.x) / w.lengthFt, y: (w.end.y - w.start.y) / w.lengthFt)
        var v = Point(x: -u.y, y: u.x)
        let s = point(on: w, along: t)
        if (p.x - s.x) * v.x + (p.y - s.y) * v.y < 0 { v = .init(x: -v.x, y: -v.y) }
        let width = min(widthFt, w.lengthFt)
        let from = min(max(0, t - width / 2), w.lengthFt - width)
        // Against the wall's face, not its line: half its drawn thickness out.
        let off = AreaTakeoff.drawnThicknessFt(w) / 2
        let o = point(on: w, along: from)
        return .init(origin: .init(x: o.x + v.x * off, y: o.y + v.y * off), u: u, v: v, widthFt: width, depthFt: depthFt)
    }

    /// A vanity where a tap puts it: 36″ × 21″ against the nearest wall, a
    /// 4″ stone backsplash on that wall.
    @discardableResult
    mutating func addVanity(at p: Point) -> Vanity? {
        guard let r = againstWall(at: p, widthFt: 3, depthFt: 1.75) else { return nil }
        var v = Vanity()
        v.rect = r
        v.splashWalls = AreaTakeoff.tubEdgeWalls(r.corners, in: self)[0].map { [$0.id] } ?? []
        vanities.append(v)
        return v
    }

    /// A vanity moved to where a tap is: against the wall nearest it, its
    /// size kept, its backsplash on that wall.
    mutating func moveVanity(_ i: Int, to p: Point) {
        guard vanities.indices.contains(i), let r = againstWall(at: p, widthFt: vanities[i].rect.widthFt, depthFt: vanities[i].rect.depthFt) else { return }
        vanities[i].rect = r
        vanities[i].splashWalls = AreaTakeoff.tubEdgeWalls(r.corners, in: self)[0].map { [$0.id] } ?? []
    }

    /// A toilet moved to where a tap is, against the wall nearest it.
    mutating func moveToilet(_ i: Int, to p: Point) {
        guard toilets.indices.contains(i), let r = againstWall(at: p, widthFt: 20.0 / 12, depthFt: 28.0 / 12) else { return }
        toilets[i] = r
    }

    /// A toilet where a tap puts it: 20″ × 28″, its tank against the nearest wall.
    mutating func addToilet(at p: Point) {
        if let r = againstWall(at: p, widthFt: 20.0 / 12, depthFt: 28.0 / 12) { toilets.append(r) }
    }

    /// The walls a vanity touches (its back, and an end against a wall).
    func wallsTouching(_ v: Vanity) -> [Wall] {
        var seen = Set<UUID>()
        return AreaTakeoff.tubEdgeWalls(v.rect.corners, in: self).compactMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    /// The top: the cabinet plus its overhang on each open side.
    func vanityTop(_ v: Vanity) -> AreaTakeoff.FloorRect {
        var r = v.rect
        let walls = AreaTakeoff.tubEdgeWalls(r.corners, in: self)
        guard walls.count == 4 else { return r }
        let o = v.overhangIn / 12, open = walls.map { $0 == nil }
        let du0 = open[3] ? o : 0, du1 = open[1] ? o : 0, dv0 = open[0] ? o : 0, dv1 = open[2] ? o : 0
        r.origin = .init(x: r.origin.x - r.u.x * du0 - r.v.x * dv0, y: r.origin.y - r.u.y * du0 - r.v.y * dv0)
        r.widthFt += du0 + du1
        r.depthFt += dv0 + dv1
        return r
    }

    /// The backsplash on each wall it's on: the wall, and its stretch along
    /// the top there.
    func vanitySplash(_ v: Vanity) -> [(wall: Wall, span: ClosedRange<Double>)] {
        guard v.splash != .none else { return [] }
        let spans = AreaTakeoff.tubSpans(vanityTop(v).corners, in: self)
        return wallsTouching(v).compactMap { w in
            guard v.splashWalls.contains(w.id), let s = spans[w.id] else { return nil }
            return (w, s)
        }
    }

    /// The top's square feet, and the backsplash's linear and square feet.
    func vanityMeasures(_ v: Vanity) -> (topSqft: Double, splashFt: Double, splashSqft: Double) {
        let t = vanityTop(v)
        let ft = vanitySplash(v).reduce(0.0) { $0 + $1.span.upperBound - $1.span.lowerBound }
        return (t.widthFt * t.depthFt, ft, ft * v.splashHeightIn / 12)
    }
}

extension ScannedRoom.Vanity {
    /// Sinks as sized (1, or 2 from 60″ wide), unless typed.
    mutating func fitSinks() {
        if !sinksTyped { sinks = rect.widthFt >= 5 - 1e-9 ? 2 : 1 }
    }
}

extension AreaTakeoff {
    /// A vanity's stone backsplash pieces, for its area (`trimEntries`).
    func vanityEntries(in room: ScannedRoom) -> [(String, TrimKind, String, Double)] {
        guard let v = room.vanity(vanityID), v.splash == .stone else { return [] }
        return room.vanitySplash(v).map { s in
            ("vanity:splash:\(s.wall.id.uuidString)", .vanity, "Vanity backsplash (\(room.name(of: s.wall)))",
             s.span.upperBound - s.span.lowerBound)
        }
    }

    /// The vanity's top to order: one slab, the cabinet plus its overhang
    /// (sinks cut at fabrication).
    func vanityCutPieces(in room: ScannedRoom) -> [CutPiece] {
        guard let v = room.vanity(vanityID) else { return [] }
        let t = room.vanityTop(v)
        return [CutPiece(key: "vanity:top", id: "vanity:top#\(v.id.uuidString)#Top#", family: "Vanity", object: v.id.uuidString,
                         objectOrder: 0, part: "Top", side: nil, type: StonePart.vanityTop.rawValue, group: StoneGroup.vanity.title,
                         lengthIn: t.widthFt * 12, widthIn: t.depthFt * 12, thickness: .threeCm, quantity: 1)]
    }
}

extension EstimateRoom {
    /// Each of the room's vanities has its own area, a Backsplash named
    /// Vanity, made when the vanity is added and gone with it; each is
    /// measured again as the vanity changes, and its tile is kept on the
    /// vanity for drawing (owner, 2026-10-19).
    mutating func syncVanities(prices: StonePrices) {
        guard var scan else { return }
        let ids = Set(scan.vanities.map(\.id))
        sections.removeAll { s in s.scanTakeoff?.vanityID.map { !ids.contains($0) } ?? false }
        for i in scan.vanities.indices {
            let v = scan.vanities[i]
            if let k = sections.firstIndex(where: { $0.scanTakeoff?.vanityID == v.id }) {
                if let t = sections[k].scanTakeoff { t.apply(scan, to: &sections[k], prices: prices) }
                scan.vanities[i].splashTile = sections[k].mainTile
            } else {
                var s = EstimateSection()
                s.area = .backsplash
                s.startWithUsualTile()
                var t = AreaTakeoff()
                t.vanityID = v.id
                t.floor = .none
                t.apply(scan, to: &s, prices: prices)
                sections.append(s)
                scan.vanities[i].splashTile = s.mainTile
            }
        }
        if scan != self.scan { self.scan = scan }
    }
}
