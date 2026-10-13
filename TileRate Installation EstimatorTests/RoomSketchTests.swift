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
