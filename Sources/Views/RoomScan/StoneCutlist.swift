import Foundation

/// One stone piece to order, as it goes on the cutlist (owner, 2026-10-16):
/// sized to order — long, trimmed at fabrication — named without sizes.
///
/// The sizes (all from the model, inches):
/// - Curb top: from the wall's face along the curb; at a corner of two
///   curbs it runs on through the other curb (4½″) and past its overhang to
///   the far edge of the other top. Width from Admin (else the curb's 4½″).
/// - Curb faces: the curb's length; an outside face at a corner also runs
///   past the other outside face's thickness. Height from Admin (else the
///   curb's height). Inside faces: the curb's length.
/// - Jambs (entry, door, window, niche): full height. Headers, sills and
///   niche shelves: full width. Widths from Admin (else the wall's
///   thickness; a niche's depth, less a stone back's thickness).
/// - Wall cap: the half wall's length plus ¾″ past each free end.
/// - Framed bench: front length × height, end depth × height; the top the
///   bench plus the front's (and end's) thickness — ¾″ when tile — plus the
///   overhang (Admin, ¾″). A floating bench's top: wall to wall × its depth.
/// - Ceiling headers and dropped headers: wall to wall × Admin's width.
/// - Corner shelves, seats and footrests: right triangles, legs its size.
struct CutPiece: Equatable {
    enum Shape: String, Codable { case rectangle, rightTriangle }

    /// The stone choice it comes from (`TrimPiece.key`), "" for corner pieces.
    var key: String
    /// Unique within the area.
    var id: String
    /// What it belongs to, for naming: "Curb", "Niche", "Half Wall"…
    var family: String
    /// Which one of the family (for letters), and its order (first added first).
    var object: String
    var objectOrder: Int
    /// Its part: "Top", "Jamb"; `side` ("Left"/"Right") when a pair.
    var part: String
    var side: String? = nil
    var type: String
    var group: String
    var shape: Shape = .rectangle
    var lengthIn: Double
    var widthIn: Double
    var thickness: StoneThickness
    /// "standard": every edge finished with the shop's standard edge, no
    /// profile (owner, 2026-10-17); a profile's own name if TileRate gets them.
    var edges = "standard"
    var quantity = 1
    /// Filled in by `cutlist`: "Curb A Top", "Niche Jambs".
    var name = ""
}

extension AreaTakeoff {
    /// The pieces to order for each stone choice of this area, keyed by
    /// `TrimPiece.key` (every choice, stone or not, so prices can follow).
    func cutPieces(entries: [(key: String, kind: TrimKind, name: String, ft: Double)], in room: ScannedRoom,
                   area: Area?, curbHeightIn: Double, prices: StonePrices) -> [String: [CutPiece]] {
        let cw = prices.curbWidthFt * 12
        let curbH = curbless ? 0 : (self.curbHeightIn ?? curbHeightIn)
        func rate(_ p: StonePart) -> StoneRate { prices.rate(p) }
        func width(_ p: StonePart, else fallback: Double) -> Double { rate(p).widthIn > 0 ? rate(p).widthIn : fallback }
        func thick(_ p: StonePart) -> StoneThickness { rate(p).thickness ?? (p == .nicheBack ? .twoCm : .threeCm) }
        func isStone(_ key: String) -> Bool { trim.first { $0.key == key }?.stone ?? false }
        func wallThick(_ id: UUID?) -> Double {
            id.flatMap { room.wall($0) }.map { Self.drawnThicknessFt($0) * 12 } ?? 4.5
        }
        func r16(_ v: Double) -> Double { (v * 16).rounded() / 16 }
        var out: [String: [CutPiece]] = [:]
        func add(_ key: String, _ p: CutPiece) {
            var p = p
            p.lengthIn = r16(max(0, p.lengthIn)); p.widthIn = r16(max(0, p.widthIn))
            p.id = "\(p.id)"
            out[key, default: []].append(p)
        }

        // The curb's runs, and which of their ends turn a corner into another run.
        let stretches = (area == .shower && floor == .drawn) ? curbSides(in: room).stretches : []
        func cornerEnds(_ i: Int) -> Int {
            let (a, b) = stretches[i]
            let da = ScannedRoom.Point(x: b.x - a.x, y: b.y - a.y), la = max(hypot(da.x, da.y), 1e-9)
            var n = 0
            for end in [a, b] {
                n += stretches.indices.contains { j in
                    guard j != i else { return false }
                    let (c, d) = stretches[j]
                    let touches = hypot(c.x - end.x, c.y - end.y) < 0.05 || hypot(d.x - end.x, d.y - end.y) < 0.05
                    let dj = ScannedRoom.Point(x: d.x - c.x, y: d.y - c.y), lj = max(hypot(dj.x, dj.y), 1e-9)
                    return touches && abs((da.x * dj.x + da.y * dj.y) / (la * lj)) < 0.5
                } ? 1 : 0
            }
            return n
        }
        let benchesAtEntry = Set((area == .shower && floor == .drawn) ? curbSides(in: room).benches.map(\.id) : [])
        let kneeWalls = room.walls.filter { room.isKneeWall($0) }
        // Doors and windows, in order: the shower's doors, then the room's own
        // (by wall letter, then along the wall); windows the scan has, then
        // those placed on the model.
        let roomOpenings = stoneOpenings(in: room).sorted { a, b in
            let la = a.wallID.flatMap { room.wall($0)?.label } ?? "", lb = b.wallID.flatMap { room.wall($0)?.label } ?? ""
            return la != lb ? la < lb : room.span(of: a).lowerBound < room.span(of: b).lowerBound
        }
        let doorOrder = showerDoors(in: room).map(\.id) + roomOpenings.filter { $0.kind != .window }.map(\.id)
        let windowOrder = roomOpenings.filter { $0.kind == .window }.map(\.id.uuidString)
            + items.filter { $0.kind == .window }.map(\.id.uuidString)
        let nicheOrder = items.filter { $0.kind == .niche }.map(\.id)
        let benchOrder = items.filter(\.kind.isBench).map(\.id)

        for e in entries {
            let parts = e.key.split(separator: ":").map(String.init)
            let item = items.first { e.key.contains($0.id.uuidString) }
            let ft = e.ft * 12
            func piece(_ family: String, _ object: String, _ order: Int, _ part: String, side: String? = nil,
                       _ type: StonePart, length: Double, width: Double, qty: Int = 1, thickness: StoneThickness? = nil) -> CutPiece {
                CutPiece(key: e.key, id: "\(e.key)#\(object)#\(part)#\(side ?? "")", family: family, object: object, objectOrder: order,
                         part: part, side: side, type: type.rawValue, group: type.group.title,
                         lengthIn: length, widthIn: width, thickness: thickness ?? thick(type), quantity: qty)
            }

            // The shower's curb, a piece per run.
            if e.key == "curb" || e.key == "curb:inside" || e.key == "curb:outside" {
                let topW = width(.curbTop, else: cw), over = max(0, (topW - cw) / 2)
                for (i, s) in stretches.enumerated() {
                    let l = hypot(s.1.x - s.0.x, s.1.y - s.0.y) * 12, corners = Double(cornerEnds(i))
                    switch e.key {
                    case "curb":
                        add(e.key, piece("Curb", "\(i)", i, "Top", .curbTop, length: l + corners * (cw + over), width: topW))
                    case "curb:inside":
                        add(e.key, piece("Curb", "\(i)", i, "Inside Face", .curbInside, length: l, width: width(.curbInside, else: curbH)))
                    default:
                        add(e.key, piece("Curb", "\(i)", i, "Outside Face", .curbOutside,
                                         length: l + corners * (cw + thick(.curbOutside).inches), width: width(.curbOutside, else: curbH)))
                    }
                }
                continue
            }
            // A shower door's curb, jambs and header; the room's doors and openings.
            if parts.count >= 2, let did = UUID(uuidString: parts[1]), let d = room.openings.first(where: { $0.id == did }) {
                let family = d.kind == .opening ? "Opening" : "Door"
                let order = doorOrder.firstIndex(of: did) ?? 99
                let wt = wallThick(d.wallID)
                let s = room.span(of: d), w = (s.upperBound - s.lowerBound) * 12
                if d.kind == .window {
                    let wo = windowOrder.firstIndex(of: d.id.uuidString) ?? 99
                    switch parts.last {
                    case "sill": add(e.key, piece("Window", d.id.uuidString, wo, "Sill", .windowSill, length: w, width: width(.windowSill, else: wt)))
                    case "header": add(e.key, piece("Window", d.id.uuidString, wo, "Header", .windowHeader, length: w, width: width(.windowHeader, else: wt)))
                    default: add(e.key, piece("Window", d.id.uuidString, wo, "Jamb", .windowJamb, length: d.heightFt * 12,
                                               width: width(.windowJamb, else: wt), qty: 2))
                    }
                    continue
                }
                switch parts[0] {
                case "curb":
                    let topW = width(.curbTop, else: cw)
                    if parts.last == "inside" {
                        add(e.key, piece(family, did.uuidString, order, "Curb Inside Face", .curbInside, length: w, width: width(.curbInside, else: curbH)))
                    } else if parts.last == "outside" {
                        add(e.key, piece(family, did.uuidString, order, "Curb Outside Face", .curbOutside, length: w, width: width(.curbOutside, else: curbH)))
                    } else {
                        add(e.key, piece(family, did.uuidString, order, "Curb Top", .curbTop, length: w, width: topW))
                    }
                case "jamb":
                    add(e.key, piece(family, did.uuidString, order, "Jamb", side: parts.last?.capitalized, .doorJamb,
                                     length: ft, width: width(.doorJamb, else: wt)))
                case "header":
                    add(e.key, piece(family, did.uuidString, order, "Header", .doorHeader, length: w, width: width(.doorHeader, else: wt)))
                default: break
                }
                continue
            }
            // A niche's or window's parts, placed on the model.
            if let i = item, i.kind == .niche || i.kind == .window {
                let w = i.widthFt * 12, h = i.heightIn
                if i.kind == .window {
                    let wo = windowOrder.firstIndex(of: i.id.uuidString) ?? 99, wt = wallThick(i.wallID)
                    switch parts.last {
                    case "sill": add(e.key, piece("Window", i.id.uuidString, wo, "Sill", .windowSill, length: w, width: width(.windowSill, else: wt)))
                    case "header": add(e.key, piece("Window", i.id.uuidString, wo, "Header", .windowHeader, length: w, width: width(.windowHeader, else: wt)))
                    default: add(e.key, piece("Window", i.id.uuidString, wo, "Jamb", .windowJamb, length: h, width: width(.windowJamb, else: wt), qty: 2))
                    }
                } else {
                    let o = nicheOrder.firstIndex(of: i.id) ?? 99
                    let back = partStone(i, "back") ? thick(.nicheBack).inches : 0
                    func depth(_ p: StonePart) -> Double { width(p, else: Self.nicheDepthIn) - back }
                    switch parts.last {
                    case "back": add(e.key, piece("Niche", i.id.uuidString, o, "Back", .nicheBack, length: w, width: h))
                    case "shelf": add(e.key, piece("Niche", i.id.uuidString, o, "Base Shelf", .nicheShelf, length: w, width: depth(.nicheShelf)))
                    case "header": add(e.key, piece("Niche", i.id.uuidString, o, "Header", .nicheHeader, length: w, width: depth(.nicheHeader)))
                    case "dividers":
                        add(e.key, piece("Niche", i.id.uuidString, o, i.dividers == 1 ? "Divider Shelf" : "Divider Shelves", .nicheDivider,
                                         length: w, width: depth(.nicheDivider), qty: max(1, i.dividers)))
                    default: add(e.key, piece("Niche", i.id.uuidString, o, "Jamb", .nicheJamb, length: h, width: depth(.nicheJamb), qty: 2))
                    }
                }
                continue
            }
            // Benches.
            if let b = item, b.kind.isBench {
                let o = benchOrder.firstIndex(of: b.id) ?? 99
                let len = b.widthFt * 12
                switch parts[0] {
                case "benchTop":
                    if b.kind == .floatingBench {
                        add(e.key, piece("Bench", b.id.uuidString, o, "Top", .floatingBenchTop, length: len, width: b.depthIn))
                    } else {
                        let over = prices.benchOverhangIn
                        let front = isStone("benchFront:\(b.id)") ? thick(.framedBenchFront).inches : 0.75
                        let end = benchesAtEntry.contains(b.id)
                            ? (isStone("benchSide:\(b.id)") ? thick(.framedBenchSide).inches : 0.75) + over : 0
                        add(e.key, piece("Bench", b.id.uuidString, o, "Top", .framedBenchTop, length: len + end,
                                         width: b.depthIn + front + over))
                    }
                case "benchFront":
                    add(e.key, piece("Bench", b.id.uuidString, o, "Front", .framedBenchFront, length: len, width: b.heightIn))
                case "benchSide":
                    add(e.key, piece("Bench", b.id.uuidString, o, "End", .framedBenchSide, length: b.depthIn, width: b.heightIn))
                default: break
                }
                continue
            }
            // Half walls: caps, ends, and the ceiling headers over them.
            if parts.count >= 2, let wid = UUID(uuidString: parts[parts[0] == "header" ? 2 % parts.count : 1]),
               let w = kneeWalls.first(where: { $0.id == wid }) {
                let o = room.walls.firstIndex { $0.id == w.id } ?? 99
                let wt = Self.drawnThicknessFt(w) * 12
                switch parts[0] {
                case "cap":
                    let free = [true, false].filter { room.isFreeEnd(of: w, start: $0) }.count
                    add(e.key, piece("Half Wall", w.id.uuidString, o, "Cap", .wallCap,
                                     length: w.lengthFt * 12 + Double(free) * 0.75, width: width(.wallCap, else: wt)))
                case "header":
                    add(e.key, piece("Half Wall", w.id.uuidString, o, "Ceiling Header", .ceilingHeader,
                                     length: w.lengthFt * 12, width: width(.ceilingHeader, else: cw)))
                default:
                    add(e.key, piece("Half Wall", w.id.uuidString, o, "End", .wallJamb, length: w.heightFt * 12, width: width(.wallJamb, else: wt)))
                }
                continue
            }
            // The ceiling header over the curb, a piece per run, meeting at a corner.
            if e.key == "header:ceiling" {
                let hw = width(.ceilingHeader, else: cw)
                for (i, s) in stretches.enumerated() {
                    let l = hypot(s.1.x - s.0.x, s.1.y - s.0.y) * 12
                    add(e.key, piece("Ceiling Header", "\(i)", i, "", .ceilingHeader,
                                     length: l + Double(cornerEnds(i)) * (cw / 2 + hw / 2), width: hw))
                }
                continue
            }
            // A dropped header's underside.
            if parts[0] == "soffit" {
                let o = soffits.firstIndex { $0.id.uuidString == parts.last } ?? 99
                add(e.key, piece("Dropped Header", parts.last ?? "", o, "Underside", .ceilingHeader, length: ft, width: width(.ceilingHeader, else: cw)))
                continue
            }
            // The shower entry's jambs: left and right, lower and upper.
            if parts[0] == "jamb", parts.count >= 2 {
                let side = parts[1].capitalized
                let level = parts.contains("lower") ? "Lower Jamb" : parts.contains("upper") ? "Upper Jamb" : "Jamb"
                add(e.key, piece("Entry", "entry", 0, level, side: side, .wallJamb, length: ft, width: width(.wallJamb, else: cw)))
                continue
            }
            // A half wall's free end at the entry ("kneeEnd:<wall>:start").
            if parts[0] == "kneeEnd", parts.count >= 2, let w = room.wall(UUID(uuidString: parts[1]) ?? UUID()) {
                let o = room.walls.firstIndex { $0.id == w.id } ?? 99
                add(e.key, piece("Half Wall", w.id.uuidString, o, "End", .wallJamb, length: w.heightFt * 12,
                                 width: width(.wallJamb, else: Self.drawnThicknessFt(w) * 12)))
            }
        }
        return out
    }

    /// Corner shelves, seats and footrests: always stone, right triangles.
    func cornerCutPieces(in room: ScannedRoom) -> [CutPiece] {
        items.enumerated().filter { $0.element.kind.isCorner }.map { n, i in
            let family = i.kind == .cornerShelf ? "Corner Shelf" : i.kind == .cornerSeat ? "Corner Seat" : "Corner Footrest"
            return CutPiece(key: "", id: "corner#\(i.id)", family: family, object: i.id.uuidString, objectOrder: n,
                            part: "", type: i.kind.rawValue, group: "Corner pieces", shape: .rightTriangle,
                            lengthIn: (i.sizeIn * 16).rounded() / 16, widthIn: (i.sizeIn * 16).rounded() / 16,
                            thickness: .threeCm)
        }
    }

    /// This area's stone pieces to order, named (owner, 2026-10-16): no
    /// sizes in names; a letter by the order things were added when there's
    /// more than one ("Niche A Jambs", "Curb B Top"); a matching left and
    /// right as one row with a quantity ("Entry Jambs"), else each its own
    /// ("Entry Left Jamb"); identical corner pieces as one row.
    func cutlist(in room: ScannedRoom, area: Area?, curbHeightIn: Double, prices: StonePrices) -> [CutPiece] {
        let stone = trimPieces(in: room, area: area, curbHeightIn: curbHeightIn, prices: prices).filter { $0.stone && $0.lengthFt > 0.01 }
        var pieces = stone.flatMap { p -> [CutPiece] in
            var cuts = p.cuts
            // A length typed over the measured one: a single piece takes it.
            if cuts.count == 1, cuts[0].quantity == 1, abs(p.lengthFt - p.measuredFt) > 0.01 { cuts[0].lengthIn = p.lengthFt * 12 }
            return cuts
        }
        pieces += cornerCutPieces(in: room)
        return Self.named(pieces)
    }

    static func named(_ pieces: [CutPiece]) -> [CutPiece] {
        // Merge a matching left and right (and identical corner pieces).
        var merged: [CutPiece] = []
        func same(_ a: CutPiece, _ b: CutPiece) -> Bool {
            a.family == b.family && a.part == b.part && a.type == b.type && a.shape == b.shape
                && a.lengthIn == b.lengthIn && a.widthIn == b.widthIn && a.thickness == b.thickness && a.edges == b.edges
        }
        for p in pieces {
            if p.side != nil, let i = merged.firstIndex(where: { $0.object == p.object && $0.side != nil && same($0, p) }) {
                merged[i].quantity += p.quantity
                merged[i].side = nil
                continue
            }
            if p.group == "Corner pieces", let i = merged.firstIndex(where: { $0.group == "Corner pieces" && same($0, p) }) {
                merged[i].quantity += p.quantity
                continue
            }
            merged.append(p)
        }
        // Letters, per family, when it has more than one of a thing.
        var letters: [String: [String: String]] = [:]
        for family in Set(merged.map(\.family)) {
            let objects = merged.filter { $0.family == family }
            let ordered = Array(Set(objects.map(\.object))).sorted { a, b in
                let oa = objects.first { $0.object == a }!.objectOrder, ob = objects.first { $0.object == b }!.objectOrder
                return oa != ob ? oa < ob : a < b
            }
            guard ordered.count > 1 else { continue }
            letters[family] = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, Self.letter($0)) })
        }
        return merged.map { p in
            var p = p
            var part = p.part
            if let side = p.side { part = "\(side) \(part)" } else if p.quantity > 1, !part.isEmpty, !part.hasSuffix("s") { part += "s" }
            p.name = [p.family, letters[p.family]?[p.object] ?? "", part].filter { !$0.isEmpty }.joined(separator: " ")
            if p.group == "Corner pieces", p.quantity > 1, letters[p.family] == nil { p.name = p.family == "Corner Shelf" ? "Corner Shelves" : p.family + "s" }
            return p
        }
    }

    static func letter(_ n: Int) -> String {
        let a = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return n < 26 ? String(a[n]) : String(a[n / 26 - 1]) + String(a[n % 26])
    }
}
