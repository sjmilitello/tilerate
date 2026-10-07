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
