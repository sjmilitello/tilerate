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
