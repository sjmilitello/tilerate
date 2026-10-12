import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// A Floor area on a scanned room leaves out the shower floors (with their
/// curbs), "no tile" boxes and the tub, can have its outline moved in, and
/// runs on into a curbless shower in the same tile in the drawing only
/// (owner, 2026-10-12).
struct RoomFloorTests {
    /// A 10′ × 8′ room, its floor outline the walls' corners.
    private var room: ScannedRoom {
        var r = ScannedRoom()
        func w(_ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(lengthFt: hypot(b.0 - a.0, b.1 - a.1), heightFt: 8, start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        r.walls = [w((0, 0), (10, 0)), w((10, 0), (10, 8)), w((10, 8), (0, 8)), w((0, 8), (0, 0))]
        r.floorOutline = [.init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 8), .init(x: 0, y: 8)]
        r.floorSqft = 80
        return r
    }

    /// A 4′ × 3′ shower in the top-left corner, open along y = 3 (its curb outside that).
    private func shower(curbless: Bool = false) -> AreaTakeoff {
        var t = AreaTakeoff()
        t.floor = .drawn
        t.curbless = curbless
        t.floorRect = AreaTakeoff.FloorRect(origin: .init(x: 0, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1), widthFt: 4, depthFt: 3)
        return t
    }

    @Test func theFloorLeavesOutTheShowerAndItsCurb() {
        let r = room
        let s = shower()
        // Two curb strips: along y = 3 (4′) and along x = 4 (3′), each 4½″ wide.
        let feet = s.floorFootprints(in: r)
        #expect(feet.count == 3)
        var floor = AreaTakeoff()
        floor.floor = .room
        #expect(abs(floor.floorSqft(in: r) - 80) < 1e-9)
        floor.cutouts = feet
        let curb = 4.5 / 12
        #expect(abs(floor.floorSqft(in: r) - (80 - 12 - (4 + 3) * curb)) < 1e-6)
        // Curbless: just the shower floor.
        floor.cutouts = shower(curbless: true).floorFootprints(in: r)
        #expect(abs(floor.floorSqft(in: r) - 68) < 1e-9)
    }

    @Test func noTileBoxesAndAMovedOutlineComeOffOnlyWhereTheyreOnTheFloor() {
        let r = room
        var floor = AreaTakeoff()
        floor.floor = .room
        // A 2′ × 2′ box half off the floor: only 2 sq ft comes off.
        floor.skipBoxes = [AreaTakeoff.FloorRect(origin: .init(x: 9, y: 2), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1), widthFt: 2, depthFt: 2)]
        #expect(abs(floor.floorSqft(in: r) - 78) < 1e-9)
        // The right-hand edge moved in 1′: 70 sq ft, and the box is now off the floor.
        floor.floorOutline = [.init(x: 0, y: 0), .init(x: 9, y: 0), .init(x: 9, y: 8), .init(x: 0, y: 8)]
        #expect(abs(floor.floorSqft(in: r) - 72) < 1e-9)
    }

    @Test func theRoomKeepsItsFloorAreasUpToDate() {
        var est = EstimateRoom()
        est.scan = room
        var s = EstimateSection(); s.area = .shower
        s.scanTakeoff = shower()
        var f = EstimateSection(); f.area = .floor
        var ft = AreaTakeoff(); ft.floor = .room
        f.scanTakeoff = ft
        est.sections = [s, f]
        est.refreshFloorCutouts(prices: StonePrices())
        let curb = 4.5 / 12
        #expect(abs(est.sections[1].measurements.sqft - ((80 - 12 - 7 * curb) * 100).rounded() / 100) < 0.011)
        // The shower made curbless: the floor's square feet follow.
        est.sections[0].scanTakeoff?.curbless = true
        est.refreshFloorCutouts(prices: StonePrices())
        #expect(abs(est.sections[1].measurements.sqft - 68) < 0.011)
    }

    @Test func aCurblessShowerInTheSameTileIsDrawnAsOneFloor() {
        let r = room
        let s = shower(curbless: true)
        var floor = AreaTakeoff()
        floor.floor = .room
        floor.cutouts = s.floorFootprints(in: r)
        let mosaic = TileChoice(tileType: .porcelain, tileSize: .mosaic, layout: .straightStacked)
        let big = TileChoice.usual
        // Same tile: no hole; the shower floor is covered by the floor's tile.
        let same = Room3DContent.floorShape(floor, tile: big, scan: r, showers: [(s.floorRect!.corners, true, big)])
        #expect(same.holes.isEmpty && same.continuous.count == 1)
        // A different tile, or a curb: a hole.
        let other = Room3DContent.floorShape(floor, tile: big, scan: r, showers: [(s.floorRect!.corners, true, mosaic)])
        #expect(other.holes.count == 1 && other.continuous.isEmpty)
        // Priced apart either way.
        #expect(abs(floor.floorSqft(in: r) - 68) < 1e-9)
    }

    @Test func theNewFloorFieldsAreSaved() throws {
        var t = AreaTakeoff()
        t.floor = .room
        t.skipBoxes = [AreaTakeoff.FloorRect(origin: .init(x: 1, y: 1), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1), widthFt: 2, depthFt: 3)]
        t.floorOutline = [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1)]
        t.cutouts = [[.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 1, y: 1)]]
        t.scannedSkipsAdded = true
        let back = try JSONDecoder().decode(AreaTakeoff.self, from: JSONEncoder().encode(t))
        #expect(back == t)
    }
}
