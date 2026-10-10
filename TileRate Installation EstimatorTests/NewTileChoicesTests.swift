import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Layouts, shapes and mosaic styles added 2026-10-09 (owner: 3-D views for
/// as many styles as possible): each prices with its own adder in both
/// engines and is named on the estimate; vertical and a photo don't change
/// the price; both are saved.
struct NewTileChoicesTests {
    private func rates() -> Rates {
        var r = Rates()
        for a in Area.allCases { r.minimum[a] = 0; r.base[a] = 20 }
        for t in TileType.allCases { r.typeAdder[t] = 0 }
        for s in TileSize.allCases { r.sizeAdder[s] = 0 }
        for l in Layout.allCases { r.layoutAdder[l] = 0 }
        for m in MosaicStyle.allCases { r.mosaicStyleAdder[m] = 0 }
        r.sizeAdderPerDoubling = 0; r.sizeAdderPerHalving = 0
        return r
    }

    private func wall(_ t: TileChoice) -> EstimateSection {
        var s = EstimateSection()
        s.area = .wall
        s.tileType = t.tileType; s.tileSize = t.tileSize; s.layout = t.layout
        s.tileWidthIn = t.tileWidthIn; s.tileLengthIn = t.tileLengthIn; s.mosaicStyle = t.mosaicStyle
        s.tileVertical = t.vertical; s.tilePhotoID = t.photoID
        s.measurements.sqft = 100
        return s
    }

    private func totals(_ s: EstimateSection, _ r: Rates) -> (Double, Double) {
        let state = EstimatorState(section: s)
        return (legacySummary(state: state, rates: r).total, schemeSummary(state: state, scheme: PricingScheme(rates: r)).total)
    }

    @Test func newLayoutsChargeTheirAdder() {
        for l in [Layout.oneThirdOffset, .diagonalHerringbone, .doubleHerringbone, .chevron, .basketweave, .versailles, .hopscotch] {
            var r = rates()
            r.layoutAdder[l] = 3
            let t = TileChoice(tileType: .porcelain, tileSize: .rectangle, layout: l, tileWidthIn: 12, tileLengthIn: 24)
            let (legacy, scheme) = totals(wall(t), r)
            #expect(abs(legacy - 2300) < 0.01, "\(l)")
            #expect(abs(scheme - legacy) < 0.01, "\(l)")
        }
    }

    @Test func newShapesAndStylesChargeTheirAdder() {
        for shape in [TileSize.diamond, .triangle, .fishscale, .picket, .pill] {
            var r = rates()
            r.sizeAdder[shape] = 2
            let t = TileChoice(tileType: .ceramic, tileSize: shape, layout: .straightStacked, tileWidthIn: 4, tileLengthIn: 8)
            let (legacy, scheme) = totals(wall(t), r)
            #expect(abs(legacy - 2200) < 0.01, "\(shape)")
            #expect(abs(scheme - legacy) < 0.01, "\(shape)")
        }
        for style in [MosaicStyle.cube, .triangle, .mixedStick, .pill] {
            var r = rates()
            r.sizeAdder[.mosaic] = 1
            r.mosaicStyleAdder[style] = 4
            var t = TileChoice(tileType: .glass, tileSize: .mosaic, layout: .straightStacked)
            t.mosaicStyle = style
            let (legacy, scheme) = totals(wall(t), r)
            #expect(abs(legacy - 2500) < 0.01, "\(style)")
            #expect(abs(scheme - legacy) < 0.01, "\(style)")
        }
    }

    @Test func verticalAndAPhotoDontChangeThePriceAndVerticalIsNamed() {
        let r = rates()
        var t = TileChoice(tileType: .porcelain, tileSize: .rectangle, layout: .runningBond, tileWidthIn: 3, tileLengthIn: 12)
        let plain = totals(wall(t), r)
        t.vertical = true
        t.photoID = "some-photo"
        let changed = totals(wall(t), r)
        #expect(plain.0 == changed.0 && plain.1 == changed.1)
        let words = describeSection(wall(t), wording: WordingTemplates())
        #expect(words.contains("Vertical Running Bond"))
        #expect(tilePhrase(t, WordingTemplates()).contains("Vertical Running Bond"))
        t.vertical = false
        #expect(!tilePhrase(t, WordingTemplates()).contains("Vertical"))
    }

    @Test func verticalAndThePhotoAreSavedAndOldDataReadsWithout() throws {
        var s = EstimateSection()
        s.tileVertical = true
        s.tilePhotoID = "abc"
        var t = TileChoice()
        t.vertical = true
        t.photoID = "def"
        s.showerFloorTile = t
        let read = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(read.tileVertical && read.tilePhotoID == "abc")
        #expect(read.showerFloorTile?.vertical == true && read.showerFloorTile?.photoID == "def")
        #expect(read.mainTile == nil || read.mainTile?.vertical == true)
        // Saved before these fields existed: horizontal, no photo.
        let old = try JSONDecoder().decode(TileChoice.self, from: Data(#"{"tileType":"Glass","tileSize":"Mosaic","layout":"Straight Stacked"}"#.utf8))
        #expect(old.vertical == false && old.photoID == nil && old.tileType == .glass)
    }

    @Test func everyShapeAndStyleHasAPatternInItsOwnShape() {
        for size in TileSize.allCases where size != .mosaic {
            let t = TileChoice(tileType: .ceramic, tileSize: size, layout: .straightStacked)
            #expect(TilePattern.make(t).image.size.width > 8, "\(size)")
        }
        for style in MosaicStyle.allCases {
            var t = TileChoice(tileType: .ceramic, tileSize: .mosaic, layout: .straightStacked)
            t.mosaicStyle = style
            #expect(TilePattern.make(t).image.size.width > 8, "\(style)")
            #expect(style == .square || style == .rectangular || TilePattern.shape(t) != .rect, "\(style) drawn as squares")
        }
        for l in Layout.allCases {
            let t = TileChoice(tileType: .ceramic, tileSize: .rectangle, layout: l, tileWidthIn: 4, tileLengthIn: 12)
            #expect(TilePattern.make(t).image.size.width > 8, "\(l)")
        }
        // Vertical turns the repeat: a 3 × 12 stacked is 12 wide across, 3 when up.
        var t = TileChoice(tileType: .ceramic, tileSize: .rectangle, layout: .straightStacked, tileWidthIn: 3, tileLengthIn: 12)
        let across = TilePattern.make(t).periodIn
        t.vertical = true
        let up = TilePattern.make(t).periodIn
        #expect(across.width == up.height && across.height == up.width)
        // Fishscale either way up: the same repeat, drawn the other way, and saved.
        var f = TileChoice(tileType: .ceramic, tileSize: .mosaic, layout: .straightStacked)
        f.mosaicStyle = .fishscale
        let up2 = TilePattern.make(f)
        f.turnedOver = true
        let down = TilePattern.make(f)
        #expect(up2.periodIn == down.periodIn)
        #expect(up2.image.pngData() != down.image.pngData())
        let read = try? JSONDecoder().decode(TileChoice.self, from: JSONEncoder().encode(f))
        #expect(read?.turnedOver == true)
    }
}
