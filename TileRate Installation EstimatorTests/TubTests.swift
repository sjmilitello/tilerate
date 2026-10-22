import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Tubs on the model (owner, 2026-10-19): placed with a tap, 60″ × 30″; an
/// alcove tub in a corner gets a full wall at its open end, one tapped in a
/// space of three walls fills it; tile from the rim (15″) up; a drop-in's
/// deck (20″, 3″ past the tub on its open sides) in tile on its own line or
/// stone in its own group; a deck beside a shower ties to it (no curb along
/// it; the deck stops there or runs in as the shower's bench); freestanding
/// tubs are the room's, decoration only.
struct TubTests {
    /// An 8′ × 10′ sketched room, 8′ ceiling, and a tub placed in a corner.
    private func placed() -> (ScannedRoom, AreaTakeoff) {
        let room = RoomSketch.room(.rectangle, .init(widthIn: 96, depthIn: 120, ceilingIn: 96))
        let corner = room.insideCorners()[0]
        let tap = ScannedRoom.Point(x: corner.at.x + (corner.a.x + corner.b.x) * 0.5,
                                    y: corner.at.y + (corner.a.y + corner.b.y) * 0.5)
        var t = AreaTakeoff()
        let how = t.placeTub(near: tap, in: room)
        #expect(how == .corner)
        return (room, t)
    }

    private func section(_ t: AreaTakeoff, _ room: ScannedRoom, prices: StonePrices = .init()) -> EstimateSection {
        var s = EstimateSection()
        s.area = .tub
        t.apply(room, to: &s, prices: prices)
        return s
    }

    /// A room with a space of three walls: the back wall, the room's side and
    /// a full wall 5½′ along it, 3′ deep.
    private func roomWithAlcove() -> ScannedRoom {
        var r = RoomSketch.room(.rectangle, .init(widthIn: 120, depthIn: 96, ceilingIn: 96))
        let corner = r.insideCorners()[0]
        let side = corner.a, out = corner.b
        let a = ScannedRoom.Point(x: corner.at.x + side.x * 5.5, y: corner.at.y + side.y * 5.5)
        _ = r.addPlannedWall(from: a, to: .init(x: a.x + out.x * 3, y: a.y + out.y * 3), heightIn: 96, thicknessIn: 0.01)
        return r
    }

    @Test func aTapPutsA60By30TubInTheCornerAndTilesTheWallsAlongIt() throws {
        let (room, t) = placed()
        let r = try #require(t.tubRect)
        #expect(abs(r.widthFt - 5) < 1e-9 && abs(r.depthFt - 2.5) < 1e-9)
        #expect(t.pieces.count == 2)
        let lengths = Set(t.pieces.map { (($0.toFt - $0.fromFt) * 12).rounded() })
        #expect(lengths == [60, 30])
        #expect(t.pieces.allSatisfy { $0.heightIn == 96 })
        #expect(abs(t.floorWidthFt - 5) < 1e-9 && abs(t.floorDepthFt - 2.5) < 1e-9)
        #expect(room.walls.count == 4)
    }

    @Test func anAlcoveTubInACornerGetsAFullWallAtItsOpenEnd() throws {
        var (room, t) = placed()
        #expect(t.tubOpenEnds(in: room).count == 1)
        t.closeTubEnds(in: &room, thicknessIn: 4.5)
        let wall = try #require(room.walls.first { $0.planned })
        #expect(!room.isKneeWall(wall))
        #expect(abs(wall.lengthFt - 2.5) < 1e-6)
        // Tiled on the tub's side: now three walls round it, and no open end.
        #expect(t.pieces.count == 3)
        #expect(t.tubOpenEnds(in: room).isEmpty)
        // The new wall's tile is under the rim too: 10′ of wall round the tub.
        let expected = 10.0 * 8 - 10.0 * 15 / 12
        #expect(abs(section(t, room).measurements.sqft - expected) < 0.02)
    }

    @Test func aTapInASpaceOfThreeWallsFillsIt() throws {
        let room = roomWithAlcove()
        let corner = room.insideCorners().first { c in
            room.cove(around: .init(x: c.at.x + (c.a.x + c.b.x) * 1.2, y: c.at.y + (c.a.y + c.b.y) * 1.2)) != nil
        }
        let c = try #require(corner)
        var t = AreaTakeoff()
        let how = t.placeTub(near: .init(x: c.at.x + (c.a.x + c.b.x) * 1.2, y: c.at.y + (c.a.y + c.b.y) * 1.2), in: room)
        #expect(how == .cove)
        let r = try #require(t.tubRect)
        #expect(abs(max(r.widthFt, r.depthFt) - 5.5) < 0.05)
        #expect(t.tubOpenEnds(in: room).isEmpty)
    }

    @Test func theWallBelowTheRimIsNotCounted() {
        let (room, t) = placed()
        // 7½′ of wall 8′ high, less 7½′ × 15″ under the rim.
        let expected = 60 - 7.5 * 15 / 12, raised = 60 - 7.5 * 20 / 12
        #expect(abs(section(t, room).measurements.sqft - expected) < 0.01)
        var high = t
        high.tubRimIn = 20
        #expect(abs(section(high, room).measurements.sqft - raised) < 0.01)
    }

    @Test func aDropInsDeckRunsPastTheTubOnItsOpenSidesAndTheWallsFollow() throws {
        var (room, t) = placed()
        _ = room
        t.setTubKind(.dropIn, in: room)
        let r = try #require(t.tubRect)
        #expect(abs(r.widthFt - 5.25) < 1e-9 && abs(r.depthFt - 2.75) < 1e-9)
        let inner = try #require(t.tubInDeck(in: room))
        #expect(abs(inner.widthFt - 5) < 1e-9 && abs(inner.depthFt - 2.5) < 1e-9)
        #expect(t.tubRimHeightIn == 20)
        let deck = t.tubDeckSqft(in: room)
        #expect(abs(deck.top - (5.25 * 2.75 - 12.5)) < 1e-9)
        #expect(abs(deck.front - (5.25 + 2.75) * 20 / 12) < 1e-9)
        let lengths = Set(t.pieces.map { (($0.toFt - $0.fromFt) * 12).rounded() })
        #expect(lengths == [63, 33])
        // A drop-in in a corner can be closed in with a full wall too.
        #expect(t.tubOpenEnds(in: room).count == 1)
        t.setTubKind(.alcove, in: room)
        #expect(abs(t.tubRect!.widthFt - 5) < 1e-9 && abs(t.tubRect!.depthFt - 2.5) < 1e-9)
    }

    @Test func aTiledDeckIsItsOwnLineAndAStoneDeckGoesInItsGroup() {
        var (room, t) = placed()
        _ = room
        t.setTubKind(.dropIn, in: room)
        var prices = StonePrices()
        prices.tubDeckTilePerSqft = 30
        let tiled = section(t, room, prices: prices)
        let line = tiled.additionsLabor.first { $0.activity == "Tub deck tile" }
        let deck = t.tubDeckSqft(in: room)
        let qty = ((deck.top + deck.front) * 100).rounded() / 100
        #expect(line != nil && abs((line?.qty ?? 0) - qty) < 0.011)
        #expect(line?.rate == 30)
        #expect(!tiled.additionsLabor.contains { $0.activity == "Stone tub deck" })

        t.trim = [.init(key: "tubDeck:top", stone: true, finish: .stone), .init(key: "tubDeck:front", stone: true, finish: .stone)]
        prices.parts[.tubDeckTop] = StoneRate(bySqft: true, perSqft: 50)
        prices.parts[.tubDeckFront] = StoneRate(bySqft: true, perSqft: 50)
        let stone = section(t, room, prices: prices)
        #expect(!stone.additionsLabor.contains { $0.activity == "Tub deck tile" })
        let s = stone.additionsLabor.first { $0.activity == "Stone tub deck" }
        #expect(s != nil && abs((s?.qty ?? 0) - qty) < 0.011 && s?.unit == "sq ft")
        let cuts = t.trimPieces(in: room, area: .tub, curbHeightIn: 4, prices: prices).flatMap(\.cuts)
        #expect(cuts.filter { $0.type == StonePart.tubDeckTop.rawValue }.count == 1)
        #expect(cuts.filter { $0.type == StonePart.tubDeckFront.rawValue }.count == 2)
        var alcove = t
        alcove.setTubKind(.alcove, in: room)
        #expect(!section(alcove, room, prices: prices).additionsLabor.contains { $0.activity.contains("deck") })
    }

    /// A drop-in tub in a corner of the room and a shower tapped beside it,
    /// along the same back wall.
    private func tubAndShower() -> EstimateRoom {
        let (scan, tub0) = placed()
        var tub = tub0
        tub.setTubKind(.dropIn, in: scan)
        var room = EstimateRoom(name: "Bath")
        var r = scan
        r.tubOutline = tub.tubRect!.corners
        r.tubPlaced = true
        room.scan = r
        var tubSection = EstimateSection(); tubSection.area = .tub; tubSection.startWithUsualTile()
        tub.apply(r, to: &tubSection)
        let d = tub.tubRect!
        let tap = ScannedRoom.Point(x: d.origin.x + d.u.x * (d.widthFt + 1) + d.v.x * 1,
                                    y: d.origin.y + d.u.y * (d.widthFt + 1) + d.v.y * 1)
        var shower = AreaTakeoff()
        shower.floor = .drawn
        _ = shower.placeShower(near: tap, in: r, curbWidthFt: 4.5 / 12)
        var showerSection = EstimateSection(); showerSection.area = .shower; showerSection.startWithUsualTile()
        shower.apply(r, to: &showerSection)
        room.sections = [tubSection, showerSection]
        return room
    }

    @Test func aShowerBesideADeckEndsAtItWithNoCurbAlongIt() throws {
        var room = tubAndShower()
        let scan = try #require(room.scan)
        let shower = try #require(room.sections[1].scanTakeoff)
        let deck = try #require(room.sections[0].scanTakeoff?.tubRect)
        let f = try #require(shower.floorRect)
        // It doesn't overlap the deck.
        let inside = f.corners.filter { p in
            let du = (p.x - deck.origin.x) * deck.u.x + (p.y - deck.origin.y) * deck.u.y
            let dv = (p.x - deck.origin.x) * deck.v.x + (p.y - deck.origin.y) * deck.v.y
            return du > 0.05 && du < deck.widthFt - 0.05 && dv > 0.05 && dv < deck.depthFt - 0.05
        }
        #expect(inside.isEmpty)
        // No curb along the deck, and no jamb at it.
        for side in shower.openSides(in: scan) {
            let mid = ScannedRoom.Point(x: (side.a.x + side.b.x) / 2, y: (side.a.y + side.b.y) / 2)
            let onDeck = AreaTakeoff.edgeTouches(side.a, side.b, [deck.corners])
            #expect(!onDeck, "curb at \(mid)")
            #expect(side.startWall?.id != AreaTakeoff.tubDeckWallID && side.endWall?.id != AreaTakeoff.tubDeckWallID)
        }
        // The room ties them: the tub knows the shower; its deck's end stays front.
        let frontBefore = room.sections[0].scanTakeoff!.tubDeckSqft(in: scan).front
        room.tieTubsAndShowers(prices: StonePrices())
        let tub = try #require(room.sections[0].scanTakeoff)
        #expect(tub.tubNeighbors.count == 1)
        #expect(abs(tub.tubDeckSqft(in: scan).front - frontBefore) < 1e-9)
        let benches = room.sections[1].scanTakeoff?.items.filter(\.fromTubDeck) ?? []
        #expect(benches.isEmpty)
    }

    @Test func aDeckRunningIntoTheShowerIsTheShowersBench() throws {
        var room = tubAndShower()
        let scan = try #require(room.scan)
        room.tieTubsAndShowers(prices: StonePrices())
        let frontStops = room.sections[0].scanTakeoff!.tubDeckSqft(in: scan).front
        room.sections[0].scanTakeoff?.tubDeckIntoShower = true
        room.tieTubsAndShowers(prices: StonePrices())
        let bench = try #require(room.sections[1].scanTakeoff?.items.first(where: { $0.fromTubDeck }))
        #expect(bench.kind == .framedBench)
        #expect(bench.heightIn == 20)
        #expect(abs(bench.depthIn - 33) < 0.01)
        #expect(abs((bench.toFt - bench.fromFt) * 12 - 15) < 0.01)
        // The deck's end is under the bench now: less deck front.
        let tub = try #require(room.sections[0].scanTakeoff)
        let endFace = 2.75 * 20 / 12
        #expect(abs(tub.tubDeckSqft(in: scan).front - (frontStops - endFace)) < 1e-6)
        // Back to stopping at the shower: the bench goes.
        room.sections[0].scanTakeoff?.tubDeckIntoShower = false
        room.tieTubsAndShowers(prices: StonePrices())
        let left = room.sections[1].scanTakeoff?.items.filter(\.fromTubDeck) ?? []
        #expect(left.isEmpty)
    }

    @Test func deletingTheTubSurroundTakesItsTubOffTheRoom() throws {
        var room = tubAndShower()
        room.sections[0].scanTakeoff?.tubDeckIntoShower = true
        room.refreshFloorCutouts(prices: StonePrices())
        #expect(room.sections[1].scanTakeoff?.items.contains(where: \.fromTubDeck) == true)
        room.sections.remove(at: 0)
        room.refreshFloorCutouts(prices: StonePrices())
        let scan = try #require(room.scan)
        #expect(scan.tubOutline.isEmpty && !scan.tubPlaced && scan.tubLengthFt == nil)
        #expect(room.sections[0].scanTakeoff?.items.contains(where: \.fromTubDeck) == false)
        // A scanned tub with no tub surround stays (a conversion, say).
        var scanned = room
        scanned.scan?.tubOutline = AreaTakeoff.FloorRect(origin: .init(x: 0, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1),
                                                          widthFt: 5, depthFt: 2.5).corners
        scanned.refreshFloorCutouts(prices: StonePrices())
        #expect(scanned.scan?.tubOutline.count == 4)
    }

    @Test func aDraggedShowerCatchesOnTheDeckBesideIt() {
        // A deck 0–5¼′ along the wall; a shower floor dragged to start 1½″ past it.
        let deck: [ScannedRoom.Point] = [.init(x: 0, y: 0), .init(x: 5.25, y: 0), .init(x: 5.25, y: 2.75), .init(x: 0, y: 2.75)]
        let floor = AreaTakeoff.FloorRect(origin: .init(x: 5.375, y: 0), u: .init(x: 1, y: 0), v: .init(x: 0, y: 1), widthFt: 3, depthFt: 3)
        let segs = deck.indices.map { (deck[$0], deck[($0 + 1) % 4]) }
        let caught = floor.caught(on: segs, reach: 0.2)
        #expect(abs(caught.origin.x - 5.25) < 1e-9 && abs(caught.origin.y) < 1e-9)
        // Out of reach, it stays where it was.
        #expect(floor.caught(on: segs, reach: 0.05) == floor)
    }

    @Test func freestandingTubsAreTheRoomsAndChangeNoTile() throws {
        var room = RoomSketch.room(.rectangle, .init(widthIn: 96, depthIn: 120, ceilingIn: 96))
        room.addFreestandingTub(at: room.middle)
        let r = try #require(room.freestandingTubs.first)
        #expect(abs(r.widthFt * 12 - 66) < 1e-9 && abs(r.depthFt * 12 - 32) < 1e-9)
        #expect(hypot(r.center.x - room.middle.x, r.center.y - room.middle.y) < 1e-9)
        let turned = r.turnedInPlace
        #expect(hypot(turned.center.x - r.center.x, turned.center.y - r.center.y) < 1e-9)
        #expect(turned.widthFt == r.depthFt)
        // The floor runs under it.
        var floor = AreaTakeoff()
        floor.floor = .room
        #expect(abs(floor.floorSqft(in: room) - 80) < 0.01)
        let back = try JSONDecoder().decode(ScannedRoom.self, from: JSONEncoder().encode(room))
        #expect(back.freestandingTubs == room.freestandingTubs)
    }

    @Test func theFloorLeavesTheTubOut() {
        let (room, t) = placed()
        #expect(t.floorFootprints(in: room).count == 1)
        var scan = room
        scan.tubOutline = t.tubRect!.corners
        var floor = AreaTakeoff()
        floor.floor = .room
        floor.excludeTub = true
        floor.cutouts = t.floorFootprints(in: scan)
        #expect(abs(floor.floorSqft(in: scan) - (80 - 12.5)) < 0.01)
    }

    @Test func aScannedTubBecomesTheTubSurroundsOwn() {
        let room = ScannedRoom.sample
        let t = AreaTakeoff.starting(for: .tub, room: room, otherAreas: [])
        #expect(t.tubRect != nil)
        #expect(abs((t.tubRect?.widthFt ?? 0) * (t.tubRect?.depthFt ?? 0) - room.tubSqft) < 0.01)
    }

    @Test func theTubIsSavedAndOldAreasReadWithoutIt() throws {
        var (room, t) = placed()
        t.setTubKind(.dropIn, in: room)
        t.tubLipIn = 4
        t.tubDeckIntoShower = true
        let back = try JSONDecoder().decode(AreaTakeoff.self, from: JSONEncoder().encode(t))
        #expect(back.tubRect == t.tubRect && back.tubKind == .dropIn && back.tubLipIn == 4 && back.tubDeckIntoShower)
        let old = try JSONDecoder().decode(AreaTakeoff.self, from: Data("{}".utf8))
        #expect(old.tubRect == nil && old.tubKind == .alcove && old.tubRimHeightIn == 15 && !old.tubDeckIntoShower)
    }
}
