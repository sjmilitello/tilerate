import Foundation
import Testing
import UIKit
import PDFKit
import CoreGraphics
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
        #expect(first?.fromFt == 0 && first?.toFt == 9 && first?.heightIn == 96)   // to the top of the wall (owner, 2026-10-08)

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
        #expect(trim.map(\.name) == ["Wall cap (half wall E)", "Half wall E end jamb"])
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
        #expect(abs(byName["Wall cap (half wall E)"]! - 3) < 1e-9)
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
        // Drawn roughly, 9″ out and a little short: it lands on the curb.
        let (a, b) = t.snappedNewWall(.init(x: 5.3, y: 3.75), .init(x: 8.7, y: 3.75), in: r, thicknessIn: 4.5)
        #expect(abs(a.x - 5) < 1e-9 && abs(b.x - 9) < 1e-9)
        #expect(abs(a.y - 3) < 1e-9 && abs(b.y - 3) < 1e-9)
        // Far from the shower, it's left where it was drawn.
        let away = t.snappedNewWall(.init(x: 1, y: 6), .init(x: 4, y: 6), in: r, thicknessIn: 4.5)
        #expect(away.0.y == 6 && away.1.x == 4)
        // Built there, the front is closed: no curb along it, only the left side's.
        _ = r.addPlannedWall(from: a, to: b, heightIn: 96, thicknessIn: 4.5)
        let curb = try #require(t.trimPieces(in: r, area: .shower, curbHeightIn: 4).first { $0.key == "curb" })
        #expect(abs(curb.lengthFt - 3) < 1e-9)
    }

    @Test func aKneeWallAcrossPartOfTheFrontLeavesTheRestAsTheEntry() throws {
        // Three-wall shower across the top of the room (walls D, A, B), 9′ × 3′,
        // open along y = 3. A 42″ knee wall covers the front's first 5′ from wall B.
        var r = room
        var t = AreaTakeoff()
        t.floor = .drawn
        t.pieces = [piece(D, 5, 8, 96), piece(A, 0, 9, 96), piece(B, 0, 3, 96)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 0, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 9, depthFt: 3)
        #expect(t.openSides(in: r).count == 1)
        let knee = r.addPlannedWall(from: .init(x: 9, y: 3), to: .init(x: 4, y: 3), heightIn: 42, thicknessIn: 4.5)
        t.pieces.append(.init(wallID: knee.id, fromFt: 0, toFt: 5, heightIn: 42, face: 0))
        let sides = t.openSides(in: r)
        #expect(sides.count == 1 && abs(sides[0].lengthFt - 4) < 1e-9)
        let trim = t.trimPieces(in: r, area: .shower, curbHeightIn: 4)
        let byName = Dictionary(uniqueKeysWithValues: trim.map { ($0.name, $0.lengthFt) })
        // Facing in (up) from y = 3: wall D (x = 0) on the left, the knee wall's end on the right.
        #expect(abs(byName["Curb"]! - 4) < 1e-9)
        #expect(abs(byName["Left jamb"]! - (8 - 4.0 / 12)) < 1e-9)
        #expect(abs(byName["Right lower jamb"]! - (3.5 - 4.0 / 12)) < 1e-9)
        #expect(abs(byName["Right upper jamb"]! - 4.5) < 1e-9)
        #expect(abs(byName["Wall cap (half wall E)"]! - 5) < 1e-9)
    }

    @Test func aFullWallJustUnderAnOddCeilingIsStillFull() {
        // Scans come back with ceilings like 8′ 0.7″; a wall rounded down to 8′ is still full.
        var r = room
        for i in r.walls.indices { r.walls[i].heightFt = 96.7 / 12 }
        let full = r.addPlannedWall(from: .init(x: 5, y: 3), to: .init(x: 9, y: 3), heightIn: 96, thicknessIn: 4.5)
        let half = r.addPlannedWall(from: .init(x: 5, y: 0), to: .init(x: 5, y: 3), heightIn: 42, thicknessIn: 4.5)
        #expect(!r.isKneeWall(full) && r.name(of: full) == "New wall E")
        #expect(r.isKneeWall(half) && r.name(of: half) == "Half wall F")
    }

    @Test func aWallAlreadyDrawnInIsFoundRatherThanStacked() {
        var r = room
        let w = r.addPlannedWall(from: .init(x: 5, y: 3), to: .init(x: 9, y: 3), heightIn: 96, thicknessIn: 4.5)
        // Drawn again over it, a little off and the other way: the same wall.
        #expect(r.plannedWall(along: .init(x: 8.9, y: 3.1), .init(x: 5.2, y: 3.05))?.id == w.id)
        // A foot away, or along a different stretch: a new one.
        #expect(r.plannedWall(along: .init(x: 5, y: 4), .init(x: 9, y: 4)) == nil)
        #expect(r.plannedWall(along: .init(x: 0, y: 3), .init(x: 4, y: 3)) == nil)
    }

    @Test func tileOnADeletedWallNoLongerCounts() {
        var r = room
        let w = r.addPlannedWall(from: .init(x: 5, y: 3), to: .init(x: 9, y: 3), heightIn: 96, thicknessIn: 4.5)
        var t = AreaTakeoff()
        t.pieces = [piece(A, 0, 4, 96), .init(wallID: w.id, fromFt: 0, toFt: 4, heightIn: 96)]
        #expect(abs(t.wallsSqft(in: r) - 64) < 1e-9)
        r.walls.removeAll { $0.id == w.id }
        #expect(abs(t.wallsSqft(in: r) - 32) < 1e-9)
    }

    // MARK: Benches, niches, windows and corner pieces

    @Test func placedBenchesNichesAndWindowsAreTheHigherOfMinimumAndSize() {
        var r = Rates()
        r.unitBench = 200; r.benchPerLinFt = 50
        r.unitNiche = 300
        r.setStoneRate(StoneRate(perLinFt: 40), for: .niche)
        r.unitWindow = 100
        r.setStoneRate(StoneRate(perLinFt: 10, widthIn: 6, bySqft: true, perSqft: 30), for: .window)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked), showerWalls: 80)
        s.features.benches = 2
        s.features.niches = 2
        s.features.windows = 1
        s.features.sized = [
            SizedFeature(kind: .bench, label: "Framed bench 5′", linFt: 5),        // 250 > 200
            SizedFeature(kind: .bench, label: "Floating bench 3′", linFt: 3),      // 150 < 200: minimum
            SizedFeature(kind: .niche, label: "Niche 13″ × 24″, stone all around", linFt: 10, stone: true), // 400
            SizedFeature(kind: .window, label: "Window", linFt: 10, stone: true),  // 10 × ½′ × 30 = 150
        ]
        // One niche typed, not placed: the per-unit price.
        let legacy = legacySummary(state: EstimatorState(section: s), rates: r)
        let scheme = schemeSummary(state: EstimatorState(section: s), scheme: PricingScheme(rates: r))
        #expect(legacy.lines.map(\.label) == scheme.lines.map(\.label))
        #expect(legacy.lines.map(\.amount) == scheme.lines.map(\.amount))
        func amount(_ start: String) -> Double? { legacy.lines.first { $0.label.hasPrefix(start) }?.amount }
        #expect(amount("Framed bench 5′") == 250)
        #expect(amount("Floating bench 3′") == 200)
        #expect(amount("Niches (1×") == 300)
        #expect(amount("Niche 13″") == 400)
        #expect(amount("Window") == 150)
        #expect(legacy.lines.contains { $0.label == "Floating bench 3′ (minimum $200.00)" })
    }

    @Test func placedItemsSetTheAreasFeaturesAndStoneWithWidthsGoesBySquareFoot() {
        let r = room
        var t = AreaTakeoff()
        t.floor = .drawn
        t.pieces = [piece(D, 5, 8, 96), piece(A, 0, 9, 96), piece(B, 0, 3, 96)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 0, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 9, depthFt: 3)
        // A framed bench along wall A, wall to wall: 9′.
        let span = t.benchSpan(on: r.walls[0], in: r, floating: false)
        #expect(span == 0...9)
        t.items = [
            .init(kind: .framedBench, wallID: A.id, fromFt: 0, toFt: 9, heightIn: 20, depthIn: 15),
            .init(kind: .niche, wallID: A.id, fromFt: 4, toFt: 4 + 13.0 / 12, bottomIn: 48, heightIn: 24, dividers: 1, stone: .shelves),
            .init(kind: .window, wallID: B.id, fromFt: 0.5, toFt: 2.5, bottomIn: 48, heightIn: 24),
            .init(kind: .cornerShelf, wallID: A.id, bottomIn: 48, sizeIn: 9),
            .init(kind: .cornerSeat, wallID: A.id, bottomIn: 20, sizeIn: 18),
        ]
        t.itemsPlaced = true
        // The window comes off wall B's tile: 3′ × 8′ less 2′ × 2′.
        #expect(abs(t.sqft(of: t.pieces[2], in: r) - (24 - 4)) < 1e-9)
        // The bench's top and front are tile: 9 × 15″ + 9 × 20″.
        #expect(abs(t.benchTileSqft(in: r) - (9 * 1.25 + 9 * 20.0 / 12)) < 1e-9)
        // Stone top: off the tile, onto a line by the square foot (12″ wide).
        t.trim = [.init(key: "benchTop:\(t.items[0].id)", stone: true)]
        #expect(abs(t.benchTileSqft(in: r) - 9 * 20.0 / 12) < 1e-9)
        var prices = StonePrices()
        prices.stone[.benchTop] = StoneRate(perLinFt: 20, widthIn: 12, bySqft: true, perSqft: 35)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked))
        s.features.shelves = 5   // typed earlier: placed items override it
        t.apply(r, to: &s, prices: prices)
        let top = s.additionsLabor.first { $0.activity == "Stone bench top" }
        #expect(top?.qty == 9 && top?.unit == "sq ft" && top?.rate == 35)
        #expect(s.features.benches == 1 && s.features.niches == 1 && s.features.windows == 1)
        #expect(s.features.shelves == 1 && s.features.seats == 1 && s.features.footrests == 0)
        // Stone shelves only: the base shelf and one divider, 13″ each.
        let niche = s.features.sized.first { $0.kind == .niche }
        #expect(niche?.stone == true && abs((niche?.linFt ?? 0) - 26.0 / 12) < 1e-9)
        #expect(s.features.sized.first { $0.kind == .bench }?.linFt == 9)
    }

    @Test func aFloatingBenchNeedsAWallAtEachEnd() {
        let r = room
        var t = AreaTakeoff()
        t.floor = .drawn
        // Shower in the A/B corner, 4′ × 3′, open on its left and front.
        t.pieces = [piece(A, 5, 9, 96), piece(B, 0, 3, 96)]
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 4, depthFt: 3)
        // Along wall A it runs from the open left side to wall B: not floating.
        #expect(t.benchSpan(on: r.walls[0], in: r, floating: true) == nil)
        // Framed, it runs flush with the outside of a 4½″ curb on the open side.
        let framed = t.benchSpan(on: r.walls[0], in: r, floating: false, curbWidthFt: 4.5 / 12)
        #expect(framed.map { abs($0.lowerBound - (5 - 4.5 / 12)) < 1e-9 && abs($0.upperBound - 9) < 1e-9 } == true)
    }

    // MARK: 3-D view

    @Test func aWallWithADoorIsBuiltAroundIt() {
        // An 8′ × 8′ wall with a 2½′ × 6′ 8″ door 2′ in: the strip either side,
        // and the header over the door.
        let cells = Room3DScene.cells(.init(x0: 0, x1: 8, y0: 0, y1: 8),
                                      minus: [.init(x0: 2, x1: 4.5, y0: 0, y1: 80.0 / 12)])
        #expect(cells.count == 3)
        let area = cells.reduce(0) { $0 + $1.w * $1.h }
        #expect(abs(area - (64 - 2.5 * 80 / 12)) < 1e-9)
        #expect(cells.contains { abs($0.x0 - 2) < 1e-9 && abs($0.y0 - 80.0 / 12) < 1e-9 })
    }

    @Test func picturesGoTwoToAPageAndOldEstimatesLoadWithout() throws {
        let blank = PDFPicture(caption: "Room 1 · Shower · Shower") { size in
            UIGraphicsImageRenderer(size: size).image { _ in UIColor.gray.setFill(); UIRectFill(CGRect(origin: .zero, size: size)) }
        }
        let three = EstimatePDF.picturePages([blank, blank, blank], perPage: 2)
        #expect(PDFDocument(data: three)?.pageCount == 2)
        #expect(PDFDocument(data: EstimatePDF.picturePages([blank, blank, blank], perPage: 4))?.pageCount == 1)
        // A document and a layout saved before pictures: none, and off.
        let doc = try JSONDecoder().decode(EstimateDocument.self, from: Data(#"{"rooms":[]}"#.utf8))
        #expect(doc.pictures.isEmpty)
        let layout = try JSONDecoder().decode(EstimateTemplate.self, from: Data(#"{"name":"Old"}"#.utf8))
        #expect(!layout.include3DViews && layout.picturesPerPage == 2)
        #expect(EstimateTemplate.starters.allSatisfy { !$0.include3DViews })
        // Saved and read back.
        var d = EstimateDocument()
        d.pictures = [EstimatePicture(name: "Shower", eye: [1, 5, 2], target: [3, 3, 1])]
        #expect(try JSONDecoder().decode(EstimateDocument.self, from: JSONEncoder().encode(d)) == d)
    }

    @Test func aBenchReachingIntoTheDoorwayIsFlagged() {
        // Shower in the A/B corner, 4′ × 3′, closed by new full walls E (x = 5)
        // and F (y = 3, running from wall B to E), door in F; a 15″ framed bench along B.
        var r = room
        _ = r.addPlannedWall(from: .init(x: 5, y: 0), to: .init(x: 5, y: 3), heightIn: 96, thicknessIn: 4.5)
        let front = r.addPlannedWall(from: .init(x: 9, y: 3), to: .init(x: 5, y: 3), heightIn: 96, thicknessIn: 4.5)
        var t = AreaTakeoff()
        t.floor = .drawn
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 4, depthFt: 3)
        t.items = [.init(kind: .framedBench, wallID: B.id, fromFt: 0, toFt: 3, heightIn: 20, depthIn: 15)]
        // Door 20″ from wall B: clear of the 15″ bench.
        var door = r.addShowerDoor(on: front, along: (20 + 15) / 12.0, widthIn: 30, heightIn: 80)
        #expect(t.doorClashes(door, in: r).isEmpty)
        // Door 20″ from the other end (wall E): in a 48″ wall that pushes it
        // against wall B, so the whole 15″ bench is in the doorway.
        r.openings.removeAll { $0.id == door.id }
        door = r.addShowerDoor(on: front, along: 4 - (20 + 15) / 12.0, widthIn: 30, heightIn: 80)
        let clash = t.doorClashes(door, in: r)
        #expect(clash.count == 1 && clash[0].name == "The framed bench on wall B")
        #expect(abs(clash[0].inches - 15) <= 1)
    }

    // MARK: Calibration

    @Test func oneTapeMeasurementCorrectsTheWholeScan() throws {
        // Wall A scanned 9′; the tape says 106″ (scan 1.9% long).
        let c = ScanCalibration.solve(room, tapeIn: [A.id: 106])
        #expect(abs(c.sx - 106.0 / 108) < 1e-9 && abs(c.sy - c.sx) < 1e-9)
        let fixed = room.calibrated(c)
        #expect(abs(fixed.wall(A.id)!.lengthFt * 12 - 106) < 1e-6)
        #expect(abs(fixed.wall(B.id)!.lengthFt - 8 * 106.0 / 108) < 1e-6)   // the same correction every way
        #expect(abs(fixed.floorSqft - 72 * pow(106.0 / 108, 2)) < 1e-6)
        #expect(fixed.calibrations.count == 1)
        // Undone, it's the scan as it was.
        let undone = try #require(fixed.uncalibrated)
        #expect(abs(undone.wall(A.id)!.lengthFt - 9) < 1e-9 && undone.calibrations.isEmpty)
    }

    // MARK: Editing scanned walls

    /// The owner's bathroom, simplified: a 12′ back wall (y = 0); a divider
    /// from it at x = 5 down to y = 4 between the shower (left) and closet
    /// (right); from the divider's corner the closet's door wall runs right
    /// to x = 12.
    private func dividerRoom() -> ScannedRoom {
        var r = ScannedRoom()
        func wall(_ l: String, _ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(label: l, lengthFt: hypot(b.0 - a.0, b.1 - a.1), heightFt: 8,
                             start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        r.walls = [wall("A", (0, 0), (12, 0)), wall("B", (5, 0), (5, 4)), wall("C", (5, 4), (12, 4)),
                   wall("D", (12, 4), (12, 0))]
        r.openings = [.init(kind: .door, wallID: r.walls[2].id, widthFt: 2.5, heightFt: 80.0 / 12, alongFt: 4)]
        return r
    }

    @Test func draggingTheDividerStretchesTheClosetWallAndKeepsTheBackWall() {
        var r = dividerRoom()
        let back = r.walls[0], divider = r.walls[1], closet = r.walls[2]
        var t = AreaTakeoff()
        t.pieces = [piece(back, 0, 5, 96), piece(divider, 0, 4, 96)]   // the shower: back wall to the divider, and the divider
        let before = r
        // Divider dragged 1′ toward the closet (to x = 6): the shower grows, the closet shrinks.
        r.moveWall(divider.id, by: .init(x: 1.04, y: 0.3))   // only the sideways part counts, to the inch
        let d = r.wall(divider.id)!
        #expect(abs(d.start.x - 6) < 1e-9 && abs(d.end.x - 6) < 1e-9 && abs(d.start.y) < 1e-9 && abs(d.end.y - 4) < 1e-9)
        #expect(abs(r.wall(back.id)!.lengthFt - 12) < 1e-9)          // the back wall is untouched
        let c = r.wall(closet.id)!
        #expect(abs(c.start.x - 6) < 1e-9 && abs(c.lengthFt - 6) < 1e-9)   // the closet wall follows its corner
        // The closet door stays where it was in the room (its along shifts by the 1′ the wall's start moved).
        #expect(abs((r.openings[0].alongFt ?? 0) - 3) < 1e-9)
        // The shower's tile follows: the back-wall piece is unchanged (that wall didn't move)…
        let moved = t.following(old: before, new: r)
        #expect(moved.pieces.first { $0.wallID == back.id }?.toFt == 5)
        // …so the owner stretches it to the divider; the divider piece keeps its 4′.
        #expect(abs((moved.pieces.first { $0.wallID == divider.id }?.toFt ?? 0) - 4) < 1e-9)
    }

    @Test func typingTheDistanceToAParallelWallMovesIt() {
        var r = dividerRoom()
        let divider = r.walls[1], east = r.walls[3], closet = r.walls[2]
        let near = r.parallelNeighbors(of: divider.id)
        #expect(near.count == 1 && near[0].wall.id == east.id && abs(abs(near[0].offset) - 7) < 1e-9)
        // The closet measures 6′ wide: the divider goes to x = 6, the closet wall follows.
        r.setDistance(of: divider.id, from: east.id, to: 6)
        #expect(abs(r.wall(divider.id)!.start.x - 6) < 1e-9)
        #expect(abs(r.wall(closet.id)!.lengthFt - 6) < 1e-9)
        #expect(abs(r.wall(r.walls[0].id)!.lengthFt - 12) < 1e-9)
    }

    @Test func undoAndRedoStepThroughSettledChanges() {
        var h = EditHistory(1)
        h.settle(2)
        h.settle(2)            // no change: no step
        h.settle(3)
        #expect(h.undo(from: 3) == 2)
        #expect(h.undo(from: 2) == 1)
        #expect(h.undo(from: 1) == nil && !h.canUndo)
        #expect(h.redo(from: 1) == 2)
        // Something not yet settled is settled before undoing, so it can be redone.
        var g = EditHistory(1)
        #expect(g.undo(from: 5) == 1)
        #expect(g.redo(from: 1) == 5)
        // A new change clears what could be redone.
        _ = g.undo(from: 5)
        g.settle(7)
        #expect(!g.canRedo)
    }

    @Test func aWallCanBeSplitAndItsTileFollows() {
        var r = dividerRoom()
        let back = r.walls[0]
        var t = AreaTakeoff()
        t.pieces = [piece(back, 0, 12, 96)]
        let before = r
        let second = r.splitWall(back.id, atFt: 5)!
        #expect(abs(r.wall(back.id)!.lengthFt - 5) < 1e-9 && abs(second.lengthFt - 7) < 1e-9)
        let moved = t.following(old: before, new: r)
        #expect(moved.pieces.count == 2)
        #expect(moved.pieces.contains { $0.wallID == back.id && $0.toFt == 5 })
        #expect(moved.pieces.contains { $0.wallID == second.id && $0.fromFt == 0 && abs($0.toFt - 7) < 1e-9 })
        #expect(abs(moved.wallsSqft(in: r) - 12 * 8) < 1e-9)
    }

    @Test func draggingAWallEndMovesTheCornerItShares() {
        var r = dividerRoom()
        let closet = r.walls[2], east = r.walls[3]
        r.moveWallEnd(closet.id, start: false, to: .init(x: 13, y: 4))
        #expect(abs(r.wall(closet.id)!.lengthFt - 8) < 1e-9)
        #expect(abs(r.wall(east.id)!.start.x - 13) < 1e-9)   // the wall from that corner went with it
    }

    @Test func calibratingAgainKeepsWhatWasTapedBefore() {
        // A 102″, B 90″; then A again at 101″ with B's earlier tape still there.
        let first = room.calibrated(ScanCalibration.solve(room, tapeIn: [A.id: 102, B.id: 90]))
        let again = first.calibrated(ScanCalibration.solve(first, tapeIn: [A.id: 101, B.id: 90]))
        #expect(abs(again.wall(A.id)!.lengthFt * 12 - 101) < 1e-6)
        #expect(abs(again.wall(B.id)!.lengthFt * 12 - 90) < 1e-6)   // B unchanged
        // The earlier tape is kept with the calibration, to show again.
        #expect(first.calibrations.last?.tapeIn[B.id.uuidString] == 90)
    }

    @Test func oneWallEachWayCorrectsLengthAndWidthSeparately() {
        // A (across) tapes 107″, B (down) tapes 97″, ceiling 95½″.
        let c = ScanCalibration.solve(room, tapeIn: [A.id: 107, B.id: 97], ceilingIn: 95.5)
        let fixed = room.calibrated(c)
        #expect(abs(fixed.wall(A.id)!.lengthFt * 12 - 107) < 1e-6)
        #expect(abs(fixed.wall(B.id)!.lengthFt * 12 - 97) < 1e-6)
        #expect(abs(fixed.wall(C.id)!.lengthFt * 12 - 107) < 1e-6)
        #expect(abs(fixed.walls[0].heightFt * 12 - 95.5) < 1e-6)
        // Areas move with it: a full-height piece stays full, a 48″ one stays 48″,
        // the shower floor stretches, a niche keeps its size.
        var t = AreaTakeoff()
        t.pieces = [piece(A, 0, 9, 96), piece(B, 0, 4, 48)]
        t.floor = .drawn
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 5, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                            widthFt: 4, depthFt: 3)
        t.items = [.init(kind: .niche, wallID: A.id, fromFt: 4, toFt: 4 + 13.0 / 12, bottomIn: 48, heightIn: 24)]
        let moved = t.calibrated(c, before: room)
        #expect(abs(moved.pieces[0].toFt * 12 - 107) < 1e-6 && moved.pieces[0].heightIn == 95)
        #expect(moved.pieces[1].heightIn == 48 && abs(moved.pieces[1].toFt * 12 - 48 * 97.0 / 96) < 1e-6)
        #expect(abs(moved.floorRect!.widthFt - 4 * 107.0 / 108) < 1e-6 && abs(moved.floorRect!.depthFt - 3 * 97.0 / 96) < 1e-6)
        #expect(abs(moved.items[0].widthFt * 12 - 13) < 1e-6)
        // Saved and read back; old scans have none.
        #expect(fixed.calibrations.first == c)
    }

    @Test func dimensionsReadToTheQuarterInch() {
        #expect(dimensionText(9) == "9′ 0″")
        #expect(dimensionText(106.5 / 12) == "8′ 10 1/2″")
        #expect(dimensionText(97.25 / 12) == "8′ 1 1/4″")
        #expect(dimensionText(13.1875 / 12) == "1′ 1 3/16″")
        #expect(dimensionText(0.25 / 12) == "1/4″")
        #expect(dimensionText(13.0 / 12) == "1′ 1″")
        #expect(dimensionText(0.5) == "6″")
        #expect(dimensionText(95.9 / 12) == "7′ 11 7/8″")
        #expect(feetAndInches(5) == "5′")
        // Typed as a tape is read.
        #expect(Lengths.parse("8' 10 1/2\"") == 106.5)
        #expect(Lengths.parse("8'10-1/2") == 106.5)
        #expect(Lengths.parse("8′ 10½") == nil || Lengths.parse("8′ 10½") == 106.5)
        #expect(Lengths.parse("106 1/2") == 106.5)
        #expect(Lengths.parse("106.5") == 106.5)
        #expect(Lengths.parse("3/16") == 0.1875)
        #expect(Lengths.parse("8'") == 96)
        #expect(Lengths.parse("8' 1") == 97)
        #expect(Lengths.parse("abc") == nil)
        #expect(Lengths.typed(inches: 106.5) == "8' 10 1/2\"")
    }

    // MARK: Suggested areas

    @Test func aScanSuggestsTheFloorTubAndBacksplashButNotAShowerInAPlainRoom() {
        let found = room.suggestions()
        #expect(found.map(\.title) == ["Tub surround", "Floor", "Backsplash"])
        // The tub surround: the walls round the tub, full height (owner's rule).
        let tub = found[0].takeoff
        #expect(Set(tub.pieces.map(\.wallID)) == [A.id, D.id])
        #expect(tub.pieces.allSatisfy { $0.heightIn == 96 })
        // The floor leaves out the tub.
        #expect(found[1].takeoff.floor == .room && found[1].takeoff.excludeTub)
        // Areas the room already has aren't suggested again.
        #expect(room.suggestions(skipping: [.floor, .tub]).map(\.title) == ["Backsplash"])
    }

    @Test func anAlcoveOfThreeWallsIsAPossibleShower() {
        // A 10′ × 8′ room with a 5′ × 3′ alcove off its top wall, between x = 2 and 7.
        var r = ScannedRoom()
        func wall(_ l: String, _ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(label: l, lengthFt: hypot(b.0 - a.0, b.1 - a.1), heightFt: 8,
                             start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        r.walls = [wall("A", (0, 0), (2, 0)), wall("B", (2, 0), (2, -3)), wall("C", (2, -3), (7, -3)),
                   wall("D", (7, -3), (7, 0)), wall("E", (7, 0), (10, 0)), wall("F", (10, 0), (10, 8)),
                   wall("G", (10, 8), (0, 8)), wall("H", (0, 8), (0, 0))]
        r.floorOutline = [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 2, y: -3), .init(x: 7, y: -3),
                          .init(x: 7, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 8), .init(x: 0, y: 8)]
        let found = r.suggestions()
        let shower = found.first { $0.area == .shower }
        #expect(shower?.title == "Possible shower")
        let t = shower!.takeoff
        #expect(abs(t.floorRect!.widthFt - 5) < 1e-9 && abs(t.floorRect!.depthFt - 3) < 1e-9)
        #expect(Set(t.pieces.map(\.wallID)) == Set([r.walls[1].id, r.walls[2].id, r.walls[3].id]))
        #expect(abs(t.wallsSqft(in: r) - (3 + 5 + 3) * 8) < 1e-9)
        // Just one: the room's own corners aren't alcoves.
        #expect(found.filter { $0.area == .shower }.count == 1)
    }

    @Test func theShowerGoesInTheCornerTappedWithItsWallsAndCurb() {
        // Sample room 9′ × 8′; tap near the B/C corner (x = 9, y = 8).
        var t = AreaTakeoff()
        t.pieces = [piece(A, 0, 9, 96)]                       // a wrong guess somewhere else
        let placed = t.placeShower(near: .init(x: 8.6, y: 7.5), in: room)
        #expect(placed)
        let r = t.floorRect!
        #expect(abs(r.origin.x - 9) < 1e-9 && abs(r.origin.y - 8) < 1e-9)
        #expect(abs(r.widthFt - 5) < 1e-9 && abs(r.depthFt - 3) < 1e-9)
        // Its 5′ side along the longer wall (C, 9′), 3′ up wall B; both tiled full height, A no longer.
        #expect(Set(t.pieces.map(\.wallID)) == [B.id, C.id])
        #expect(t.pieces.allSatisfy { $0.heightIn == 96 })
        #expect(abs(t.wallsSqft(in: room) - (5 + 3) * 8) < 1e-9)
        // The curb on the two open sides.
        let curb = t.trimPieces(in: room, area: .shower, curbHeightIn: 4).first { $0.key == "curb" }
        #expect(abs((curb?.lengthFt ?? 0) - 8) < 1e-9)
        // Turned: 3′ along C, 5′ up B, still in the corner; the walls follow.
        var turned = t
        turned.floorRect = r.turned
        turned.tileWallsAroundFloor(in: room)
        #expect(abs(turned.floorRect!.widthFt - 3) < 1e-9 && abs(turned.floorRect!.depthFt - 5) < 1e-9)
        #expect(abs(turned.floorRect!.origin.x - 9) < 1e-9 && abs(turned.floorRect!.origin.y - 8) < 1e-9)
        #expect(abs(turned.wallsSqft(in: room) - (3 + 5) * 8) < 1e-9)
        let onB = turned.pieces.first { $0.wallID == B.id }!
        #expect(abs((onB.toFt - onB.fromFt) - 5) < 1e-9)
        // A scan turned on the plan (as real ones are) still puts the long side along the longer wall.
        let tilted = room.turned(by: 27)
        var t2 = AreaTakeoff()
        let c = tilted.walls[1].end    // the B/C corner
        let placedTilted = t2.placeShower(near: .init(x: c.x, y: c.y), in: tilted)
        #expect(placedTilted)
        let along = t2.floorRect!.u
        let cDir = ScannedRoom.Point(x: (tilted.walls[2].end.x - tilted.walls[2].start.x) / 9, y: (tilted.walls[2].end.y - tilted.walls[2].start.y) / 9)
        #expect(abs(along.x * cDir.x + along.y * cDir.y) > 0.99)
        // Moved back into the corner and tiled round.
        let again = turned.placeShower(near: .init(x: 8.6, y: 7.5), in: room)
        #expect(again)
    }

    @Test func wallTileStartsFullHeightExceptBacksplashes() {
        let w = room.walls[0]
        #expect(AreaTakeoff.startingHeight(for: .tub, wall: w) == 96)
        #expect(AreaTakeoff.startingHeight(for: .shower, wall: w) == 96)
        #expect(AreaTakeoff.startingHeight(for: .wall, wall: w) == 96)
        #expect(AreaTakeoff.startingHeight(for: .backsplash, wall: w) == 18)
    }

    @Test func areasSavedBeforeAreMeasuredFromTheModel() throws {
        let s = try JSONDecoder().decode(EstimateSection.self, from: Data(#"{"roomName":"Bath"}"#.utf8))
        #expect(!s.measuredByHand)
    }

    @Test func aRoomIsDrawnForThePDF() throws {
        var t = AreaTakeoff()
        t.pieces = [piece(A, 0, 9, 96), piece(B, 0, 3, 96)]
        let c = Room3DContent(room: room, takeoff: t, area: .shower, tile: nil, floorTile: nil, others: [],
                              curbHeightIn: 4, stoneParts: [], showFixtures: true)
        let cam = Room3DScene.standard(.room, content: c)
        let image = try #require(Room3DScene.picture(c, eye: cam.eye, target: cam.target, size: CGSize(width: 200, height: 120)))
        #expect(image.size.width > 0)
    }

    @Test func tileSizesComeLongSideFirstWithUsualFallbacks() {
        var t = TileChoice(tileType: .porcelain, tileSize: .rectangle, layout: .runningBond, tileWidthIn: 24, tileLengthIn: 12)
        #expect(TilePattern.size(t) == (24, 12))
        t.tileWidthIn = nil; t.tileLengthIn = nil
        #expect(TilePattern.size(t) == (24, 12))
        t.tileSize = .mosaic
        #expect(TilePattern.size(t) == (2, 2))
        // Herringbone 12 × 24 repeats every 48″.
        t = TileChoice(tileType: .porcelain, tileSize: .rectangle, layout: .herringbone, tileWidthIn: 12, tileLengthIn: 24)
        #expect(TilePattern.make(t).periodIn == CGSize(width: 48, height: 48))
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
