import Testing
import Foundation
import UIKit
@testable import TileRate_Installation_Estimator

/// How a tile looks (owner, 2026-10-18): colour, look, grout (Laticrete
/// PermaColor by name), variation, finish and its name in My Tiles —
/// drawing and wording only, and nothing changes for tiles saved before.
struct TileLookTests {
    @Test func tilesSavedBeforeReadWithNoAppearance() throws {
        let old = #"{"tileType":"Porcelain","tileSize":"Rectangle","layout":"Running Bond","tileWidthIn":12,"tileLengthIn":24}"#
        let t = try JSONDecoder().decode(TileChoice.self, from: Data(old.utf8))
        #expect(t.appearance == nil && t.tileWidthIn == 12)
        var s = EstimateSection()
        s.tileType = .porcelain; s.tileSize = .rectangle
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(back.tileAppearance == nil && back.mainTile?.appearance == nil)
    }

    @Test func anAppearanceSavesAndReadsBack() throws {
        var a = TileAppearance()
        a.colour = "#658679"; a.look = .marble; a.pattern = .thinVeins; a.accent = "#5D798B"
        a.grout = "#E7DACB"; a.groutName = "PermaColor Sauterne"; a.variation = 3; a.finish = .gloss; a.name = "Cloé Sage"
        var t = TileChoice.usual
        t.appearance = a
        #expect(try JSONDecoder().decode(TileChoice.self, from: JSONEncoder().encode(t)) == t)
        // A look or finish this version doesn't know reads as none; a retired pattern as its replacement.
        let odd = #"{"look":"glitter","finish":"mirror","pattern":"graniteFlowing","variation":2}"#
        let r = try JSONDecoder().decode(TileAppearance.self, from: Data(odd.utf8))
        #expect(r.look == nil && r.finish == nil && r.pattern == .sweeping && r.variation == 2)
    }

    @Test func theMainTileCarriesItsAppearance() {
        var s = EstimateSection()
        var t = TileChoice.usual
        t.appearance = TileAppearance(colour: "#B6D6ED", look: .handmade, grout: "#FFFEF4", groutName: "PermaColor Bright White")
        s.setMainTile(t)
        #expect(s.tileAppearance == t.appearance)
        #expect(s.fullMainTile?.appearance == t.appearance && s.mainTile?.appearance == t.appearance)
    }

    @Test func aLookPatternIsOneOfItsLooks() {
        var a = TileAppearance(look: .stone)
        #expect(a.lookPattern == .slate)
        a.pattern = .thinVeins           // a marble pattern on a stone look
        #expect(a.lookPattern == .slate)
        a.look = .marble
        #expect(a.lookPattern == .thinVeins)
        a.look = .wood                   // real wood grain, straight unless chosen
        #expect(a.lookPattern == .woodStraight)
        a.pattern = .woodRustic
        #expect(a.lookPattern == .woodRustic)
        a.look = .solid
        #expect(a.lookPattern == nil)
    }

    @Test func namesStayOffTheEstimate() {
        // Tile and grout names are kept, not listed in the description (owner, 2026-10-18).
        let w = WordingTemplates.standard
        var t = TileChoice.usual
        let plain = tilePhrase(t, w)
        t.appearance = TileAppearance(colour: "#FAFAFA", grout: "#E7DACB", groutName: "PermaColor Sauterne", name: "Cloé")
        #expect(tilePhrase(t, w) == plain)
    }

    @Test func aSatinSavedBeforeReadsAsMatte() throws {
        let a = try JSONDecoder().decode(TileAppearance.self, from: Data(#"{"finish":"satin"}"#.utf8))
        #expect(a.finish == .matte)
        #expect(TileAppearance.Finish.allCases == [.matte, .gloss])
    }

    @Test func thePalettes() {
        let tiles = TilePalette.families.flatMap(\.colours)
        #expect(tiles.count == 53 && Set(tiles).count == 53)
        let grouts = TilePalette.grouts.flatMap(\.colours)
        #expect(grouts.count == 40 && Set(grouts.map(\.name)).count == 40)
        #expect(grouts.contains { $0.name == "Sauterne" && $0.hex == "#E7DACB" })
        #expect(grouts.contains { $0.name == "Midnight Black" })
    }

    @Test func colourAndGroutChangeHowItsDrawn() throws {
        var t = TileChoice.usual
        let plain = try #require(TilePattern.make(t).image.cgImage)
        t.appearance = TileAppearance(colour: "#AA2015")
        let red = try #require(TilePattern.make(t).image.cgImage)
        #expect(centre(plain) != centre(red))
        let c = centre(red)
        #expect(Int(c[0]) > Int(c[1]) + 60)                 // red
        t.appearance = TileAppearance(look: .marble, pattern: .boldVeins)
        #expect(TilePattern.make(t).image.cgImage != nil)
        t.appearance = TileAppearance(look: .wood)
        #expect(TilePattern.make(t).image.cgImage != nil)
    }

    @Test func myTilesKeepEverything() {
        let suite = "TileLookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lib = TileLibrary(defaults: defaults)
        var t = TileChoice(tileType: .ceramic, tileSize: .rectangle, layout: .runningBond, tileWidthIn: 2.5, tileLengthIn: 8)
        t.appearance = TileAppearance(colour: "#658679", look: .handmade)
        lib.save(t, name: "Cloé Sage 2.5×8")
        lib.used(t)
        let again = TileLibrary(defaults: defaults)
        #expect(again.mine.count == 1 && again.mine[0].tileWidthIn == 2.5 && again.mine[0].appearance?.name == "Cloé Sage 2.5×8")
        #expect(TileLibrary.sameLook(again.mine[0], t))
        #expect(again.recent.count == 1)
        again.delete(at: 0)
        #expect(TileLibrary(defaults: defaults).mine.isEmpty)
    }

    private func centre(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // A spot inside the first tile, clear of the grout.
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) * 0.05, y: -CGFloat(image.height) * 0.2,
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return px
    }
}
