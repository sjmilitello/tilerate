//
//  TileRate_Installation_EstimatorTests.swift
//  TileRate EstimatorTests
//
//  Created by Salvatore Militello on 8/17/25.
//

import Foundation
import Testing
@testable import TileRate_Installation_Estimator

// Every test sets the rates it depends on. The defaults in `Rates` are not the
// owner's prices and can change without notice.

/// Rates with every adder at zero, so a test switches on only what it checks.
private func plainRates() -> Rates {
    var r = Rates()
    for k in r.typeAdder.keys { r.typeAdder[k] = 0 }
    for k in r.sizeAdder.keys { r.sizeAdder[k] = 0 }
    for k in r.layoutAdder.keys { r.layoutAdder[k] = 0 }
    r.typeAdderUnit = .perSqft
    r.sizeAdderUnit = .perSqft
    r.layoutAdderUnit = .perSqft
    r.sizeBaseAreaSqIn = 288
    r.sizeStepSqIn = 54
    r.sizeStepAdder = 0
    r.mosaicInlayRate = 0
    return r
}

private func section(_ area: Area,
                     sqft: Double = 0,
                     type: TileType = .ceramic,
                     size: TileSize = .hexagon,
                     layout: Layout = .straightStacked,
                     widthIn: Double? = nil,
                     lengthIn: Double? = nil) -> EstimateSection {
    var s = EstimateSection()
    s.area = area
    s.tileType = type
    s.tileSize = size
    s.layout = layout
    s.tileWidthIn = widthIn
    s.tileLengthIn = lengthIn
    s.measurements.sqft = sqft
    return s
}

private func price(_ s: EstimateSection, _ r: Rates) -> Double {
    computeSummary(state: EstimatorState(section: s), rates: r).total
}

// MARK: - Floor escalator (owner's rule; see CLAUDE.md)

struct FloorEscalatorTests {
    /// Minimum $1,500, $14 per foot over 50 up to 99, base rate from 100.
    private func rates() -> Rates {
        var r = plainRates()
        r.base[.floor] = 20
        r.minimum[.floor] = 1500
        r.floorEscThresholdLower = 50
        r.floorEscThresholdUpper = 99
        r.floorEscAdjPerSqft = 14
        return r
    }

    @Test(arguments: [(10.0, 1500.0), (50, 1500), (51, 1514), (60, 1640), (99, 2186)])
    func minimumPlusEscalatorInsideTheWindow(sqft: Double, expected: Double) {
        #expect(price(section(.floor, sqft: sqft), rates()) == expected)
    }

    @Test func baseRateTakesOverAboveTheWindow() {
        // 100 × $20 = $2,000 beats the minimum with no escalator.
        #expect(price(section(.floor, sqft: 100), rates()) == 2000)
        #expect(price(section(.floor, sqft: 150), rates()) == 3000)
    }

    @Test func priceNeverFallsAsTheFloorGetsBigger() {
        // With a base rate high enough that it wins inside the window too.
        var r = rates()
        r.base[.floor] = 25
        var last = 0.0
        for sqft in stride(from: 1.0, through: 200, by: 1) {
            let p = price(section(.floor, sqft: sqft), r)
            #expect(p >= last, "price fell at \(sqft) sq ft")
            last = p
        }
    }

    @Test func addersGoOnTopOfTheMinimum() {
        var r = rates()
        r.layoutAdder[.herringbone] = 3
        // 60 sq ft: $1,640 plus $3 × 60.
        #expect(price(section(.floor, sqft: 60, layout: .herringbone), r) == 1640 + 180)
    }
}

// MARK: - Minimums and adders

struct MinimumAndAdderTests {
    @Test func smallWallPaysTheMinimumLargeWallPaysTheRate() {
        var r = plainRates()
        r.base[.wall] = 25
        r.minimum[.wall] = 600
        #expect(price(section(.wall, sqft: 10), r) == 600)
        #expect(price(section(.wall, sqft: 40), r) == 1000)
    }

    @Test func addersStackAndGoOnTopOfTheMinimum() {
        var r = plainRates()
        r.base[.wall] = 25
        r.minimum[.wall] = 600
        r.typeAdder[.marble] = 4
        r.sizeAdder[.hexagon] = 2
        r.layoutAdder[.diagonal] = 1
        // 10 sq ft: $600 minimum + ($4 + $2 + $1) × 10.
        #expect(price(section(.wall, sqft: 10, type: .marble, size: .hexagon, layout: .diagonal), r) == 670)
        // 40 sq ft: ($25 + $7) × 40.
        #expect(price(section(.wall, sqft: 40, type: .marble, size: .hexagon, layout: .diagonal), r) == 1280)
    }

    @Test func percentAddersArePercentOfTheBaseRate() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.typeAdder[.glass] = 10
        r.typeAdderUnit = .percent
        // $20 + 10% of $20 = $22 × 50.
        #expect(abs(price(section(.wall, sqft: 50, type: .glass), r) - 1100) < 0.005)
    }

    @Test func featuresAreChargedPerUnit() {
        var r = plainRates()
        r.base[.shower] = 30
        r.minimum[.shower] = 0
        r.unitNiche = 250
        r.unitBench = 400
        var s = section(.shower)
        s.measurements.showerWallsSqft = 100
        s.features.niches = 2
        s.features.benches = 1
        #expect(price(s, r) == 3000 + 500 + 400)
    }

    @Test func floorsNeverChargeShelvesNichesFootrestsOrBenches() {
        var r = plainRates()
        r.base[.floor] = 20
        r.minimum[.floor] = 0
        r.floorEscAdjPerSqft = 0
        r.unitShelf = 100; r.unitNiche = 250; r.unitFootrest = 150; r.unitBench = 400
        var s = section(.floor, sqft: 100)
        s.features.shelves = 1; s.features.niches = 2; s.features.footrests = 1; s.features.benches = 1
        #expect(price(s, r) == 2000)
    }
}

// MARK: - Square and rectangle size steps

struct SizeStepTests {
    private func steps(_ w: Double?, _ l: Double?, _ size: TileSize = .rectangle) -> Int? {
        sizeSteps(size: size, lengthIn: l, widthIn: w, rates: plainRates())
    }

    @Test func baseSizeHasNoSteps() {
        #expect(steps(12, 24) == 0)     // 288 sq in
    }

    @Test(arguments: [
        (12.0, 12.0, 2),   // 144: 144 away = 2.67 steps → 2
        (24, 24, 5),       // 576: 288 away = 5.33 → 5
        (8, 48, 1),        // 384: 96 away = 1.78 → 1
        (6, 6, 4),         // 36: 252 away = 4.67 → 4
        (18, 22, 2),       // 396: exactly 108 away = 2
        (13, 24, 0),       // 312: 24 away, under one step
        (24, 48, 16),      // 1152: 864 away = 16
    ])
    func partStepsRoundDown(w: Double, l: Double, expected: Int) {
        #expect(steps(w, l, .square) == expected)
        #expect(steps(w, l, .rectangle) == expected)
    }

    @Test func missingDimensionsAreReported() {
        #expect(steps(nil, 24) == nil)
        #expect(steps(12, 0) == nil)
        #expect(isMissingTileDimensions(size: .rectangle, lengthIn: 24, widthIn: nil))
        #expect(!isMissingTileDimensions(size: .rectangle, lengthIn: 24, widthIn: 12))
        #expect(!isMissingTileDimensions(size: .hexagon, lengthIn: nil, widthIn: nil))
    }

    @Test func otherShapesHaveNoSteps() {
        #expect(steps(2, 2, .hexagon) == 0)
        #expect(steps(1, 1, .mosaic) == 0)
    }

    @Test func eachStepAddsTheAdderPerSquareFoot() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeStepAdder = 1.5
        // 24×24 is 5 steps: $20 + 5 × $1.50 = $27.50 × 100.
        #expect(price(section(.wall, sqft: 100, size: .square, widthIn: 24, lengthIn: 24), r) == 2750)
        // 12×24 is the base size: no adder.
        #expect(price(section(.wall, sqft: 100, size: .rectangle, widthIn: 12, lengthIn: 24), r) == 2000)
        // Missing width: no adder, which the app warns about.
        #expect(price(section(.wall, sqft: 100, size: .square, lengthIn: 24), r) == 2000)
    }

    @Test func percentStepAdderIsPercentOfTheBaseRate() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeStepAdder = 5
        r.sizeAdderUnit = .percent
        // 12×12 is 2 steps: 2 × 5% of $20 = $2 → $22 × 10.
        #expect(abs(price(section(.wall, sqft: 10, size: .square, widthIn: 12, lengthIn: 12), r) - 220) < 0.005)
    }

    @Test func otherShapesKeepTheirFlatAdder() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdder[.hexagon] = 3
        r.sizeStepAdder = 100   // must not apply to a hexagon
        #expect(price(section(.wall, sqft: 10, size: .hexagon, widthIn: 2, lengthIn: 2), r) == 230)
    }
}

// MARK: - Separate shower floor and ceiling tiles

struct SeparateTileTests {
    private func rates() -> Rates {
        var r = plainRates()
        r.base[.shower] = 30
        r.minimum[.shower] = 0
        r.showerFloorBase = 25
        r.showerFloorMinimum = 0
        r.ceilingBase = 20
        r.ceilingMinimum = 0
        r.sizeAdder[.mosaic] = 10
        r.layoutAdder[.herringbone] = 5
        return r
    }

    private func shower() -> EstimateSection {
        var s = section(.shower, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.measurements.showerWallsSqft = 100
        s.measurements.showerFloorSqft = 10
        return s
    }

    @Test func withoutASeparateTileTheFloorUsesTheWallTile() {
        // Walls 100 × $30, floor 10 × $25, 12×24 so no size adder.
        #expect(price(shower(), rates()) == 3250)
    }

    @Test func aSeparateFloorTileChangesOnlyTheFloor() {
        var s = shower()
        s.showerFloorTile = TileChoice(tileType: .ceramic, tileSize: .mosaic, layout: .straightStacked)
        // Floor becomes 10 × ($25 + $10 mosaic).
        #expect(price(s, rates()) == 3000 + 350)
    }

    @Test func aSeparateCeilingTileChangesOnlyTheCeiling() {
        var s = shower()
        s.measurements.ceilingSqft = 20
        #expect(price(s, rates()) == 3250 + 400)
        s.ceilingTile = TileChoice(tileType: .ceramic, tileSize: .rectangle, layout: .herringbone,
                                   tileWidthIn: 12, tileLengthIn: 24)
        // Ceiling becomes 20 × ($20 + $5 herringbone).
        #expect(price(s, rates()) == 3250 + 500)
    }

    @Test func aSeparateTileUsesItsOwnSizeSteps() {
        var r = rates()
        r.sizeStepAdder = 1
        var s = shower()
        s.showerFloorTile = TileChoice(tileType: .ceramic, tileSize: .square, layout: .straightStacked,
                                       tileWidthIn: 6, tileLengthIn: 6)
        // 6×6 floor is 4 steps: 10 × ($25 + $4). Walls stay at 12×24.
        #expect(price(s, r) == 3000 + 290)
    }

    @Test func tubCeilingCanHaveItsOwnTile() {
        var r = rates()
        r.base[.tub] = 26
        r.minimum[.tub] = 0
        var s = section(.tub, sqft: 50, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.measurements.ceilingSqft = 10
        s.ceilingTile = TileChoice(tileType: .ceramic, tileSize: .mosaic, layout: .straightStacked)
        #expect(price(s, r) == 1300 + 300)
    }
}

// MARK: - Shower walls, each with its own tile

struct WallTests {
    private func rates() -> Rates {
        var r = plainRates()
        r.base[.shower] = 30
        r.minimum[.shower] = 1200
        r.showerFloorBase = 25
        r.showerFloorMinimum = 0
        r.typeAdder[.marble] = 8
        r.layoutAdder[.herringbone] = 5
        r.sizeStepAdder = 1
        return r
    }

    private func wall(_ name: String, _ sqft: Double, _ type: TileType = .ceramic,
                      _ layout: Layout = .straightStacked, w: Double = 12, l: Double = 24) -> TiledWall {
        TiledWall(name: name, sqft: sqft,
                   tile: TileChoice(tileType: type, tileSize: .rectangle, layout: layout,
                                    tileWidthIn: w, tileLengthIn: l))
    }

    private func shower(_ walls: [TiledWall]) -> EstimateSection {
        var s = section(.shower, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.walls = walls
        return s
    }

    @Test func eachWallAddsItsOwnAdders() {
        let s = shower([
            wall("Back Wall", 40, .marble, .herringbone),   // $8 + $5 = $13
            wall("Left Wall", 30),                          // 12×24: no adders
            wall("Right Wall", 30, w: 24, l: 24),           // 5 size steps: $5
        ])
        // Base: 100 × $30 = $3,000, above the $1,200 minimum.
        #expect(price(s, rates()) == 3000 + 40 * 13 + 30 * 5)
    }

    @Test func theMinimumAppliesToAllTheWallsTogether() {
        let s = shower([wall("Back Wall", 10, .marble), wall("Left Wall", 10)])
        // 20 × $30 = $600 is under the $1,200 minimum; marble adds $8 × 10.
        #expect(price(s, rates()) == 1200 + 80)
    }

    @Test func wallsWithTheSameTileCostTheSameAsAllWallsTheSame() {
        var same = section(.shower, type: .marble, size: .rectangle, layout: .herringbone,
                           widthIn: 24, lengthIn: 24)
        same.measurements.showerWallsSqft = 90
        var split = same
        split.walls = [
            wall("Back Wall", 40, .marble, .herringbone, w: 24, l: 24),
            wall("Left Wall", 25, .marble, .herringbone, w: 24, l: 24),
            wall("Right Wall", 25, .marble, .herringbone, w: 24, l: 24),
        ]
        #expect(price(split, rates()) == price(same, rates()))
    }

    @Test func separateWallsIgnoreTheSingleWallsFigure() {
        var s = shower([wall("Back Wall", 50)])
        s.measurements.showerWallsSqft = 999
        #expect(price(s, rates()) == 1500)
    }

    @Test func unmeasuredWallsAddNothing() {
        let s = shower([wall("Back Wall", 50), wall("Left Wall", 0, .marble), wall("Right Wall", 0)])
        #expect(price(s, rates()) == 1500)
    }

    @Test func tubSurroundWallsEachHaveTheirOwnTile() {
        var r = rates()
        r.base[.tub] = 26
        r.minimum[.tub] = 900
        var s = section(.tub, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.measurements.sqft = 999     // ignored once the walls are separate
        s.walls = [wall("Back Wall", 30, .marble), wall("Left Wall", 10), wall("Right Wall", 10, w: 24, l: 24)]
        // Base 50 × $26 = $1,300 over the $900 minimum; marble $8 × 30; 24×24 5 steps × 10.
        #expect(price(s, r) == 1300 + 240 + 50)
    }

    @Test func tubSurroundMinimumAppliesToAllTheWallsTogether() {
        var r = rates()
        r.base[.tub] = 26
        r.minimum[.tub] = 900
        var s = section(.tub, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.walls = [wall("Back Wall", 10, .marble), wall("Left Wall", 10)]
        #expect(price(s, r) == 900 + 80)
    }

    @Test func tubSurroundWallsWithTheSameTileCostTheSameAsAllWallsTheSame() {
        var r = rates()
        r.base[.tub] = 26
        r.minimum[.tub] = 900
        var same = section(.tub, sqft: 60, type: .marble, size: .rectangle, layout: .herringbone,
                           widthIn: 24, lengthIn: 24)
        same.measurements.ceilingSqft = 12
        var split = same
        split.walls = [
            wall("Back Wall", 30, .marble, .herringbone, w: 24, l: 24),
            wall("Left Wall", 15, .marble, .herringbone, w: 24, l: 24),
            wall("Right Wall", 15, .marble, .herringbone, w: 24, l: 24),
        ]
        #expect(price(split, r) == price(same, r))
    }

    @Test func floorAndCeilingStillPricedWithSeparateWalls() {
        var s = shower([wall("Back Wall", 50)])
        s.measurements.showerFloorSqft = 10
        s.showerFloorTile = TileChoice(tileType: .marble, tileSize: .rectangle, layout: .straightStacked,
                                       tileWidthIn: 12, tileLengthIn: 24)
        // Walls $1,500; floor 10 × ($25 + $8 marble).
        #expect(price(s, rates()) == 1500 + 330)
    }
}

// MARK: - Whole-estimate totals (shared by the Summary screen and the PDF)

struct EstimateTotalsTests {
    private func document() -> EstimateDocument {
        var wall = section(.wall, sqft: 40)
        wall.additionsLabor = [AdditionItem(activity: "Demo", qty: 2, rate: 100)]
        var floor = section(.floor, sqft: 100)
        floor.additionsMaterials = [
            AdditionItem(activity: "Tile", qty: 1, rate: 500, taxable: true),
            AdditionItem(activity: "Delivery", qty: 1, rate: 50, taxable: false),
        ]
        return EstimateDocument(rooms: [
            EstimateRoom(name: "Bath", sections: [wall]),
            EstimateRoom(name: "Kitchen", sections: [floor]),
        ])
    }

    private func rates() -> Rates {
        var r = plainRates()
        r.base[.wall] = 25
        r.minimum[.wall] = 0
        r.base[.floor] = 20
        r.minimum[.floor] = 0
        r.floorEscAdjPerSqft = 0
        return r
    }

    @Test func subtotalTaxShippingAndTotal() {
        let t = computeTotals(document: document(), rates: rates(),
                              shippingEnabled: true, shipping: 75, taxPercent: 8)
        // Wall 1,000 + labour 200; floor 2,000 + materials 550.
        #expect(t.sections.map(\.subtotal) == [1200, 2550])
        #expect(t.subtotal == 3750)
        #expect(t.taxableBase == 500)       // only the taxable material line
        #expect(t.tax == 40)
        #expect(t.shipping == 75)
        #expect(t.grandTotal == 3750 + 75 + 40)
    }

    @Test func noShippingWhenSwitchedOff() {
        let t = computeTotals(document: document(), rates: rates(),
                              shippingEnabled: false, shipping: 75, taxPercent: 8)
        #expect(t.shipping == 0)
    }

    @Test func noShippingWithoutMaterialLines() {
        var doc = document()
        doc.rooms[1].sections[0].additionsMaterials = []
        let t = computeTotals(document: doc, rates: rates(),
                              shippingEnabled: true, shipping: 75, taxPercent: 8)
        #expect(t.shipping == 0)
        #expect(t.tax == 0)
    }

    @Test func sectionTotalsMatchPricingEachSectionAlone() {
        let r = rates()
        let t = computeTotals(document: document(), rates: r,
                              shippingEnabled: false, shipping: 0, taxPercent: 0)
        for item in t.sections {
            #expect(item.core.total == price(item.section, r))
        }
    }
}

// MARK: - Loading what earlier versions saved

struct SavedDataTests {
    @Test func ratesSavedWithTheOldSizeSettingsStillLoad() throws {
        // Saved before the step rule: the old Over/Under keys, no step keys.
        let json = """
        {"base":["Floor",21,"Wall",27],"floorEscAdjPerSqft":14,
         "rectSquareOverLengthIn":24,"rectSquareOverWidthIn":13,"rectSquareOverAdder":5,
         "rectSquareUnderLengthIn":12,"rectSquareUnderWidthIn":3,"rectSquareUnderAdder":5}
        """
        let r = try JSONDecoder().decode(Rates.self, from: Data(json.utf8))
        #expect(r.base[.floor] == 21)
        #expect(r.base[.wall] == 27)
        #expect(r.floorEscAdjPerSqft == 14)
        #expect(r.sizeBaseAreaSqIn == 288)
        #expect(r.sizeStepSqIn == 54)
        #expect(r.sizeStepAdder == 0)
    }

    @Test func sectionsSavedWithoutSeparateTilesStillLoad() throws {
        let json = """
        {"id":"4E1D1C4A-0000-4000-8000-000000000001","roomName":"","area":"Shower",
         "tileType":"Porcelain","tileSize":"Rectangle","layout":"Running Bond",
         "features":{"niches":1},"measurements":{"showerWallsSqft":90,"showerFloorSqft":12},
         "additionsLabor":[],"additionsMaterials":[],"tileWidthIn":12,"tileLengthIn":24}
        """
        let s = try JSONDecoder().decode(EstimateSection.self, from: Data(json.utf8))
        #expect(s.area == .shower)
        #expect(s.features.niches == 1)
        #expect(s.measurements.showerFloorSqft == 12)
        #expect(s.showerFloorTile == nil)
        #expect(s.ceilingTile == nil)
        #expect(s.walls.isEmpty)     // all walls the same, as before
    }

    @Test func showerWallsSurviveSaving() throws {
        var s = section(.shower, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.walls = [
            TiledWall(name: "Back Wall", sqft: 40,
                       tile: TileChoice(tileType: .marble, tileSize: .rectangle, layout: .herringbone,
                                        tileWidthIn: 3, tileLengthIn: 12)),
            TiledWall(name: "Niche Wall", sqft: 22.5),
        ]
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let state = try JSONDecoder().decode(EstimatorState.self,
                                             from: JSONEncoder().encode(EstimatorState(section: s)))
        #expect(state.walls == s.walls)
    }

    @Test func aWallMissingFieldsKeepsTheRest() throws {
        let w = try JSONDecoder().decode(TiledWall.self,
                                         from: Data(#"{"name":"Back Wall","sqft":40}"#.utf8))
        #expect(w.name == "Back Wall")
        #expect(w.sqft == 40)
        #expect(w.tile == TileChoice())
    }

    @Test func separateTilesSurviveSaving() throws {
        var s = section(.shower, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.showerFloorTile = TileChoice(tileType: .glass, tileSize: .mosaic, layout: .straightStacked,
                                       tileWidthIn: 1, tileLengthIn: 1)
        s.ceilingTile = TileChoice(tileType: .porcelain, tileSize: .square, layout: .diagonal,
                                   tileWidthIn: 12, tileLengthIn: 12)
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(back == s)

        var state = EstimatorState(section: s)
        state.stepIndex = 3
        let stateBack = try JSONDecoder().decode(EstimatorState.self, from: JSONEncoder().encode(state))
        #expect(stateBack.showerFloorTile == s.showerFloorTile)
        #expect(stateBack.ceilingTile == s.ceilingTile)
    }

    @Test func aTileChoiceMissingFieldsKeepsTheRest() throws {
        let t = try JSONDecoder().decode(TileChoice.self, from: Data(#"{"tileSize":"Mosaic"}"#.utf8))
        #expect(t.tileSize == .mosaic)
        #expect(t.tileType == .ceramic)
    }
}
