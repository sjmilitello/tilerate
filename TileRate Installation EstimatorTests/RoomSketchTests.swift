import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Rooms sketched by hand, and new rooms' areas placed on the model
/// (owner, 2026-10-12).
struct RoomSketchTests {
    @Test func rectangleMakesFourWallsAtTheCeilingAndItsFloor() {
        let r = RoomSketch.room(.rectangle, .init(widthIn: 96, depthIn: 120, ceilingIn: 96))
        #expect(r.sketched)
        #expect(r.walls.count == 4)
        #expect(Set(r.walls.map(\.label)) == ["A", "B", "C", "D"])
        #expect(r.walls.allSatisfy { abs($0.heightFt - 8) < 1e-9 })
        #expect(abs(r.floorSqft - 80) < 1e-9)
        #expect(abs(r.walls.map(\.lengthFt).reduce(0, +) - 36) < 1e-9)
    }

    @Test func lShapeLosesItsCorner() {
        let s = RoomSketch.Sides(widthIn: 120, depthIn: 120, cutWidthIn: 48, cutDepthIn: 60, ceilingIn: 96)
        #expect(RoomSketch.valid(.lShape, s))
        let r = RoomSketch.room(.lShape, s)
        #expect(r.walls.count == 6)
        #expect(abs(r.floorSqft - (100 - 4 * 5)) < 1e-9)
        #expect(!RoomSketch.valid(.lShape, .init(widthIn: 120, depthIn: 120, cutWidthIn: 120, cutDepthIn: 60)))
    }

    @Test func sketchedFlagIsSavedAndOldScansReadWithout() throws {
        let r = RoomSketch.room(.rectangle, .init())
        let back = try JSONDecoder().decode(ScannedRoom.self, from: JSONEncoder().encode(r))
        #expect(back.sketched)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ScannedRoom.sample)) as! [String: Any]
        old.removeValue(forKey: "sketched")
        let read = try JSONDecoder().decode(ScannedRoom.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(!read.sketched)
    }

    @Test func newAreasArePlacedWhereTheModelSuggests() {
        var room = EstimateRoom(name: "Bath")
        room.scan = ScannedRoom.sample
        room.sections = [Area.floor, .tub, .backsplash, .wall].map { a in
            var s = EstimateSection(); s.area = a; s.startWithUsualTile(); return s
        }
        room.placeAreas(room.sections.map(\.id), prices: StonePrices())
        let floor = room.sections[0], tub = room.sections[1], splash = room.sections[2], wall = room.sections[3]
        #expect(floor.scanTakeoff?.floor == .room)
        #expect(floor.measurements.sqft > 0)
        #expect(tub.scanTakeoff?.pieces.isEmpty == false)
        #expect(splash.scanTakeoff?.pieces.count == 1)
        #expect(wall.scanTakeoff?.pieces.isEmpty != false)
    }
}

struct GuidedOrderTests {
    @Test func showersThenTubsComeBeforeTheFloor() {
        #expect(NewEstimateView.showersFirst([.floor, .backsplash, .tub, .shower, .shower])
                == [.shower, .shower, .tub, .floor, .backsplash])
    }
}

struct CurbCornerTests {
    /// A corner shower's two curb runs overlap at the outside corner
    /// (owner, 2026-10-12), and its linear feet don't change.
    @Test func cornerShowerCurbsOverlapOutsideTheCorner() {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        let placed = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        #expect(placed)
        let w = 4.5 / 12
        let edges = t.curbEdges(in: room)
        let runs = t.curbRuns(in: room, widthFt: w)
        #expect(edges.count == 2 && runs.count == 2)
        let raw = edges.reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        let drawn = runs.reduce(0) { $0 + hypot($1.b.x - $1.a.x, $1.b.y - $1.a.y) }
        #expect(abs(drawn - raw - w) < 1e-9)
        // The corner square outside the floor's corner is covered.
        guard let r = t.floorRect else { Issue.record("no floor"); return }
        let corner = r.corners.min { hypot($0.x - 5, $0.y - 5) < hypot($1.x - 5, $1.y - 5) }!
        let out = ScannedRoom.Point(x: corner.x - w / 2, y: corner.y - w / 2)
        let covered = runs.contains { run in
            let len = hypot(run.b.x - run.a.x, run.b.y - run.a.y)
            let u = ScannedRoom.Point(x: (run.b.x - run.a.x) / len, y: (run.b.y - run.a.y) / len)
            let along = (out.x - run.a.x) * u.x + (out.y - run.a.y) * u.y
            let across = abs((out.x - run.a.x) * -u.y + (out.y - run.a.y) * u.x)
            return along > 0 && along < len && across < w
        }
        #expect(covered)
    }
}

struct WallTileToCurbTests {
    /// A corner shower's wall tile runs on to the curb's outside edge
    /// (owner, 2026-10-13); curbless, it stops at the floor.
    @Test func cornerShowerWallTileReachesTheCurbsOutsideEdge() {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        let placed = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        #expect(placed)
        let r = t.floorRect!
        #expect(t.pieces.count == 2)
        for p in t.pieces {
            let floorSide = abs(r.widthFt - 4) < 1e-6 ? 4.0 : r.widthFt
            #expect(abs((p.toFt - p.fromFt) - (floorSide + 4.5 / 12)) < 1e-6)
        }
        var curbless = t
        curbless.curbless = true
        curbless.tileWallsAroundFloor(in: room)
        for p in curbless.pieces { #expect(abs((p.toFt - p.fromFt) - 4) < 1e-6) }
    }
}

struct WallOnCurbTests {
    /// A wall put on a corner shower's curb runs along the curb's middle
    /// and out to its outside corner (owner, 2026-10-13).
    @Test func wallOnACornerShowersCurbLinesUpWithItAndReachesItsEnd() {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        let placed = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        #expect(placed)
        let w = 4.5 / 12
        let sides = t.openSides(in: room)
        #expect(sides.count == 2)
        let side = sides[0]
        let (a, b) = t.wallOnCurb(side, in: room, curbWidthFt: w)
        // As long as the side plus the curb's width (to the outside corner).
        #expect(abs(hypot(b.x - a.x, b.y - a.y) - (side.lengthFt + w)) < 1e-9)
        // Half the curb's width outside the floor's edge, all along.
        let r = t.floorRect!
        let c = r.corners
        let wm = ScannedRoom.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        // Distance from the floor's edge line to the wall's line is w/2.
        let l = side.lengthFt
        let n = ScannedRoom.Point(x: -(side.b.y - side.a.y) / l, y: (side.b.x - side.a.x) / l)
        #expect(abs(abs((a.x - side.a.x) * n.x + (a.y - side.a.y) * n.y) - w / 2) < 1e-9)
        #expect(abs(abs((b.x - side.a.x) * n.x + (b.y - side.a.y) * n.y) - w / 2) < 1e-9)
        // Outside the floor, not inside it.
        #expect(!AreaTakeoff.inside(c, wm))
        // Curbless: on the floor's edge, its length.
        let (ca, cb) = t.wallOnCurb(side, in: room, curbWidthFt: 0)
        #expect(abs(hypot(cb.x - ca.x, cb.y - ca.y) - side.lengthFt) < 1e-9)
    }
}

struct JambFaceTests {
    /// Every jamb drawn is a jamb priced, keyed the same (owner, 2026-10-13).
    @Test func threeWallShowerJambsAreDrawnWhereTheyArePriced() {
        var room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        let placed = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        #expect(placed)
        // A full wall on one curb: a three-wall shower.
        let side = t.openSides(in: room)[0]
        let (a, b) = t.wallOnCurb(side, in: room, curbWidthFt: 4.5 / 12)
        _ = room.addPlannedWall(from: a, to: b, heightIn: 96, thicknessIn: 4.5)
        let priced = Set(t.trimPieces(in: room, area: .shower, curbHeightIn: 4).filter { $0.kind == .jamb }.map(\.key))
        let drawn = t.jambFaces(in: room, curbHeightIn: 4)
        #expect(drawn.count == 2)
        #expect(Set(drawn.map(\.key)) == priced)
        for f in drawn {
            #expect(abs(f.bottomFt - 4.0 / 12) < 1e-9)
            #expect(f.topFt > 7.9)
        }
    }
}

struct HalfWallJambTests {
    /// Corner shower, half wall on one curb: lower jamb on its face, upper
    /// on the back wall above the cap, and its free end a piece floor to
    /// cap at the jamb price (owner, 2026-10-13).
    @Test func cornerShowerHalfWallOnACurb() {
        var room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        let placed = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        #expect(placed)
        let side = t.openSides(in: room)[0]
        let (a, b) = t.wallOnCurb(side, in: room, curbWidthFt: 4.5 / 12)
        let half = room.addPlannedWall(from: a, to: b, heightIn: 42, thicknessIn: 4.5)
        #expect(room.isKneeWall(half))
        let pieces = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        let jambs = pieces.filter { $0.kind == .jamb }
        let keys = Set(jambs.map(\.key))
        #expect(keys.contains { $0.hasSuffix(":lower") } && keys.contains { $0.hasSuffix(":upper") })
        let end = jambs.first { $0.key.hasPrefix("kneeEnd:") }
        #expect(abs((end?.lengthFt ?? 0) - 3.5) < 1e-9)   // floor to cap: 42″
        // Every piece priced is drawn, and nothing else.
        let drawn = t.jambFaces(in: room, curbHeightIn: 4)
        #expect(Set(drawn.map(\.key)) == keys)
        // The upper jamb stands on the back wall at the half wall's attached end, above the cap.
        let upper = drawn.first { $0.key.hasSuffix(":upper") }!
        #expect(abs(upper.bottomFt - 3.5) < 1e-9)
        let attached = room.isFreeEnd(of: half, start: true) ? half.end : half.start
        #expect(hypot(upper.center.x - attached.x, upper.center.y - attached.y) < 0.2)
        // The end is at the half wall's free end, floor to cap.
        let free = room.isFreeEnd(of: half, start: true) ? half.start : half.end
        let e = drawn.first { $0.key.hasPrefix("kneeEnd:") }!
        #expect(hypot(e.center.x - free.x, e.center.y - free.y) < 1e-9 && e.bottomFt == 0 && abs(e.topFt - 3.5) < 1e-9)
    }
}

struct DoorAndHeaderTests {
    /// A door's jambs and header, and the ceiling headers over the curb and
    /// half wall caps, are drawn where they're priced (owner, 2026-10-13).
    @Test func doorJambsHeaderAndCeilingHeadersMatchTheirPrices() {
        var room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        let placed = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        #expect(placed)
        let sides = t.openSides(in: room)
        // A full wall with a door on one curb, a half wall on the other.
        let (a, b) = t.wallOnCurb(sides[0], in: room, curbWidthFt: 4.5 / 12)
        let full = room.addPlannedWall(from: a, to: b, heightIn: 96, thicknessIn: 4.5)
        _ = room.addShowerDoor(on: full, along: full.lengthFt / 2, widthIn: 30, heightIn: 80)
        t.pieces.append(.init(wallID: full.id, fromFt: 0, toFt: full.lengthFt, heightIn: 96))
        let priced = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        let keys = Set(priced.map(\.key))
        let drawn = t.doorAndHeaderFaces(in: room, curbHeightIn: 4)
        // Two door jambs and the door header.
        #expect(drawn.jambs.count == 2)
        #expect(Set(drawn.jambs.map(\.key)).isSubset(of: keys))
        #expect(drawn.headers.contains { $0.key.hasPrefix("header:") && !$0.key.hasPrefix("header:ceiling") })
        // The ceiling header over the curb, priced as a header.
        #expect(keys.contains("header:ceiling"))
        #expect(drawn.headers.contains { $0.key == "header:ceiling" })
        #expect(Set(drawn.headers.map(\.key)).isSubset(of: keys))
        // Stone: on the cap & header line, named for headers.
        t.trim = [.init(key: "header:ceiling", stone: true)]
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        t.apply(room, to: &s, prices: StonePrices(curb: 30, cap: 25, jamb: 20, curbHeightIn: 4))
        #expect(s.additionsLabor.contains { $0.activity == "Stone ceiling header" })
    }
}

/// Stone pieces priced by part, one line per group, with the stone material
/// in it or on its own line (owner, 2026-10-13).
struct StonePartPricingTests {
    func cornerShower() -> (ScannedRoom, AreaTakeoff) {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        _ = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        return (room, t)
    }

    @Test func oldPricesCarryOverToEveryPart() {
        var r = Rates()
        r.stoneCurbPerLinFt = 30
        r.stoneCapPerLinFt = 25
        r.stoneJambPerLinFt = 20
        r.setStoneRate(StoneRate(perLinFt: 40), for: StoneItem.niche)
        #expect(r.stoneRate(.curbTop).perLinFt == 30 && r.stoneRate(.curbOutside).perLinFt == 30)
        #expect(r.stoneRate(.wallCap).perLinFt == 25 && r.stoneRate(.doorHeader).perLinFt == 25 && r.stoneRate(.ceilingHeader).perLinFt == 25)
        #expect(r.stoneRate(.wallJamb).perLinFt == 20 && r.stoneRate(.doorJamb).perLinFt == 20)
        #expect(r.stoneRate(.nicheDivider).perLinFt == 40)
        // A part's own price, once set, is its own.
        r.setStoneRate(StoneRate(perLinFt: 33), for: .curbInside)
        #expect(r.stoneRate(.curbInside).perLinFt == 33 && r.stoneRate(.curbTop).perLinFt == 30)
    }

    @Test func eachPartAtItsOwnPriceOnTheGroupsLine() {
        let (room, base) = cornerShower()
        var t = base
        t.trim = [.init(key: "curb", stone: true), .init(key: "curb:outside", stone: true)]
        var prices = StonePrices()
        prices.parts[.curbTop] = StoneRate(perLinFt: 30)
        prices.parts[.curbOutside] = StoneRate(perLinFt: 10)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        t.apply(room, to: &s, prices: prices)
        let curb = s.additionsLabor.first { $0.activity == "Stone curb" }!
        // 8′ of curb top at $30 and 8′ of outside face at $10, one line.
        #expect(abs(curb.amount - (8 * 30 + 8 * 10)) < 0.01)
    }

    @Test func materialIsInTheLineOrOnItsOwn() {
        let (room, base) = cornerShower()
        var t = base
        t.trim = [.init(key: "curb", stone: true)]
        var prices = StonePrices()
        prices.parts[.curbTop] = StoneRate(perLinFt: 30, widthIn: 6)   // 6″ wide: ½ sq ft a foot
        prices.materialPerSqft = 20
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        t.apply(room, to: &s, prices: prices)
        let curb = s.additionsLabor.first { $0.activity == "Stone curb" }!
        #expect(curb.qty == 8 && abs(curb.rate - (30 + 10)) < 1e-9)                 // install + material
        #expect(!s.additionsMaterials.contains { $0.activity == "Stone pieces" })
        prices.materialSeparate = true
        t.apply(room, to: &s, prices: prices)
        let installOnly = s.additionsLabor.first { $0.activity == "Stone curb" }!
        let material = s.additionsMaterials.first { $0.activity == "Stone pieces" }
        #expect(installOnly.qty == 8)
        #expect(material?.qty == 4 && material?.rate == 20 && material?.taxable == true)  // 8′ × 6″ = 4 sq ft
    }

    @Test func aNicheIsItsMinimumPlusItsStoneParts() {
        let (room, base) = cornerShower()
        var t = base
        let wall = room.walls.first { w in t.pieces.contains { $0.wallID == w.id } }!
        t.items = [.init(kind: .niche, wallID: wall.id, fromFt: 0.5, toFt: 1.5, bottomIn: 48, heightIn: 24, dividers: 1, stone: .tile)]
        t.itemsPlaced = true
        let n = t.items[0]
        t.setPartStone(n, "shelf", true)
        t.setPartStone(n, "jambs", true)
        var prices = StonePrices()
        prices.parts[.nicheShelf] = StoneRate(perLinFt: 50)
        prices.parts[.nicheJamb] = StoneRate(perLinFt: 30)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        t.apply(room, to: &s, prices: prices)
        // Stone: 1′ base shelf at $50 and 2 × 2′ jambs at $30, on the niche line.
        let niche = s.additionsLabor.first { $0.activity == "Stone niche" }!
        #expect(abs(niche.amount - (50 + 4 * 30)) < 0.01)
        // The niche itself is its minimum, not the higher of the two.
        var r = Rates()
        r.unitNiche = 300
        let lines = featureLines(s.features, prices: FeaturePrices(rates: r), money: { "\($0)" })
        #expect(lines.first { $0.label.hasPrefix("Niche") }?.amount == 300)
        // The divider stays tile, and its tile is counted inside the niche.
        #expect(!t.partStone(n, "dividers") && !t.partStone(n, "header"))
    }
}

/// A header dropped from the ceiling over the curb (owner, 2026-10-13).
struct SoffitTests {
    @Test func aHeaderOverTheCurbAddsTileStopsTheJambsAndPricesItsUnderside() throws {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        _ = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        let walls = t.wallsSqft(in: room)
        let flat = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        #expect(flat.contains { $0.key == "header:ceiling" })
        #expect(t.soffitTargets(in: room).contains { $0.over == "curb" })

        t.soffits = [.init(over: "curb", dropIn: 6)]
        let lines = t.soffitLines(t.soffits[0], in: room)
        let len = t.soffitLengthFt(t.soffits[0], in: room)
        // Over both curb runs of the corner shower (4′ + 4½″ and 4′), 4½″ wide.
        #expect(lines.count == 2 && lines.allSatisfy { abs($0.widthFt - 4.5 / 12) < 1e-9 })
        #expect(abs(len - (8 + 4.5 / 12)) < 1e-9)
        // Tile: both 6″ faces and the 4½″ underside.
        #expect(abs(t.wallsSqft(in: room) - walls - len * (1 + 4.5 / 12)) < 1e-9)
        // Its underside replaces the flat ceiling header; the jambs stop at it.
        let pieces = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        #expect(!pieces.contains { $0.key == "header:ceiling" })
        let under = try #require(pieces.first { $0.key.hasPrefix("soffit:") })
        #expect(under.part == .ceilingHeader && abs(under.lengthFt - len) < 1e-9)
        for j in pieces where j.kind == .jamb { #expect(abs(j.lengthFt - (7.5 - 4.0 / 12)) < 1e-9) }
        // Stone underside: off the tile, on the ceiling header line.
        t.trim = [.init(key: under.key, stone: true)]
        #expect(abs(t.wallsSqft(in: room) - walls - len) < 1e-9)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        var prices = StonePrices()
        prices.parts[.ceilingHeader] = StoneRate(perLinFt: 40)
        t.apply(room, to: &s, prices: prices)
        let header = try #require(s.additionsLabor.first { $0.activity == "Stone ceiling header" })
        #expect(abs(header.amount - len * 40) < 0.25)   // quantity rounded to the hundredth
    }

    @Test func savedTakeoffsWithoutHeadersStillRead() throws {
        var t = AreaTakeoff()
        t.soffits = [.init(over: "curb", dropIn: 8)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as! [String: Any]
        let back = try JSONDecoder().decode(AreaTakeoff.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.soffits.first?.dropIn == 8)
        json.removeValue(forKey: "soffits")
        let old = try JSONDecoder().decode(AreaTakeoff.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.soffits.isEmpty)
    }
}

struct ExtendTileToCurbTests {
    /// A shower placed before the rule has its wall tile brought out to the
    /// curb's outside edge when opened, once (owner, 2026-10-13).
    @Test func oldShowerTileReachesTheCurbOnce() {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        _ = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        let now = t.wallsSqft(in: room)
        // As placed before: tile stops at the floor.
        var old = t
        for i in old.pieces.indices {
            let len = old.pieces[i].toFt - old.pieces[i].fromFt - 4.5 / 12
            if old.pieces[i].fromFt > 0 { old.pieces[i].fromFt += 4.5 / 12 } else { old.pieces[i].toFt = old.pieces[i].fromFt + len }
        }
        #expect(old.wallsSqft(in: room) < now)
        old.extendTileToCurb(in: room)
        #expect(abs(old.wallsSqft(in: room) - now) < 1e-9)
        let once = old.pieces
        old.extendTileToCurb(in: room)
        #expect(old.pieces == once)
        // Curbless: nothing changes.
        var curbless = t
        curbless.curbless = true
        let before = curbless.pieces
        curbless.extendTileToCurb(in: room)
        #expect(curbless.pieces == before)
    }
}

struct CoveToWallCornerTests {
    /// A shower filled into a cove before the rule is deepened to the walls'
    /// corners when opened, once (owner, 2026-10-13).
    @Test func olderCoveShowerReachesTheCornerOnce() {
        var room = ScannedRoom()
        func wall(_ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(lengthFt: hypot(b.0 - a.0, b.1 - a.1), heightFt: 8, start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        room.walls = [wall((0, 0), (2, 0)), wall((2, 0), (2, -3)), wall((2, -3), (7, -3)),
                      wall((7, -3), (7, 0)), wall((7, 0), (10, 0)), wall((10, 0), (10, 8)),
                      wall((10, 8), (0, 8)), wall((0, 8), (0, 0))]
        room.reletter()
        var t = AreaTakeoff()
        _ = t.placeShower(near: .init(x: 4, y: -1.5), in: room, curbWidthFt: 4.5 / 12)
        let now = t
        // As placed before: 2″ shallower.
        var old = t
        old.floorRect?.depthFt -= 2.25 / 12
        old.coveDepthFt = 3
        old.fitCove(in: room)
        #expect(abs(old.floorRect!.depthFt - now.floorRect!.depthFt) < 1e-9)
        #expect(old.coveDepthFt == now.coveDepthFt)
        let once = old
        old.fitCove(in: room)
        #expect(old == once)
    }
}

struct NicheBackStoneTests {
    /// A niche's back can be stone, priced by its own area (owner, 2026-10-13).
    @Test func aStoneNicheBackIsPricedByItsArea() {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 120, ceilingIn: 96))
        var t = AreaTakeoff()
        t.floor = .drawn
        _ = t.placeShower(near: .init(x: 9.5, y: 9.5), in: room, curbWidthFt: 4.5 / 12)
        let wall = room.walls.first { w in t.pieces.contains { $0.wallID == w.id } }!
        t.items = [.init(kind: .niche, wallID: wall.id, fromFt: 0.5, toFt: 1.5, bottomIn: 48, heightIn: 24)]
        t.itemsPlaced = true
        let n = t.items[0]
        let tileBefore = t.nicheTileSqft(n)
        #expect(!t.partStone(n, "back"))                       // tile to start
        t.setPartStone(n, "back", true)
        #expect(abs(tileBefore - t.nicheTileSqft(n) - 2) < 0.01)   // 1′ × 2′ off the tile
        var prices = StonePrices()
        prices.parts[.nicheBack] = StoneRate(bySqft: true, perSqft: 60)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .rectangle, .straightStacked))
        t.apply(room, to: &s, prices: prices)
        let line = s.additionsLabor.first { $0.activity == "Stone niche" }
        #expect(line?.unit == "sq ft" && line?.qty == 2 && line?.rate == 60)
    }
}
