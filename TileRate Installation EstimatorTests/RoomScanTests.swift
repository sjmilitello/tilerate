import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Square feet from a LiDAR room scan (AreaTakeoff).
struct RoomScanTests {
    /// A 9′ × 8′ bathroom, 8′ high: A (top, 9′), B (right, 8′), C (bottom, 9′),
    /// D (left, 8′). A tub 5′ × 2′6″ in the A/D corner; a door 2′6″ × 6′8″ in C,
    /// its middle 2′ along; a window 2′6″ × 3′, 3′6″ up, in B, 5′ along.
    private let room = ScannedRoom.sample
    private var A: ScannedRoom.Wall { room.walls[0] }
    private var B: ScannedRoom.Wall { room.walls[1] }
    private var C: ScannedRoom.Wall { room.walls[2] }
    private var D: ScannedRoom.Wall { room.walls[3] }

    private func piece(_ w: ScannedRoom.Wall, _ from: Double, _ to: Double, _ heightIn: Double) -> AreaTakeoff.Piece {
        .init(wallID: w.id, fromFt: from, toFt: to, heightIn: heightIn)
    }

    @Test func thePlanMathLinesUp() {
        #expect(room.floorSqft == 72)
        #expect(room.tubSqft == 12.5)
        #expect(ScannedRoom.area(ScannedRoom.outline(of: room.floorOutline.reversed())) == 72)
        #expect(room.along(.init(x: 4, y: 3), on: A) == 4)
        #expect(room.point(on: B, along: 2) == .init(x: 9, y: 2))
        #expect(room.span(of: room.openings[0]) == 0.75...3.25)
        // The tub's corners against wall A are snap points at 0 and 5.
        #expect(room.snapPoints(on: A).contains(5))
    }

    @Test func aPieceIsItsStretchTimesItsHeight() {
        var t = AreaTakeoff()
        t.pieces = [piece(A, 0, 5, 84), piece(D, 0, 2.5, 96)]
        #expect(t.wallsSqft(in: room) == 35 + 20)
    }

    @Test func openingsComeOffOnlyWhereTheyOverlapAndOnlyWhenTicked() {
        let door = room.openings[0], window = room.openings[1]
        var t = AreaTakeoff()
        t.pieces = [piece(C, 0, 9, 48), piece(B, 0, 8, 96)]
        #expect(t.openingsInPieces(of: room).map(\.id) == [door.id, window.id])
        #expect(t.wallsSqft(in: room) == 36 + 64)            // nothing ticked

        t.subtracted = [door.id, window.id]
        // Door: 2′6″ wide, 4′ of it below the 48″ tile. Window: all of it.
        #expect(t.sqft(of: t.pieces[0], in: room) == 36 - 2.5 * 4)
        #expect(t.sqft(of: t.pieces[1], in: room) == 64 - 2.5 * 3)

        // A piece that stops part-way across the door only loses that part.
        t.pieces[0] = piece(C, 2, 9, 48)
        #expect(t.sqft(of: t.pieces[0], in: room) == 28 - 1.25 * 4)
        // Tiled to 3′: the window, 3′6″ up, isn't in it.
        t.pieces[1].heightIn = 36
        #expect(!t.openingsInPieces(of: room).contains { $0.id == window.id })
    }

    @Test func aNewPieceTakesTheLongestFreeStretch() {
        var shower = AreaTakeoff()
        let first = shower.addPiece(on: A, area: .tub, others: [])
        #expect(first?.fromFt == 0 && first?.toFt == 9 && first?.heightIn == 84)

        // Another area already has A from 0 to 5 (a tub surround).
        var wainscot = AreaTakeoff()
        let p = wainscot.addPiece(on: A, area: .wall, others: [piece(A, 0, 5, 84)])
        #expect(p?.fromFt == 5 && p?.toFt == 9 && p?.heightIn == 96)
        // Nothing left: no piece.
        #expect(wainscot.addPiece(on: A, area: .wall, others: [piece(A, 0, 5, 84)]) == nil)

        var backsplash = AreaTakeoff()
        #expect(backsplash.addPiece(on: B, area: .backsplash, others: [])?.heightIn == 18)
    }

    @Test func snappingRoundsToTheInchOrToANearbyEdge() {
        #expect(snapped(4.93, to: [5]) == 5)
        #expect(snapped(4.6, to: [5]) == (4.6 * 12).rounded() / 12)
        #expect(snapped(1.04, to: []) == 1)
    }

    @Test func aFloorLeavesOutTheTubAndTheShowerFloor() {
        var shower = EstimateSection()
        shower.area = .shower
        shower.measurements.showerFloorSqft = 9
        let t = AreaTakeoff.starting(for: .floor, room: room, otherAreas: [shower])
        #expect(t.floor == .room && t.excludeTub && t.excludeSqft == 9)
        #expect(t.floorSqft(in: room) == 72 - 12.5 - 9)

        var floor = PricingCases.section(.floor, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked), sqft: 1)
        t.apply(room, to: &floor)
        #expect(floor.measurements.sqft == 50.5)
        #expect(floor.scanTakeoff == t)
    }

    @Test func aShowerTakesItsWallsFloorAndCeiling() {
        var t = AreaTakeoff.starting(for: .shower, room: room, otherAreas: [])
        #expect(t.floor == .drawn)
        t.floor = .size
        t.pieces = [piece(B, 0, 3, 96), piece(A, 6, 9, 96)]
        let size = t.suggestedFloorSize(in: room)
        #expect(size?.width == 3 && size?.depth == 3)
        t.floorWidthFt = 3
        t.floorDepthFt = 3
        t.tileCeiling = true

        var same = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        t.apply(room, to: &same)
        #expect(same.measurements.showerWallsSqft == 48)
        #expect(same.measurements.showerFloorSqft == 9)
        #expect(same.measurements.ceilingSqft == 9)

        // With a tile per wall: a wall each, named by the scan's letter.
        var split = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        split.walls = [TiledWall(name: "Wall B", tile: PricingCases.tile(.marble, .hexagon, .straightStacked))]
        t.apply(room, to: &split)
        #expect(split.walls.map(\.name) == ["Wall A", "Wall B"])
        #expect(split.walls.map(\.sqft) == [24, 24])
        #expect(split.walls[1].tile.tileType == .marble)
    }

    @Test func aShowerFloorIsDrawnInTheCornerOfItsWalls() throws {
        // Shower in the A/B corner: 3′ of B from its start (the A corner), the last 4′ of A.
        var t = AreaTakeoff.starting(for: .shower, room: room, otherAreas: [])
        t.pieces = [piece(A, 5, 9, 96), piece(B, 0, 3, 96)]
        let r = try #require(t.suggestedFloorRect(in: room))
        #expect(abs(r.widthFt - 4) < 1e-9 && abs(r.depthFt - 3) < 1e-9)
        // Its corners: the A/B corner, 4′ back along A, 3′ down B.
        let corners = Set(r.corners.map { "\(Int(($0.x * 12).rounded())),\(Int(($0.y * 12).rounded()))" })
        #expect(corners == ["108,0", "60,0", "60,36", "108,36"])
        t.floorRect = r
        #expect(t.floorSqft(in: room) == 12)
        t.tileCeiling = true
        #expect(t.ceilingSqft(in: room) == 12)

        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        t.apply(room, to: &s)
        #expect(s.measurements.showerFloorSqft == 12)
        #expect(s.measurements.showerWallsSqft == 32 + 24)

        // A shower on one wall gets a 3′ deep floor out into the room.
        var one = AreaTakeoff()
        one.pieces = [piece(C, 0, 5, 96)]
        let r1 = try #require(one.suggestedFloorRect(in: room))
        #expect(r1.widthFt == 5 && r1.depthFt == 3)
        #expect(r1.corners.allSatisfy { $0.y <= 8 + 1e-9 && $0.y >= 5 - 1e-9 })
    }

    @Test func aWallThatContinuesPastTheShowerSplitsBetweenAreas() {
        // Wall A: tub surround over the tub (0–5′ at 84″), wainscot beyond (5–9′ at 48″).
        var tub = AreaTakeoff.starting(for: .tub, room: room, otherAreas: [])
        #expect(tub.floorWidthFt == 5 && tub.floorDepthFt == 2.5)
        tub.pieces = [piece(A, 0, 5, 84), piece(D, 0, 2.5, 84)]
        var wainscot = AreaTakeoff()
        wainscot.pieces = [piece(A, 5, 9, 48)]

        var tubSection = PricingCases.section(.tub, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        tub.apply(room, to: &tubSection)
        #expect(tubSection.measurements.sqft == 35 + 17.5)
        var wallSection = PricingCases.section(.wall, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        wainscot.apply(room, to: &wallSection)
        #expect(wallSection.measurements.sqft == 16)
    }

    @Test func aWallSplitInTwoByTheScannerIsMergedBack() {
        func w(_ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(lengthFt: ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot(), heightFt: 8,
                             start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        // The top wall came back as 0–4 and 4.1–9 (a hair out of line); the others are whole.
        let parts = [w((0, 0), (4, 0)), w((4.1, 0.05), (9, 0)), w((9, 0), (9, 8)), w((9, 8), (0, 8)), w((0, 8), (0, 0))]
        var (walls, into) = ScannedRoom.mergingStraightRuns(parts)
        #expect(walls.count == 4)
        #expect(into[parts[1].id] == parts[0].id)
        let top = walls.first { $0.id == parts[0].id }!
        #expect(abs(top.lengthFt - 9) < 0.01)
        // Parallel walls across the room are never merged.
        #expect(ScannedRoom.mergingStraightRuns([parts[2], parts[4]]).0.count == 2)
        ScannedRoom.letter(&walls)
        #expect(Set(walls.map(\.label)) == ["A", "B", "C", "D"])
    }

    @Test func aTurnedScanIsSquaredUpForTheScreen() {
        #expect(abs(room.squaringAngle) < 1e-9)
        for degrees in [27.0, -40, 63, 90, 135] {
            let turned = room.turned(by: degrees)
            // The angle that squares it is the turn, folded into ±45°.
            var expected = degrees.truncatingRemainder(dividingBy: 90)
            if expected > 45 { expected -= 90 }
            if expected < -45 { expected += 90 }
            #expect(abs(turned.squaringAngle * 180 / .pi - expected) < 1e-6, "\(degrees)°")
            // Turning doesn't change any measurement.
            #expect(abs(ScannedRoom.area(turned.floorOutline) - 72) < 1e-9)
            #expect(abs(turned.tubSqft - 12.5) < 1e-9)
        }
    }

    @Test func aKneeWallDrawnFromAWallSnapsSquareAndCountsItsFacesAndCap() throws {
        var r = room
        // Drawn from wall C (bottom, y = 8) up toward the middle, a little crooked.
        let start = r.snappedToWall(.init(x: 6, y: 7.8))
        #expect(abs(start.y - 8) < 1e-9 && abs(start.x - 6) < 1e-9)
        let end = r.plannedEnd(from: start, toward: .init(x: 6.3, y: 4.04))
        #expect(abs(end.x - 6) < 1e-9 && abs(end.y - 4) < 1e-9)          // straightened, 4′ to the inch
        let wall = r.addPlannedWall(from: start, to: end, heightIn: 42, thicknessIn: 4.5)
        #expect(wall.label == "E" && wall.planned && abs(wall.lengthFt - 4) < 1e-9)
        // Against wall C at its start; its far end is open.
        #expect(!r.isFreeEnd(of: wall, start: true))
        #expect(r.isFreeEnd(of: wall, start: false))
        #expect(r.faceName(of: wall, face: 0).hasPrefix("Side facing wall") )
        #expect(r.faceName(of: wall, face: 0) != r.faceName(of: wall, face: 1))

        // The shower side and the room side, each 4′ × 42″, and the cap.
        var t = AreaTakeoff()
        let showerPiece = t.addPiece(on: wall, area: .shower, others: [], face: 0)
        let shower = try #require(showerPiece)
        #expect(shower.heightIn == 42)
        let roomPiece = t.addPiece(on: wall, area: .shower, others: [], face: 1)
        let roomSide = try #require(roomPiece)
        #expect(roomSide.fromFt == 0 && roomSide.toFt == 4)
        let none = t.addPiece(on: wall, area: .shower, others: [], face: 0)
        #expect(none == nil)   // that face is full
        #expect(abs(t.wallsSqft(in: r) - 28) < 1e-9)

        // Outside a shower: a cap and a jamb at the open end, tile until switched to stone.
        let trim = t.trimPieces(in: r, area: .wall, curbHeightIn: 4)
        #expect(trim.map(\.name) == ["Wall cap (knee wall E)", "Knee wall E end jamb"])
        #expect(abs(trim[0].lengthFt - 4) < 1e-9 && abs(trim[1].lengthFt - 3.5) < 1e-9)
        #expect(trim.allSatisfy { !$0.stone })
        var s = PricingCases.section(.wall, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        let prices = StonePrices(curb: 30, cap: 25, jamb: 20, curbHeightIn: 4)
        t.apply(r, to: &s, prices: prices)
        #expect(s.additionsLabor.isEmpty)                                // tile: no line
        t.trim = [.init(key: trim[0].key, stone: true)]
        t.apply(r, to: &s, prices: prices)
        let cap = try #require(s.additionsLabor.first)
        #expect(cap.activity == "Stone wall cap" && cap.qty == 4 && cap.rate == 25 && cap.unit == "lin ft")
        s.additionsLabor[0].rate = 28                                    // changed on the estimate
        t.trim[0].lengthFt = 4.5
        t.apply(r, to: &s, prices: prices)
        #expect(s.additionsLabor.count == 1 && s.additionsLabor[0].qty == 4.5 && s.additionsLabor[0].rate == 28)
        t.trim = []
        t.apply(r, to: &s, prices: prices)
        #expect(s.additionsLabor.isEmpty)

        // Moving its open end keeps its length right.
        r.movePlannedEnd(wall.id, start: false, to: .init(x: 6, y: 5))
        #expect(abs(r.wall(wall.id)!.lengthFt - 3) < 1e-9)
        // It's saved with the room.
        let back = try JSONDecoder().decode(ScannedRoom.self, from: JSONEncoder().encode(r))
        #expect(back.wall(wall.id)?.planned == true && back.wall(wall.id)?.thicknessIn == 4.5)
    }

    @Test func anOpenThreeSidedShowerHasACurbAndTwoFullJambs() throws {
        // Shower across the room's top end: walls D (left), A (back), B (right); open at y = 3.
        var t = AreaTakeoff()
        t.floor = .drawn
        t.pieces = [piece(D, 5, 8, 96), piece(A, 0, 9, 96), piece(B, 0, 3, 96)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 0, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 9, depthFt: 3)
        let trim = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        #expect(Set(trim.map(\.name)) == ["Curb", "Left jamb", "Right jamb"])
        #expect(abs(trim.first { $0.name == "Curb" }!.lengthFt - 9) < 1e-9)
        #expect(trim.filter { $0.kind == .jamb }.allSatisfy { abs($0.lengthFt - (8 - 4.0 / 12)) < 1e-9 })
        // Facing in (up the screen) from y = 3, x = 0 is on the left.
        let left = try #require(trim.first { $0.name == "Left jamb" })
        #expect(left.key == "jamb:left")
    }

    @Test func aShowerWithAKneeWallOnTheRightHasACapAndSplitJamb() throws {
        // Shower in the A/B corner, 4′ along A and 3′ deep; a 42″ knee wall
        // closes its left side (x = 5, from A down 3′). Entry: the bottom, y = 3.
        var r = room
        let knee = r.addPlannedWall(from: .init(x: 5, y: 0), to: .init(x: 5, y: 3), heightIn: 42, thicknessIn: 4.5)
        var t = AreaTakeoff()
        t.floor = .drawn
        t.pieces = [piece(r.walls[0], 5, 9, 96), piece(r.walls[1], 0, 3, 96),
                    .init(wallID: knee.id, fromFt: 0, toFt: 3, heightIn: 42, face: 0)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 4, depthFt: 3)
        let trim = t.trimPieces(in: r, area: .shower, curbHeightIn: 4)
        let byName = Dictionary(uniqueKeysWithValues: trim.map { ($0.name, $0.lengthFt) })
        // Standing outside (below) facing in (up): wall B (x = 9) is on the right, the knee wall on the left.
        #expect(abs(byName["Curb"]! - 4) < 1e-9)
        #expect(abs(byName["Right jamb"]! - (8 - 4.0 / 12)) < 1e-9)          // curb to the top of the tile
        #expect(abs(byName["Left lower jamb"]! - (3.5 - 4.0 / 12)) < 1e-9)   // curb to cap
        #expect(abs(byName["Left upper jamb"]! - 4.5) < 1e-9)                // cap to the top of the tile
        #expect(abs(byName["Wall cap (knee wall E)"]! - 3) < 1e-9)
        #expect(trim.count == 5)

        // Tile stops at 84″: the jambs follow; a 6″ curb shortens them.
        t.pieces[0].heightIn = 84
        t.pieces[1].heightIn = 84
        t.curbHeightIn = 6
        let lower = t.trimPieces(in: r, area: .shower, curbHeightIn: 4)
        #expect(abs(lower.first { $0.name == "Right jamb" }!.lengthFt - 6.5) < 1e-9)
        #expect(abs(lower.first { $0.name == "Left upper jamb" }!.lengthFt - 3.5) < 1e-9)

        // Stone curb and cap, tile jambs: two lines.
        t.trim = [.init(key: "curb", stone: true), .init(key: "cap:\(knee.id)", stone: true)]
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        t.apply(r, to: &s, prices: StonePrices(curb: 30, cap: 25, jamb: 20, curbHeightIn: 4))
        #expect(s.additionsLabor.map(\.activity) == ["Stone curb", "Stone wall cap"])
        #expect(s.additionsLabor.map(\.qty) == [4, 3])
        // Stone jambs: one line for all of them.
        t.trim.append(.init(key: "jamb:right", stone: true))
        t.trim.append(.init(key: "jamb:left:lower", stone: true))
        t.apply(r, to: &s, prices: StonePrices(curb: 30, cap: 25, jamb: 20, curbHeightIn: 4))
        let jambs = try #require(s.additionsLabor.first { $0.activity == "Stone jambs" })
        #expect(abs(jambs.qty - (6.5 + 3)) < 0.01 && jambs.rate == 20)
    }

    @Test func aFourWallShowerWithANewWallAndDoorHasACurbJambsAndHeader() throws {
        // Shower in the A/B corner, 4′ along A and 3′ deep, closed by two new
        // full walls: E on its left (x = 5) and F across its front (y = 3),
        // with a 30″ × 80″ door in the middle of F.
        var r = room
        let left = r.addPlannedWall(from: .init(x: 5, y: 0), to: .init(x: 5, y: 3), heightIn: 96, thicknessIn: 4.5)
        let front = r.addPlannedWall(from: .init(x: 5, y: 3), to: .init(x: 9, y: 3), heightIn: 96, thicknessIn: 4.5)
        #expect(!r.isKneeWall(left) && !r.isKneeWall(front) && r.name(of: front) == "New wall F")
        let door = r.addShowerDoor(on: front, along: 2, widthIn: 30, heightIn: 80)
        var t = AreaTakeoff()
        t.floor = .drawn
        t.pieces = [piece(r.walls[0], 5, 9, 96), piece(r.walls[1], 0, 3, 96),
                    .init(wallID: left.id, fromFt: 0, toFt: 3, heightIn: 96, face: 0),
                    .init(wallID: front.id, fromFt: 0, toFt: 4, heightIn: 96, face: 1)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 4, depthFt: 3)
        let trim = t.trimPieces(in: r, area: .shower, curbHeightIn: 4)
        let byName = Dictionary(uniqueKeysWithValues: trim.map { ($0.name, $0.lengthFt) })
        // Every side of the floor is closed: the only curb is the door's. No caps on full walls.
        #expect(Set(byName.keys) == ["Curb (door in new wall F)", "Left jamb (door in new wall F)",
                                     "Right jamb (door in new wall F)", "Header (door in new wall F)"])
        #expect(abs(byName["Curb (door in new wall F)"]! - 2.5) < 1e-9)
        #expect(abs(byName["Left jamb (door in new wall F)"]! - (80.0 - 4) / 12) < 1e-9)
        #expect(abs(byName["Header (door in new wall F)"]! - 2.5) < 1e-9)
        #expect(t.curbEdges(in: r).count == 1)
        // The door is never tiled: 4′ × 8′ less 2½′ × 6′ 8″.
        #expect(abs(t.sqft(of: t.pieces[3], in: r) - (32 - 2.5 * 80 / 12)) < 1e-9)
        #expect(t.openingsInPieces(of: r).allSatisfy { $0.kind != .showerDoor })

        // A stone header is priced as a wall cap, on a line named for it.
        t.trim = [.init(key: "header:\(door.id)", stone: true)]
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        t.apply(r, to: &s, prices: StonePrices(curb: 30, cap: 25, jamb: 20, curbHeightIn: 4))
        #expect(s.additionsLabor.map(\.activity) == ["Stone header"] && s.additionsLabor[0].qty == 2.5
                && s.additionsLabor[0].rate == 25)

        // Dragged to the ceiling: no header, and the jambs run to the top of the tile.
        let i = r.openings.firstIndex { $0.id == door.id }!
        r.openings[i].heightFt = 8
        #expect(!r.hasHeader(r.openings[i]))
        let open = t.trimPieces(in: r, area: .shower, curbHeightIn: 4)
        #expect(!open.contains { $0.kind == .cap })
        #expect(open.filter { $0.kind == .jamb }.allSatisfy { abs($0.lengthFt - (8 - 4.0 / 12)) < 1e-9 })
        t.apply(r, to: &s, prices: StonePrices(curb: 30, cap: 25, jamb: 20, curbHeightIn: 4))
        #expect(s.additionsLabor.isEmpty)

        // The door is saved with the room.
        let back = try JSONDecoder().decode(ScannedRoom.self, from: JSONEncoder().encode(r))
        #expect(back.openings.first { $0.id == door.id }?.kind == .showerDoor)
    }

    @Test func aPlannedWallMovesWholeAndSnapsToTheShowerFloor() throws {
        // A new wall drawn a foot short of the shower floor's front (y = 3).
        var r = room
        let w = r.addPlannedWall(from: .init(x: 5, y: 4), to: .init(x: 9, y: 4), heightIn: 96, thicknessIn: 4.5)
        let floor = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                          widthFt: 4, depthFt: 3)
        // Dragged up most of a foot: it lines up with the floor's side and stays against wall B.
        r.movePlannedWall(w, by: .init(x: 0.1, y: -0.9), guides: floor.corners)
        let moved = try #require(r.wall(w.id))
        #expect(abs(moved.start.y - 3) < 1e-9 && abs(moved.end.y - 3) < 1e-9)
        #expect(abs(moved.end.x - 9) < 1e-9 && abs(moved.lengthFt - 4) < 1e-9)
        // Away from anything to snap to, it moves to the inch.
        r.movePlannedWall(moved, by: .init(x: 0, y: 1.52))
        #expect(abs(r.wall(w.id)!.start.y - (3 + 18.0 / 12)) < 1e-9)
    }

    @Test func aNewWallDrawnNearTheShowerSnapsJustOutsideItsFloor() throws {
        // Shower in the A/B corner, 4′ × 3′; open on its left (x = 5) and front (y = 3).
        var r = room
        var t = AreaTakeoff()
        t.floor = .drawn
        t.pieces = [piece(r.walls[0], 5, 9, 96), piece(r.walls[1], 0, 3, 96)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 4, depthFt: 3)
        // Drawn roughly, 9″ out and a little short: it takes the front's place,
        // its inside face on the floor's edge.
        let (a, b) = t.snappedNewWall(.init(x: 5.3, y: 3.75), .init(x: 8.7, y: 3.75), in: r, thicknessIn: 4.5)
        #expect(abs(a.x - 5) < 1e-9 && abs(b.x - 9) < 1e-9)
        #expect(abs(a.y - (3 + 2.25 / 12)) < 1e-9 && abs(b.y - a.y) < 1e-9)
        // Far from the shower, it's left where it was drawn.
        let away = t.snappedNewWall(.init(x: 1, y: 6), .init(x: 4, y: 6), in: r, thicknessIn: 4.5)
        #expect(away.0.y == 6 && away.1.x == 4)
        // Built there, the front is closed: no curb along it, only the left side's.
        _ = r.addPlannedWall(from: a, to: b, heightIn: 96, thicknessIn: 4.5)
        let curb = try #require(t.trimPieces(in: r, area: .shower, curbHeightIn: 4).first { $0.key == "curb" })
        #expect(abs(curb.lengthFt - 3) < 1e-9)
    }

    @Test func theScanIsSavedWithTheRoomAndTheChoicesWithTheArea() throws {
        var r = EstimateRoom(name: "Bath")
        r.scan = room
        var s = EstimateSection()
        var t = AreaTakeoff()
        t.pieces = [piece(A, 0, 5, 84)]
        t.subtracted = [room.openings[0].id]
        s.scanTakeoff = t
        r.sections = [s]
        let back = try JSONDecoder().decode(EstimateRoom.self, from: JSONEncoder().encode(r))
        #expect(back.scan == room)
        #expect(back.sections.first?.scanTakeoff == t)
        // Rooms saved before scans existed still load.
        let old = try JSONDecoder().decode(EstimateRoom.self, from: Data(#"{"name":"Kitchen","sections":[]}"#.utf8))
        #expect(old.scan == nil && old.name == "Kitchen")
        #expect(feetAndInches(7.5) == "7′ 6″")
        #expect(feetAndInches(0.5) == "6″")
    }
}
