import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Vanities and toilets (owner, 2026-10-19): added from any area's model; a
/// vanity is 36″ × 21″ against the wall, a stone top 1″ past it on open
/// sides, sinks (2 from 60″), and a backsplash — stone 4″, tile, or none — on
/// the walls it touches; its own area prices it.
struct VanityTests {
    /// An 8′ × 10′ room with a vanity tapped near the middle of a wall.
    private func room() -> ScannedRoom {
        var r = RoomSketch.room(.rectangle, .init(widthIn: 96, depthIn: 120, ceilingIn: 96))
        let w = r.walls[0]
        let mid = r.point(on: w, along: w.lengthFt / 2)
        let m = r.middle
        r.addVanity(at: .init(x: mid.x + (m.x - mid.x) * 0.1, y: mid.y + (m.y - mid.y) * 0.1))
        return r
    }

    @Test func aVanityStartsAgainstTheWallWithAStoneBacksplash() throws {
        let r = room()
        let v = try #require(r.vanities.first)
        #expect(abs(v.rect.widthFt * 12 - 36) < 1e-9 && abs(v.rect.depthFt * 12 - 21) < 1e-9)
        #expect(v.splash == .stone && v.splashHeightIn == 4 && v.sinks == 1)
        #expect(v.splashWalls == [r.walls[0].id])
        #expect(r.wallsTouching(v).map(\.id) == [r.walls[0].id])
        // The top: 1″ past it at the front and both open ends.
        let t = r.vanityTop(v)
        #expect(abs(t.widthFt * 12 - 38) < 1e-9 && abs(t.depthFt * 12 - 22) < 1e-9)
        let m = r.vanityMeasures(v)
        #expect(abs(m.topSqft - 38.0 * 22 / 144) < 1e-9)
        #expect(abs(m.splashFt * 12 - 38) < 1e-6 && abs(m.splashSqft - 38.0 * 4 / 144) < 1e-6)
    }

    @Test func aWideVanityHasTwoSinksUnlessTyped() {
        var v = ScannedRoom.Vanity()
        v.rect.widthFt = 5
        v.fitSinks()
        #expect(v.sinks == 2)
        v.sinks = 1; v.sinksTyped = true
        v.rect.widthFt = 6
        v.fitSinks()
        #expect(v.sinks == 1)
    }

    @Test func aVanityInACornerCanHaveItsBacksplashOnBothWalls() throws {
        var r = RoomSketch.room(.rectangle, .init(widthIn: 96, depthIn: 120, ceilingIn: 96))
        let c = r.insideCorners()[0]
        r.addVanity(at: .init(x: c.at.x + c.a.x * 0.5 + c.b.x * 0.3, y: c.at.y + c.a.y * 0.5 + c.b.y * 0.3))
        var v = try #require(r.vanities.first)
        #expect(r.wallsTouching(v).count == 2)
        v.splashWalls = r.wallsTouching(v).map(\.id)
        // Two walls: the back (the top's 37″, one open end) and the end (22″).
        #expect(abs(r.vanityMeasures(v).splashFt * 12 - (37 + 22)) < 1e-6)
    }

    @Test func eachVanityHasItsOwnAreaThatPricesItsStoneAndTile() throws {
        var er = EstimateRoom(name: "Bath")
        er.scan = room()
        var prices = StonePrices()
        prices.parts[.vanitySplash] = StoneRate(perLinFt: 30)
        er.refreshFloorCutouts(prices: prices)
        let s = try #require(er.sections.first { $0.scanTakeoff?.vanityID != nil })
        #expect(s.area == .backsplash)
        #expect(AreaFlowView.areaName(s, in: er.sections) == "Vanity")
        // Stone backsplash: its own line, no tile.
        let line = try #require(s.additionsLabor.first { $0.activity == "Stone vanity backsplash" })
        #expect(abs(line.qty - (38.0 / 12 * 100).rounded() / 100) < 0.011 && line.rate == 30)
        #expect(s.measurements.sqft == 0)
        // Tile: the tile's square feet, and no stone line.
        er.scan!.vanities[0].splash = .tile
        er.refreshFloorCutouts(prices: prices)
        let tiled = er.sections.first { $0.scanTakeoff?.vanityID != nil }!
        #expect(abs(tiled.measurements.sqft - (38.0 * 4 / 144 * 100).rounded() / 100) < 0.011)
        #expect(!tiled.additionsLabor.contains { $0.activity == "Stone vanity backsplash" })
        #expect(er.scan!.vanities[0].splashTile != nil)
        // Removed: its area goes too.
        er.scan!.vanities = []
        er.refreshFloorCutouts(prices: prices)
        #expect(!er.sections.contains { $0.scanTakeoff?.vanityID != nil })
    }

    @Test func theTopIsChargedAsMaterialsOnlyWhenStoneMaterialIsItsOwnLine() throws {
        var er = EstimateRoom(name: "Bath")
        var scan = room()
        scan.vanities[0].rect.widthFt = 5
        scan.vanities[0].fitSinks()
        er.scan = scan
        var prices = StonePrices()
        prices.vanityTopPerSqft = 60
        prices.sinkCutoutEach = 150
        er.refreshFloorCutouts(prices: prices)
        var s = er.sections.first { $0.scanTakeoff?.vanityID != nil }!
        #expect(!s.additionsMaterials.contains { $0.activity == "Vanity top" })
        prices.materialSeparate = true
        er.refreshFloorCutouts(prices: prices)
        s = er.sections.first { $0.scanTakeoff?.vanityID != nil }!
        let top = try #require(s.additionsMaterials.first { $0.activity == "Vanity top" })
        let sinks = try #require(s.additionsMaterials.first { $0.activity == "Sink cut-outs" })
        #expect(abs(top.qty - (62.0 * 22 / 144 * 100).rounded() / 100) < 0.011 && top.rate == 60 && top.taxable)
        #expect(sinks.qty == 2 && sinks.rate == 150)
    }

    @Test func theCutlistHasTheTopAndAStoneBacksplash() throws {
        var er = EstimateRoom(name: "Bath")
        er.scan = room()
        er.refreshFloorCutouts(prices: StonePrices())
        let t = try #require(er.sections.first { $0.scanTakeoff?.vanityID != nil }?.scanTakeoff)
        let cuts = t.cutlist(in: er.scan!, area: .backsplash, curbHeightIn: 4, prices: StonePrices())
        let top = try #require(cuts.first { $0.type == StonePart.vanityTop.rawValue })
        #expect(abs(top.lengthIn - 38) < 0.01 && abs(top.widthIn - 22) < 0.01)
        let splash = try #require(cuts.first { $0.type == StonePart.vanitySplash.rawValue })
        #expect(abs(splash.lengthIn - 38) < 0.01 && splash.widthIn == 4)
    }

    @Test func aToiletGoesAgainstTheWallAndIsSaved() throws {
        var r = RoomSketch.room(.rectangle, .init(widthIn: 96, depthIn: 120, ceilingIn: 96))
        r.addToilet(at: r.middle)
        let t = try #require(r.toilets.first)
        #expect(abs(t.widthFt * 12 - 20) < 1e-9 && abs(t.depthFt * 12 - 28) < 1e-9)
        let saved = room()
        let back = try JSONDecoder().decode(ScannedRoom.self, from: JSONEncoder().encode(saved))
        #expect(back.vanities == saved.vanities)
        let r2 = try JSONDecoder().decode(ScannedRoom.self, from: JSONEncoder().encode(r))
        #expect(r2.toilets == r.toilets)
        let old = try JSONDecoder().decode(ScannedRoom.Vanity.self, from: Data("{}".utf8))
        #expect(old.splash == .stone && old.splashHeightIn == 4 && old.overhangIn == 1)
    }
}
