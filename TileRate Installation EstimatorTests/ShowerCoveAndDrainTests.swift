import Foundation
import SceneKit
import Testing
@testable import TileRate_Installation_Estimator

/// Placing a shower (a cove filled, else 48″ × 48″ in a corner), curbless
/// showers and drains (owner's calls, 2026-10-08).
struct ShowerCoveAndDrainTests {
    private let curb = 4.5 / 12

    /// A 10′ × 8′ room with a 5′ × 3′ cove off its top wall, between x = 2 and 7.
    private func coveRoom() -> ScannedRoom {
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
        return r
    }

    private func placedInCove() -> (ScannedRoom, AreaTakeoff) {
        let room = coveRoom()
        var t = AreaTakeoff()
        let placed = t.placeShower(near: .init(x: 4, y: -1.5), in: room, curbWidthFt: curb)
        #expect(placed)
        return (room, t)
    }

    @Test func aTapInsideACoveFillsItWithTheCurbFlushToItsOutsideCorners() {
        let (room, t) = placedInCove()
        let r = t.floorRect!
        #expect(abs(r.widthFt - 5) < 1e-9)
        // The floor stops at the curb's inside face; the curb's outside face is on the corners (y = 0).
        #expect(abs(r.depthFt - (3 - curb)) < 1e-9)
        #expect(abs((t.coveDepthFt ?? 0) - 3) < 1e-9)
        let corners = r.corners
        #expect(abs(corners.map(\.y).max()! - (0 - curb)) < 1e-9)
        #expect(abs(corners.map(\.y).min()! - (-3)) < 1e-9)
        // Its three walls tiled; one curb across the front.
        #expect(Set(t.pieces.map(\.wallID)) == Set([room.walls[1].id, room.walls[2].id, room.walls[3].id]))
        let pieces = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        #expect(abs((pieces.first { $0.key == "curb" }?.lengthFt ?? 0) - 5) < 1e-9)
    }

    @Test func aTapInTheOpenRoomIsNotACove() {
        let room = coveRoom()
        #expect(room.cove(around: .init(x: 5, y: 4)) == nil)
        #expect(ScannedRoom.sample.cove(around: .init(x: 4.5, y: 4)) == nil)
    }

    @Test func curblessFillsTheCoveAndPutsCurblessShowerOnTheEstimate() {
        var (room, t) = placedInCove()
        t.setCurbless(true, curbWidthFt: curb)
        #expect(abs(t.floorRect!.depthFt - 3) < 1e-9)
        // No curb; the jambs start at the floor.
        let pieces = t.trimPieces(in: room, area: .shower, curbHeightIn: 4)
        #expect(!pieces.contains { $0.kind == .curb })
        #expect(pieces.filter { $0.kind == .jamb }.allSatisfy { abs($0.lengthFt - 8) < 1e-9 })
        #expect(t.curbEdges(in: room).isEmpty)

        var section = EstimateSection()
        section.area = .shower
        var prices = StonePrices()
        prices.curblessItem?.price = 12
        prices.curblessItem?.minimum = 300
        t.apply(room, to: &section, prices: prices)
        let line = section.additionsLabor.first { $0.activity == "Curbless Shower" }
        #expect(line != nil)
        #expect(abs((line?.qty ?? 0) - 15) < 1e-9)          // 5′ × 3′ of shower floor
        #expect(line?.amount == 300)                          // 15 × $12 = $180: the minimum
        #expect(line?.unit == "sq ft")

        // The curb back: the floor stops at it again, and the line goes.
        t.setCurbless(false, curbWidthFt: curb)
        #expect(abs(t.floorRect!.depthFt - (3 - curb)) < 1e-9)
        t.apply(room, to: &section, prices: prices)
        #expect(!section.additionsLabor.contains { $0.activity == "Curbless Shower" })
    }

    @Test func aCornerShowerKeepsItsSizeWithoutACurb() {
        let room = ScannedRoom.sample
        var t = AreaTakeoff()
        _ = t.placeShower(near: .init(x: 8.6, y: 7.5), in: room, curbWidthFt: curb)
        t.setCurbless(true, curbWidthFt: curb)
        #expect(abs(t.floorRect!.widthFt - 4) < 1e-9 && abs(t.floorRect!.depthFt - 4) < 1e-9)
    }

    @Test func aSquareDrainSitsInTheMiddleAndSnapsBackToIt() {
        let (_, t) = placedInCove()
        let r = t.floorRect!
        let d = t.drainShown()!
        #expect(d.kind == .center)
        #expect(abs(d.alongWidthFt - r.widthFt / 2) < 1e-9 && abs(d.alongDepthFt - r.depthFt / 2) < 1e-9)
        // Dragged 1″ off the middle: back to it. 6″ off: stays, to the sixteenth.
        let near = AreaTakeoff.snappedDrain(d, in: r, alongWidth: r.widthFt / 2 + 1.0 / 12, alongDepth: 1)
        #expect(abs(near.alongWidthFt - r.widthFt / 2) < 1e-9)
        let off = AreaTakeoff.snappedDrain(d, in: r, alongWidth: r.widthFt / 2 + 0.5, alongDepth: 1)
        #expect(abs(off.alongWidthFt - (r.widthFt / 2 + 0.5)) < 1e-9)
    }

    @Test func aLinearDrainStartsAgainstTheLongestWallAndGoesOnTheEstimate() {
        var (room, t) = placedInCove()
        let r = t.floorRect!
        t.drain = t.startingLinearDrain(in: room)
        let d = t.drainShown()!
        // The back wall (C, 5′), wall to wall, flush against it.
        #expect(d.kind == .linear && d.runsAlongWidth)
        #expect(abs(d.lengthFt - 5) < 1e-9)
        let outline = t.drainOutline(d)
        #expect(abs(outline.map(\.y).min()! - (-3)) < 1e-9)
        // It snaps flush to the open side when moved there (curbless: the outside corners).
        let atFront = AreaTakeoff.snappedDrain(d, in: r, alongWidth: d.alongWidthFt, alongDepth: r.depthFt - 0.1)
        #expect(abs(atFront.alongDepthFt - (r.depthFt - AreaTakeoff.linearDrainWidthFt / 2)) < 1e-9)
        // Turned: along the depth, no longer than the floor.
        let turned = AreaTakeoff.turnedDrain(d, in: r)
        #expect(!turned.runsAlongWidth && turned.lengthFt <= r.depthFt + 1e-9)

        var section = EstimateSection()
        section.area = .shower
        var prices = StonePrices()
        prices.linearDrainItem?.price = 90
        prices.linearDrainItem?.minimum = 400
        t.apply(room, to: &section, prices: prices)
        let line = section.additionsMaterials.first { $0.activity == "Linear Drain" }
        #expect(abs((line?.qty ?? 0) - 5) < 1e-9)
        #expect(line?.amount == 450)
        #expect(line?.taxable == true && line?.unit == "lin ft")
        // Back to a square drain: the line goes.
        t.drain = nil
        t.apply(room, to: &section, prices: prices)
        #expect(!section.additionsMaterials.contains { $0.activity == "Linear Drain" })
    }

    @Test func savedRatesGetTheNewItemsOnceAndDeletingThemSticks() throws {
        // Rates saved before: no flag, no items.
        var old = Rates()
        old.priceList.removeAll { item in PriceListItem.showerDrainItems.contains { $0.id == item.id } }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "showerDrainItemsAdded")
        let read = try JSONDecoder().decode(Rates.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(read.priceList.contains { $0.id == PriceListItem.curblessShower.id })
        #expect(read.priceList.contains { $0.id == PriceListItem.linearDrain.id })
        // Deleted in Admin and saved: they stay deleted.
        var edited = read
        edited.priceList.removeAll { $0.id == PriceListItem.linearDrain.id }
        let again = try JSONDecoder().decode(Rates.self, from: JSONEncoder().encode(edited))
        #expect(!again.priceList.contains { $0.id == PriceListItem.linearDrain.id })
        #expect(StonePrices(rates: again).linearDrainItem == nil)
    }

    @Test func theNewFieldsSurviveSavingAndOldTakeoffsStillLoad() throws {
        var (_, t) = placedInCove()
        t.setCurbless(true, curbWidthFt: curb)
        t.drain = .init(kind: .linear, alongWidthFt: 2.5, alongDepthFt: 0.1, lengthFt: 4, runsAlongWidth: true)
        let back = try JSONDecoder().decode(AreaTakeoff.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        let old = try JSONDecoder().decode(AreaTakeoff.self, from: Data(#"{"pieces":[],"floor":"drawn"}"#.utf8))
        #expect(!old.curbless && old.drain == nil && old.coveDepthFt == nil)
    }

    @Test func theCurbIsFourAndAHalfInchesWhateverTheStoneOnTopIs() {
        // Admin's stone curb width is the stone on top, which overhangs the curb.
        var prices = StonePrices()
        prices.stone[.curb] = StoneRate(perLinFt: 30, widthIn: 6)
        #expect(abs(prices.curbWidthFt - 4.5 / 12) < 1e-12)
    }

    @Test func inThreeDTheTileIsOnTheShowersSideOfAPartition() throws {
        // A 12′ × 10′ room; a partition (P) from wall A at x = 4 into the room,
        // 4′ long. The shower is the cove behind it (x 0–4, y 0–4): the side of P
        // away from the room's middle.
        var r = ScannedRoom()
        func wall(_ l: String, _ a: (Double, Double), _ b: (Double, Double)) -> ScannedRoom.Wall {
            ScannedRoom.Wall(label: l, lengthFt: hypot(b.0 - a.0, b.1 - a.1), heightFt: 8,
                             start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        r.walls = [wall("A", (0, 0), (12, 0)), wall("B", (12, 0), (12, 10)), wall("C", (12, 10), (0, 10)),
                   wall("D", (0, 10), (0, 0)), wall("P", (4, 0), (4, 4))]
        let p = r.walls[4]
        var t = AreaTakeoff()
        t.floor = .drawn
        t.floorRect = .init(origin: .init(x: 0, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1), widthFt: 4, depthFt: 4)
        t.pieces = [.init(wallID: p.id, fromFt: 0, toFt: 4, heightIn: 96)]
        let c = Room3DContent(room: r, takeoff: t, area: .shower, tile: nil, floorTile: nil, others: [],
                              curbHeightIn: 4, stoneParts: [], showFixtures: false)
        let scene = Room3DScene.build(c)
        let node = try #require(scene.rootNode.childNode(withName: "wall|\(p.id.uuidString)", recursively: true))
        // The tile: planes standing just off the wall's face.
        let tiles = node.childNodes.filter { $0.geometry is SCNPlane && abs(abs($0.position.z) - Float(4.0 / 12 / 2 + 0.006)) < 1e-4 }
        #expect(!tiles.isEmpty)
        for tile in tiles {
            #expect(node.convertPosition(tile.position, to: nil).x < 4)     // on the shower's side
        }
        // The partition is solid, so its room side shows too.
        #expect(node.childNodes.contains { $0.geometry is SCNBox })
    }

    @Test func aNicheKeepsItsOwnTileAndOldNichesUseTheWalls() throws {
        var n = AreaTakeoff.Item()
        n.kind = .niche
        n.tile = TileChoice(tileType: .porcelain, tileSize: .mosaic, layout: .straightStacked)
        let back = try JSONDecoder().decode(AreaTakeoff.Item.self, from: JSONEncoder().encode(n))
        #expect(back.tile == n.tile)
        let old = try JSONDecoder().decode(AreaTakeoff.Item.self, from: Data(#"{"kind":"niche","heightIn":24}"#.utf8))
        #expect(old.tile == nil && old.heightIn == 24)
    }
}
