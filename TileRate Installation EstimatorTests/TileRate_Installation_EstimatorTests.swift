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
    r.sizeAdderPerDoubling = 0
    r.sizeAdderPerHalving = 0
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

// MARK: - Square and rectangle size: doublings from the standard tile

struct SizeDoublingTests {
    private func doublings(_ w: Double?, _ l: Double?, _ size: TileSize = .rectangle) -> Double? {
        sizeDoublings(size: size, lengthIn: l, widthIn: w, rates: plainRates())
    }

    @Test func theStandardTileHasNone() {
        #expect(doublings(12, 24) == 0)     // 288 sq in
        #expect(doublings(6, 48) == 0)      // also 288 sq in
    }

    @Test(arguments: [
        (24.0, 48.0, 2.0),              // 4× the area
        (3, 12, 3),                     // 1/8
        (24, 24, 1),                    // 2×
        (12, 12, 1),                    // 1/2
        (6, 6, 3),                      // 1/8
        (48, 48, 3),                    // 8×
        (48, 96, 4),                    // 16×
        (2, 2, 6.169925001442312),      // 1/72
        (6, 36, 0.41503749927884376),   // 3/4
    ])
    func biggerAndSmallerCountTheSameWay(w: Double, l: Double, expected: Double) {
        #expect(abs(doublings(w, l, .square)! - expected) < 1e-9)
        #expect(abs(doublings(w, l, .rectangle)! - expected) < 1e-9)
    }

    @Test func missingDimensionsAreReported() {
        #expect(doublings(nil, 24) == nil)
        #expect(doublings(12, 0) == nil)
        #expect(isMissingTileDimensions(size: .rectangle, lengthIn: 24, widthIn: nil))
        #expect(!isMissingTileDimensions(size: .rectangle, lengthIn: 24, widthIn: 12))
        #expect(!isMissingTileDimensions(size: .hexagon, lengthIn: nil, widthIn: nil))
    }

    @Test func otherShapesHaveNone() {
        #expect(doublings(2, 2, .hexagon) == 0)
        #expect(doublings(1, 1, .mosaic) == 0)
    }

    /// The owner's figures: $2.50 per doubling or halving from 12×24.
    @Test func theOwnersReferenceTiles() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdderPerDoubling = 2.5
        r.sizeAdderPerHalving = 2.5
        func perSqft(_ w: Double, _ l: Double) -> Double {
            price(section(.wall, sqft: 100, size: .rectangle, widthIn: w, lengthIn: l), r) / 100 - 20
        }
        #expect(abs(perSqft(12, 24) - 0) < 1e-9)
        #expect(abs(perSqft(24, 48) - 5) < 1e-9)
        #expect(abs(perSqft(3, 12) - 7.5) < 1e-9)
        #expect(abs(perSqft(24, 24) - 2.5) < 1e-9)
        #expect(abs(perSqft(48, 48) - 7.5) < 1e-9)
    }

    @Test func theAdderGrowsTheFurtherFromTheStandardInEitherDirection() {
        var r = plainRates()
        r.sizeAdderPerDoubling = 2.5
        r.sizeAdderPerHalving = 2.5
        var last = 0.0
        for side in stride(from: 17.0, through: 96, by: 1) {       // 17×17 ≈ 288 and up
            let d = sizeDoublings(size: .square, lengthIn: side, widthIn: side, rates: r)!
            #expect(d >= last); last = d
        }
        last = 0
        for side in stride(from: 16.0, through: 1, by: -1) {        // down to 1×1
            let d = sizeDoublings(size: .square, lengthIn: side, widthIn: side, rates: r)!
            #expect(d >= last); last = d
        }
    }

    @Test func biggerAndSmallerHaveTheirOwnAdders() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdderPerDoubling = 2.5
        r.sizeAdderPerHalving = 1.5
        func perSqft(_ w: Double, _ l: Double) -> Double {
            price(section(.wall, sqft: 100, size: .rectangle, widthIn: w, lengthIn: l), r) / 100 - 20
        }
        #expect(abs(perSqft(24, 48) - 5) < 1e-9)       // 2 doublings × $2.50
        #expect(abs(perSqft(3, 12) - 4.5) < 1e-9)      // 3 halvings × $1.50
        #expect(abs(perSqft(12, 12) - 1.5) < 1e-9)     // 1 halving
        #expect(abs(perSqft(12, 24) - 0) < 1e-9)
        #expect(sizeAdderAmount(size: .square, lengthIn: 24, widthIn: 24, rates: r) == 2.5)
        #expect(sizeAdderAmount(size: .square, lengthIn: 24, widthIn: nil, rates: r) == nil)
    }

    @Test func aSavedDoublingAdderAlsoBecomesTheHalvingAdder() throws {
        // Saved when one adder covered both directions: prices stay the same.
        let one = try JSONDecoder().decode(Rates.self, from: Data(#"{"sizeAdderPerDoubling":3}"#.utf8))
        #expect(one.sizeAdderPerDoubling == 3 && one.sizeAdderPerHalving == 3)
        let two = try JSONDecoder().decode(Rates.self,
                                           from: Data(#"{"sizeAdderPerDoubling":3,"sizeAdderPerHalving":1}"#.utf8))
        #expect(two.sizeAdderPerDoubling == 3 && two.sizeAdderPerHalving == 1)
    }

    @Test func missingWidthChargesNoSizeAdder() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdderPerDoubling = 2.5
        r.sizeAdderPerHalving = 2.5
        // The app warns about this on the Size step and the Summary.
        #expect(price(section(.wall, sqft: 100, size: .square, lengthIn: 24), r) == 2000)
    }

    @Test func percentAdderIsPercentOfTheBaseRate() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdderPerDoubling = 10
        r.sizeAdderPerHalving = 10
        r.sizeAdderUnit = .percent
        // 24×24 is 1 doubling: 10% of $20 = $2 → $22 × 10.
        #expect(abs(price(section(.wall, sqft: 10, size: .square, widthIn: 24, lengthIn: 24), r) - 220) < 0.005)
    }

    @Test func otherShapesKeepTheirFlatAdder() {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdder[.hexagon] = 3
        r.sizeAdderPerDoubling = 100
        r.sizeAdderPerHalving = 100   // must not apply to a hexagon
        #expect(price(section(.wall, sqft: 10, size: .hexagon, widthIn: 2, lengthIn: 2), r) == 230)
    }
}

// MARK: - Mosaic styles

struct MosaicStyleTests {
    private func rates() -> Rates {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdder[.mosaic] = 4
        r.mosaicStyleAdder[.pennyRound] = 3
        r.mosaicStyleAdder[.waterjet] = 10
        return r
    }

    private func mosaic(_ style: MosaicStyle?) -> EstimateSection {
        var s = section(.wall, sqft: 10, size: .mosaic)
        s.mosaicStyle = style
        return s
    }

    @Test func theStyleAdderGoesOnTopOfTheMosaicAdder() {
        #expect(price(mosaic(.pennyRound), rates()) == 10 * (20 + 4 + 3))
        #expect(price(mosaic(.waterjet), rates()) == 10 * (20 + 4 + 10))
        #expect(price(mosaic(.hexagon), rates()) == 10 * (20 + 4))    // no style adder set
        #expect(price(mosaic(nil), rates()) == 10 * (20 + 4))         // no style chosen
    }

    @Test func aStyleLeftOverFromAnotherShapeIsIgnored() {
        var s = mosaic(.waterjet)
        s.tileSize = .hexagon
        #expect(price(s, rates()) == 10 * 20)
    }

    @Test func aSeparateMosaicTileUsesItsStyle() {
        var r = rates()
        r.base[.shower] = 30
        r.minimum[.shower] = 0
        r.showerFloorBase = 25
        r.showerFloorMinimum = 0
        var s = section(.shower, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.measurements.showerWallsSqft = 100
        s.measurements.showerFloorSqft = 10
        s.showerFloorTile = TileChoice(tileType: .glass, tileSize: .mosaic, layout: .straightStacked,
                                       mosaicStyle: .pennyRound)
        #expect(price(s, r) == 3000 + 10 * (25 + 4 + 3))
    }

    @Test func theEstimateNamesTheStyle() {
        var s = mosaic(.pennyRound)
        s.tileType = .porcelain
        s.measurements.sqft = 10
        #expect(describeSection(s).contains("Porcelain Penny Round Mosaic on Walls"))

        var sq = mosaic(.square)
        sq.tileType = .glass
        sq.tileWidthIn = 1
        sq.tileLengthIn = 1
        #expect(describeSection(sq).contains("1×1 Glass Square Mosaic"))

        var plain = mosaic(nil)
        plain.tileType = .porcelain
        #expect(describeSection(plain).contains("Porcelain Tile"))
        #expect(!describeSection(plain).contains("pattern"))
    }

    @Test func mosaicsNeedNoLayoutAndPayNoLayoutAdder() {
        var r = rates()
        r.layoutAdder[.herringbone] = 7
        var s = mosaic(.pennyRound)
        s.layout = .herringbone
        #expect(price(s, r) == 10 * (20 + 4 + 3))          // no $7 herringbone adder
        s.layout = nil
        #expect(isSectionReady(s))
        #expect(price(s, r) == 10 * (20 + 4 + 3))          // still priced without a layout

        var tile = section(.wall, sqft: 10, size: .hexagon)
        tile.layout = nil
        #expect(!isSectionReady(tile))                      // other shapes still need one
        #expect(price(tile, r) == 0)
    }

    @Test func mosaicWordingHasNoPattern() {
        var s = mosaic(.pennyRound)
        s.tileType = .porcelain
        s.layout = .herringbone
        s.measurements.sqft = 10
        #expect(describeSection(s).contains("Porcelain Penny Round Mosaic on Walls"))
        #expect(!describeSection(s).contains("pattern"))
    }

    @Test func savedDataWithoutStylesStillLoads() throws {
        let tile = try JSONDecoder().decode(TileChoice.self, from: Data(#"{"tileSize":"Mosaic"}"#.utf8))
        #expect(tile.mosaicStyle == nil)
        let r = try JSONDecoder().decode(Rates.self, from: Data(#"{"sizeAdder":["Mosaic",4]}"#.utf8))
        #expect(r.sizeAdder[.mosaic] == 4)
        #expect(MosaicStyle.allCases.allSatisfy { r.mosaicStyleAdder[$0] == 0 })

        var s = mosaic(.fishscale)
        s.showerFloorTile = TileChoice(tileSize: .mosaic, mosaicStyle: .pebble)
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let state = try JSONDecoder().decode(EstimatorState.self,
                                             from: JSONEncoder().encode(EstimatorState(section: s)))
        #expect(state.mosaicStyle == .fishscale)
    }
}

// MARK: - Price list for extras

struct PriceListTests {
    private let demo = PriceListItem(name: "Demolition", unit: .perSqft, price: 3)
    private let threshold = PriceListItem(name: "Threshold", unit: .each, price: 45, isMaterial: true, taxable: true)

    @Test func thePerSqftItemFillsInTheAreasSquareFeet() {
        var shower = section(.shower)
        shower.measurements.showerWallsSqft = 90
        shower.measurements.showerFloorSqft = 12
        shower.add(demo)
        let line = shower.additionsLabor[0]
        #expect(line.activity == "Demolition" && line.qty == 102 && line.rate == 3 && line.unit == "sq ft")
        #expect(line.followsAreaSqft && line.amount == 306)
    }

    @Test func itFollowsTheAreaUntilAQuantityIsTyped() {
        var s = section(.floor, sqft: 100)
        s.add(demo)
        s.measurements.sqft = 120
        s.syncAreaQuantities()
        #expect(s.additionsLabor[0].qty == 120)
        s.additionsLabor[0].qty = 80
        s.additionsLabor[0].followsAreaSqft = false        // what typing a quantity does
        s.measurements.sqft = 150
        s.syncAreaQuantities()
        #expect(s.additionsLabor[0].qty == 80)
    }

    @Test func otherUnitsStartAtOneAndMaterialsCanBeTaxed() {
        var s = section(.floor, sqft: 100)
        s.add(threshold)
        let line = s.additionsMaterials[0]
        #expect(s.additionsLabor.isEmpty)
        #expect(line.qty == 1 && line.unit == "each" && line.taxable && !line.followsAreaSqft)
    }

    @Test func thePriceCanBeChangedForOneEstimate() {
        var s = section(.floor, sqft: 10)
        s.add(demo)
        s.additionsLabor[0].rate = 4
        #expect(s.additionsLabor[0].amount == 40)
        #expect(demo.price == 3)                            // the list is unchanged
    }

    @Test func theMinimumChargeApplies() {
        var s = section(.floor, sqft: 40)
        s.add(PriceListItem(name: "Demolition", unit: .perSqft, price: 3, minimum: 250))
        #expect(s.additionsLabor[0].amount == 250 && s.additionsLabor[0].minimumApplied)   // 40 × $3 = $120
        s.measurements.sqft = 100
        s.syncAreaQuantities()
        #expect(s.additionsLabor[0].amount == 300 && !s.additionsLabor[0].minimumApplied)
    }

    private func demo(_ name: String) -> PriceListItem {
        PriceListItem.ownersDemolition.first { $0.name == "Demo: " + name }!
    }

    @Test func demolitionItemsFillInTheirOwnPart() {
        var shower = section(.shower)
        shower.measurements.showerWallsSqft = 90
        shower.measurements.showerFloorSqft = 12
        shower.measurements.ceilingSqft = 20
        for name in ["Tile walls", "Tile shower base", "Tile ceiling", "Tile floors", "Acrylic shower base"] {
            shower.add(demo(name))
        }
        #expect(shower.additionsLabor.map(\.qty) == [90, 12, 20, 0, 1])
        #expect(shower.additionsLabor[4].unit == "each" && !shower.additionsLabor[4].followsAreaSqft)

        var floor = section(.floor, sqft: 60)
        for name in ["Tile floors", "Carpeting", "Plywood", "Tile walls"] { floor.add(demo(name)) }
        #expect(floor.additionsLabor.map(\.qty) == [60, 60, 60, 0])

        var tub = section(.tub, sqft: 50)
        tub.add(demo("Tile walls"))
        tub.add(demo("Tub only"))
        tub.measurements.sqft = 70
        tub.syncAreaQuantities()
        #expect(tub.additionsLabor.map(\.qty) == [70, 1])
    }

    @Test func theOldSingleDemolitionItemSplitsKeepingItsPrice() throws {
        let json = """
        {"priceList":[{"id":"6B1C2D3E-0F41-4A52-8B63-7C84D5E6F701","name":"Demolition","unit":"per sq ft","price":4,"minimum":300},
                      {"id":"6B1C2D3E-0F41-4A52-8B63-7C84D5E6F702","name":"Floor leveling","price":2}]}
        """
        let r = try JSONDecoder().decode(Rates.self, from: Data(json.utf8))
        #expect(r.priceList.map(\.name) == PriceListItem.ownersDemolition.map(\.name) + ["Floor leveling"])
        let demos = r.priceList.prefix(12)
        #expect(demos.filter { $0.unit == .perSqft }.allSatisfy { $0.price == 4 && $0.minimum == 300 })
        #expect(demos.filter { $0.unit == .each }.allSatisfy { $0.price == 0 && $0.minimum == 0 })
        #expect(r.priceList.last?.measure == .floorOnly && r.priceList.last?.price == 2)
    }

    @Test func linesCountInTheTotals() {
        var r = plainRates()
        r.base[.floor] = 20
        r.minimum[.floor] = 0
        r.floorEscAdjPerSqft = 0
        var s = section(.floor, sqft: 100)
        s.add(demo)
        s.add(threshold)
        let t = computeTotals(document: EstimateDocument(rooms: [EstimateRoom(name: "Hall", sections: [s])]),
                              rates: r, shippingEnabled: false, shipping: 0, taxPercent: 10)
        #expect(t.subtotal == 2000 + 300 + 45)
        #expect(t.taxableBase == 45)
    }

    @Test func savedDataLoads() throws {
        let old = try JSONDecoder().decode(Rates.self, from: Data(#"{"unitBench":200}"#.utf8))
        #expect(old.priceList.map(\.name)
                == PriceListItem.ownersDemolition.map(\.name) + ["Floor leveling", "Epoxy grout upgrade"])
        #expect(old.priceList.count == 14)
        #expect(old.priceList.allSatisfy { $0.price == 0 && !$0.isMaterial })
        let line = try JSONDecoder().decode(AdditionItem.self, from: Data(#"{"activity":"Haul","qty":2,"rate":50}"#.utf8))
        #expect(line.amount == 100 && line.unit == "" && !line.followsAreaSqft && line.minimum == 0)
        var r = Rates()
        r.priceList = [threshold]
        #expect(try JSONDecoder().decode(Rates.self, from: JSONEncoder().encode(r)).priceList == [threshold])
    }
}

// MARK: - Electric radiant heat

struct RadiantHeatTests {
    private func rates() -> Rates {
        var r = plainRates()
        r.heatingSystems = [.ownersStrataHeat]
        return r
    }

    private func floor(_ sqft: Double, heated: Double? = nil) -> EstimateSection {
        var s = section(.floor, sqft: sqft)
        s.radiantHeat = RadiantHeatChoice(systemID: HeatingSystem.ownersStrataHeat.id, heatedSqft: heated)
        return s
    }

    private func cents(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    @Test func theOwnersExample() throws {
        // 60 sq ft floor, 50 heated: 8 mats, a 200 LF 120V wire, 1 thermostat.
        let r = try #require(radiantHeatPrice(for: floor(60, heated: 50), rates: rates()))
        #expect(r.parts.map(\.detail) == ["1 × 200 LF (120V)", "8 × $16.59", "1 × $226.68"])
        #expect(cents(r.cost) == cents(292.99 + 8 * 16.59 + 226.68))      // $652.39
        #expect(r.materials == 1043.82)                                     // × 1.6
        #expect(r.labor == 500 && r.laborMinimumApplied)                    // 60 × $8 = $480 < $500
    }

    @Test func voltageSwitchesAbove100SqFt() throws {
        let at100 = try #require(radiantHeatPrice(for: floor(100), rates: rates()))
        #expect(at100.parts[0].detail == "1 × 398 LF (120V)")
        let at101 = try #require(radiantHeatPrice(for: floor(101), rates: rates()))
        #expect(at101.parts[0].detail == "1 × 415 LF (240V)")
        #expect(at101.labor == 808 && !at101.laborMinimumApplied)
    }

    @Test func longRunsSplitAcrossWiresEachWithAThermostat() throws {
        // 250 sq ft: 987.5 LF, more than the 830 LF longest wire → two of 493.75 → 498 LF each.
        let r = try #require(radiantHeatPrice(for: floor(250), rates: rates()))
        #expect(r.parts[0].detail == "2 × 498 LF (240V)")
        #expect(r.parts[2].detail == "2 × $226.68")
        #expect(cents(r.parts[0].cost) == cents(2 * 530.13))
    }

    @Test func wholeFloorWhenNoHeatedAreaIsGiven() throws {
        let r = try #require(radiantHeatPrice(for: floor(40), rates: rates()))
        #expect(r.heatedSqft == 40)
        #expect(r.parts[0].detail == "1 × 166 LF (120V)")                   // 158 LF needed
    }

    @Test func aShowerFloorCanBeHeated() throws {
        var s = section(.shower)
        s.measurements.showerWallsSqft = 90
        s.measurements.showerFloorSqft = 12
        s.radiantHeat = RadiantHeatChoice(systemID: HeatingSystem.ownersStrataHeat.id)
        let r = try #require(radiantHeatPrice(for: s, rates: rates()))
        #expect(r.floorSqft == 12)
        #expect(r.parts.map(\.detail) == ["1 × 50 LF (120V)", "2 × $16.59", "1 × $226.68"])
        #expect(r.labor == 500)
    }

    @Test func onlyFloorsAndShowerFloors() {
        var wall = section(.wall, sqft: 50)
        wall.radiantHeat = RadiantHeatChoice()
        #expect(radiantHeatPrice(for: wall, rates: rates()) == nil)
        #expect(radiantHeatPrice(for: section(.floor, sqft: 50), rates: rates()) == nil)   // not switched on
        var none = rates()
        none.heatingSystems = []
        #expect(radiantHeatPrice(for: floor(50), rates: none) == nil)                        // no system set up
    }

    @Test func markupAndLaborFollowTheSettings() throws {
        var r = rates()
        r.heatingSystems[0].markupPercent = 100
        r.heatingSystems[0].laborPerSqft = 10
        r.heatingSystems[0].laborMinimum = 0
        let p = try #require(radiantHeatPrice(for: floor(60, heated: 50), rates: r))
        #expect(p.materials == cents(p.cost * 2))
        #expect(p.labor == 600)
    }

    @Test func installationCanBeChargedOnTheHeatedAreaOnly() throws {
        var r = rates()
        r.heatingSystems[0].laborMinimum = 0
        let whole = try #require(radiantHeatPrice(for: floor(120, heated: 90), rates: r))
        #expect(whole.labor == 960)                     // 120 floor sq ft × $8
        r.heatingSystems[0].laborOnHeatedAreaOnly = true
        let heated = try #require(radiantHeatPrice(for: floor(120, heated: 90), rates: r))
        #expect(heated.labor == 720)                    // 90 heated sq ft × $8
        #expect(heated.materials == whole.materials)    // parts unchanged
    }

    @Test func theKitIsATaxableMaterialLineAndInstallationALaborLine() throws {
        var r = rates()
        r.base[.floor] = 20
        r.minimum[.floor] = 0
        r.floorEscAdjPerSqft = 0
        let doc = EstimateDocument(rooms: [EstimateRoom(name: "Bath", sections: [floor(60, heated: 50)])])
        let t = computeTotals(document: doc, rates: r, shippingEnabled: true, shipping: 40, taxPercent: 10)
        let item = try #require(t.sections.first)
        #expect(item.materialItems.map(\.activity) == [HeatingSystem.ownersStrataHeat.name])
        #expect(item.materialItems[0].taxable && item.materialItems[0].amount == 1043.82)
        #expect(item.laborItems.map(\.activity) == ["Radiant Heat Installation"])
        #expect(item.subtotal == 1200 + 1043.82 + 500)
        #expect(t.taxableBase == 1043.82)
        #expect(t.shipping == 40)                       // the kit counts as material for shipping
    }

    @Test func savedDataLoads() throws {
        // Rates saved before radiant heat get the owner's system.
        let old = try JSONDecoder().decode(Rates.self, from: Data(#"{"unitBench":200}"#.utf8))
        #expect(old.heatingSystems.map(\.id) == [HeatingSystem.ownersStrataHeat.id])
        // An emptied list stays empty.
        let empty = try JSONDecoder().decode(Rates.self, from: Data(#"{"heatingSystems":[]}"#.utf8))
        #expect(empty.heatingSystems.isEmpty)
        // A system and a section round-trip.
        var r = rates()
        r.heatingSystems[0].markupPercent = 55
        let back = try JSONDecoder().decode(Rates.self, from: JSONEncoder().encode(r))
        #expect(back.heatingSystems == r.heatingSystems)
        let s = floor(60, heated: 45)
        #expect(try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s)) == s)
        let state = try JSONDecoder().decode(EstimatorState.self,
                                             from: JSONEncoder().encode(EstimatorState(section: s)))
        #expect(state.radiantHeat == s.radiantHeat)
        let part = try JSONDecoder().decode(HeatingPart.self, from: Data(#"{"name":"Mat","rule":"Covers the floor"}"#.utf8))
        #expect(part.rule == .coversFloor && part.coverageSqft == 8)
        #expect(!old.heatingSystems[0].laborOnHeatedAreaOnly)    // whole floor, as before
    }
}

// MARK: - Multi-tile layouts

struct MultiTileTests {
    private func rates() -> Rates {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.sizeAdderPerDoubling = 2.5
        r.sizeAdderPerHalving = 2.5
        r.layoutAdder[.multiTile] = 6
        r.typeAdder[.marble] = 4
        return r
    }

    private func multi(_ pieces: [TilePiece]) -> EstimateSection {
        var s = section(.wall, sqft: 100, type: .marble, size: .square, layout: .multiTile)
        s.multiTilePieces = pieces
        return s
    }

    @Test func noSizeAdderOnlyTheLayoutAndTypeAdders() {
        let s = multi([TilePiece(shape: .square, widthIn: 6, lengthIn: 6),
                       TilePiece(shape: .rectangle, widthIn: 24, lengthIn: 48)])
        // $20 base + $4 marble + $6 multi-tile; neither size's adder.
        let expected: Double = 100 * 30
        #expect(price(s, rates()) == expected)
    }

    @Test func missingPieceSizesRaiseNoWarning() {
        let s = multi([TilePiece(shape: .rectangle)])
        #expect(missingSizeWarnings(s).isEmpty)
        #expect(isSectionReady(s))
    }

    @Test func theEstimateListsEachTile() {
        var s = multi([TilePiece(shape: .rectangle, widthIn: 12, lengthIn: 24),
                       TilePiece(shape: .square, widthIn: 24, lengthIn: 24),
                       TilePiece(shape: .hexagon, widthIn: 6, lengthIn: 6)])
        s.tileType = .porcelain
        #expect(describeSection(s).contains("Porcelain Tile in Multi-Tile pattern (12×24, 24×24, 6×6 Hexagon)"))
    }

    @Test func aSeparateMultiTileWallUsesItsPieces() {
        var r = rates()
        r.base[.shower] = 30
        r.minimum[.shower] = 0
        var s = section(.shower, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.walls = [TiledWall(name: "Back Wall", sqft: 40,
                             tile: TileChoice(tileType: .ceramic, tileSize: .rectangle, layout: .multiTile,
                                              pieces: [TilePiece(shape: .square, widthIn: 6, lengthIn: 6)]))]
        let expected: Double = 40 * 36                           // no 6×6 size adder
        #expect(price(s, r) == expected)
        #expect(describeSection(s).contains("Ceramic Tile in Multi-Tile pattern (6×6) on Back Wall"))
    }

    @Test func otherLayoutsStillPayTheSizeAdder() {
        let s = section(.wall, sqft: 100, type: .marble, size: .square, layout: .straightStacked,
                        widthIn: 24, lengthIn: 24)
        let expected: Double = 100 * 26.5
        #expect(price(s, rates()) == expected)
    }

    @Test func savedDataWithoutPiecesStillLoads() throws {
        let t = try JSONDecoder().decode(TileChoice.self, from: Data(#"{"layout":"Multi-Tile"}"#.utf8))
        #expect(t.pieces.isEmpty)
        let piece = try JSONDecoder().decode(TilePiece.self, from: Data(#"{"shape":"Hexagon","widthIn":6}"#.utf8))
        #expect(piece.shape == .hexagon && piece.widthIn == 6 && piece.lengthIn == nil)

        let s = multi([TilePiece(shape: .square, widthIn: 12, lengthIn: 12)])
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let state = try JSONDecoder().decode(EstimatorState.self, from: JSONEncoder().encode(EstimatorState(section: s)))
        #expect(state.multiTilePieces == s.multiTilePieces)
    }
}

// MARK: - Bands, borders and inlays

struct DecorativeTests {
    private func rates() -> Rates {
        var r = plainRates()
        r.base[.wall] = 20
        r.minimum[.wall] = 0
        r.bandRatePerLinFt = 15
        r.borderRatePerLinFt = 12
        r.mosaicInlayRate = 40
        return r
    }

    @Test func eachKindUsesItsOwnRateAndUnit() {
        var s = section(.wall, sqft: 100)
        s.decoratives = [
            DecorativeItem(kind: .band, quantity: 10),     // 10 lin ft × $15
            DecorativeItem(kind: .border, quantity: 8),    // 8 lin ft × $12
            DecorativeItem(kind: .inlay, quantity: 4),     // 4 sq ft × $40
        ]
        #expect(price(s, rates()) == 2000 + 150 + 96 + 160)
    }

    @Test func anyNumberInAnyMix() {
        var s = section(.wall, sqft: 100)
        s.decoratives = [
            DecorativeItem(kind: .band, quantity: 10), DecorativeItem(kind: .band, quantity: 6),
            DecorativeItem(kind: .inlay, quantity: 2), DecorativeItem(kind: .inlay, quantity: 3),
        ]
        #expect(price(s, rates()) == 2000 + 16 * 15 + 5 * 40)
    }

    @Test func theTileDescribesButDoesNotChangeThePrice() {
        var r = rates()
        r.typeAdder[.marble] = 9
        var s = section(.wall, sqft: 100)
        s.decoratives = [DecorativeItem(kind: .band, quantity: 10, tile: TileChoice(tileType: .marble))]
        #expect(price(s, r) == 2000 + 150)
    }

    @Test func unmeasuredItemsAddNothing() {
        var s = section(.wall, sqft: 100)
        s.decoratives = [DecorativeItem(kind: .border, quantity: 0)]
        #expect(price(s, rates()) == 2000)
    }

    @Test func worksOnFloors() {
        var r = rates()
        r.base[.floor] = 20
        r.minimum[.floor] = 0
        r.floorEscAdjPerSqft = 0
        var s = section(.floor, sqft: 100)
        s.decoratives = [DecorativeItem(kind: .border, quantity: 40)]
        #expect(price(s, r) == 2000 + 480)
    }

    @Test func aShowerDefaultsToTheFloorsMosaic() {
        var s = section(.shower, type: .porcelain, size: .rectangle, widthIn: 12, lengthIn: 24)
        let floor = TileChoice(tileType: .glass, tileSize: .mosaic, mosaicStyle: .pennyRound)
        s.showerFloorTile = floor
        #expect(defaultDecorativeTile(for: s) == floor)

        // A floor tile that isn't a mosaic: fall back to the main tile.
        s.showerFloorTile = TileChoice(tileType: .marble, tileSize: .hexagon)
        #expect(defaultDecorativeTile(for: s).tileType == .porcelain)
        #expect(defaultDecorativeTile(for: s).tileSize == .rectangle)

        // Other areas: the main tile.
        var w = section(.wall, type: .slate, size: .square, widthIn: 12, lengthIn: 12)
        w.showerFloorTile = floor
        #expect(defaultDecorativeTile(for: w).tileType == .slate)
    }

    @Test func theEstimateListsThem() {
        var s = section(.wall, sqft: 100, type: .porcelain, size: .rectangle, widthIn: 12, lengthIn: 24)
        s.decoratives = [
            DecorativeItem(kind: .band, name: "Chair rail", quantity: 12,
                           tile: TileChoice(tileType: .glass, tileSize: .mosaic, mosaicStyle: .pennyRound)),
            DecorativeItem(kind: .inlay, quantity: 4, tile: TileChoice(tileType: .marble, tileSize: .square,
                                                                       tileWidthIn: 6, tileLengthIn: 6)),
        ]
        let d = describeSection(s)
        #expect(d.contains("Band “Chair rail” of Glass Penny Round Mosaic"))
        #expect(d.contains("Inlay of 6×6 Marble Tile"))
        #expect(!d.contains("lin ft") && !d.contains("sq ft"))
    }

    @Test func locationOptionsFollowTheArea() {
        var tub = section(.tub, sqft: 50)
        #expect(decorativeLocationOptions(tub).map(\.label) == ["Back Wall", "Left Wall", "Right Wall"])
        tub.measurements.ceilingSqft = 10
        #expect(decorativeLocationOptions(tub).map(\.label) == ["Back Wall", "Left Wall", "Right Wall", "Ceiling"])

        var shower = section(.shower)
        shower.walls = [TiledWall(name: "Back wall", sqft: 40), TiledWall(name: "Left wall", sqft: 30),
                        TiledWall(name: "Right wall", sqft: 30), TiledWall(name: "Knee wall", sqft: 8)]
        shower.measurements.showerFloorSqft = 12
        #expect(decorativeLocationOptions(shower).map(\.label)
                == ["Back wall", "Left wall", "Right wall", "Knee wall", "Shower Floor"])

        #expect(decorativeLocationOptions(section(.wall, sqft: 50)).isEmpty)
        #expect(decorativeLocationOptions(section(.floor, sqft: 50)).isEmpty)
    }

    @Test func bandsTakeSeveralLocationsInlaysOne() {
        let tub = section(.tub, sqft: 50)
        let opts = decorativeLocationOptions(tub)
        var band = DecorativeItem(kind: .band)
        band.toggleLocation(opts[0]); band.toggleLocation(opts[1])
        #expect(decorativeLocationLabels(band, in: tub) == ["Back Wall", "Left Wall"])
        band.toggleLocation(opts[0])
        #expect(decorativeLocationLabels(band, in: tub) == ["Left Wall"])

        var inlay = DecorativeItem(kind: .inlay)
        inlay.toggleLocation(opts[0]); inlay.toggleLocation(opts[2])
        #expect(decorativeLocationLabels(inlay, in: tub) == ["Right Wall"])
    }

    @Test func locationsFollowWallsByIdAndSurviveSplittingWalls() {
        var shower = section(.shower)
        let knee = TiledWall(name: "Knee wall", sqft: 8)
        shower.walls = [TiledWall(name: "Back Wall", sqft: 40), knee]
        var band = DecorativeItem(kind: .border, quantity: 6)
        band.toggleLocation(decorativeLocationOptions(shower)[1])
        shower.walls[1].name = "Half wall"                     // renamed: still linked
        #expect(decorativeLocationLabels(band, in: shower) == ["Half wall"])
        shower.walls.remove(at: 1)                              // removed: dropped
        #expect(decorativeLocationLabels(band, in: shower).isEmpty)

        // Chosen while all walls were the same, then the walls were split.
        var tub = section(.tub, sqft: 50)
        var b2 = DecorativeItem(kind: .band)
        b2.toggleLocation(decorativeLocationOptions(tub)[0])  // "Back Wall"
        tub.walls = [TiledWall(name: "Back wall", sqft: 30), TiledWall(name: "Left wall", sqft: 20)]
        #expect(decorativeLocationLabels(b2, in: tub) == ["Back wall"])
    }

    @Test func theEstimateSaysWhereButThePriceIgnoresIt() {
        var tub = section(.tub, sqft: 50, type: .porcelain, size: .rectangle, widthIn: 12, lengthIn: 24)
        var band = DecorativeItem(kind: .band, quantity: 10,
                                  tile: TileChoice(tileType: .glass, tileSize: .mosaic, mosaicStyle: .pennyRound))
        let opts = decorativeLocationOptions(tub)
        band.toggleLocation(opts[0]); band.toggleLocation(opts[1])
        tub.decoratives = [band]
        #expect(describeSection(tub).contains("Band of Glass Penny Round Mosaic on Back Wall & Left Wall"))

        var r = rates()
        r.base[.tub] = 26
        r.minimum[.tub] = 0
        var noPlace = tub
        noPlace.decoratives[0].locations = []
        #expect(price(tub, r) == price(noPlace, r))
    }

    @Test func anOldMosaicBandBecomesAnInlayAtTheSamePrice() throws {
        // Saved before bands, borders and inlays: one switch and its square feet.
        let json = """
        {"id":"4E1D1C4A-0000-4000-8000-000000000002","area":"Wall","tileType":"Ceramic",
         "tileSize":"Hexagon","layout":"Straight Stacked",
         "features":{"mosaicBand":true},"measurements":{"sqft":100,"mosaicSqft":6}}
        """
        let s = try JSONDecoder().decode(EstimateSection.self, from: Data(json.utf8))
        #expect(s.decoratives.count == 1)
        #expect(s.decoratives[0].kind == .inlay)
        #expect(s.decoratives[0].quantity == 6)
        #expect(!s.features.mosaicBand)
        #expect(price(s, rates()) == 2000 + 6 * 40)     // same as the old inlay price
    }

    @Test func savedDataWithoutThemStillLoads() throws {
        let json = #"{"area":"Wall","measurements":{"sqft":100}}"#
        let s = try JSONDecoder().decode(EstimateSection.self, from: Data(json.utf8))
        #expect(s.decoratives.isEmpty)
        let r = try JSONDecoder().decode(Rates.self, from: Data(#"{"mosaicInlayRate":35}"#.utf8))
        #expect(r.mosaicInlayRate == 35)
        #expect(r.bandRatePerLinFt == 0 && r.borderRatePerLinFt == 0)

        let item = try JSONDecoder().decode(DecorativeItem.self, from: Data(#"{"kind":"Border","quantity":9}"#.utf8))
        #expect(item.kind == .border && item.quantity == 9 && item.locations.isEmpty)

        var saved = section(.shower)
        saved.decoratives = [DecorativeItem(kind: .band, name: "Accent", quantity: 7.5,
                                            tile: TileChoice(tileType: .glass, tileSize: .mosaic, mosaicStyle: .picket),
                                            locations: ["Back Wall", "Ceiling"])]
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(saved))
        #expect(back == saved)
        let state = try JSONDecoder().decode(EstimatorState.self, from: JSONEncoder().encode(EstimatorState(section: saved)))
        #expect(state.decoratives == saved.decoratives)
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

    @Test func aSeparateTileUsesItsOwnSize() {
        var r = rates()
        r.sizeAdderPerDoubling = 1
        r.sizeAdderPerHalving = 1
        var s = shower()
        s.showerFloorTile = TileChoice(tileType: .ceramic, tileSize: .square, layout: .straightStacked,
                                       tileWidthIn: 6, tileLengthIn: 6)
        // 6×6 floor is 3 halvings: 10 × ($25 + $3). Walls stay at 12×24.
        #expect(abs(price(s, r) - (3000 + 280)) < 1e-9)
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
        r.sizeAdderPerDoubling = 1
        r.sizeAdderPerHalving = 1
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
            wall("Right Wall", 30, w: 24, l: 24),           // 1 doubling: $1
        ])
        // Base: 100 × $30 = $3,000, above the $1,200 minimum.
        #expect(abs(price(s, rates()) - Double(3000 + 40 * 13 + 30 * 1)) < 1e-9)
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
        // Base 50 × $26 = $1,300 over the $900 minimum; marble $8 × 30; 24×24 1 doubling × 10.
        #expect(abs(price(s, r) - (1300 + 240 + 10)) < 1e-9)
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
        // Saved before the doubling rule: the old Over/Under keys, no size keys.
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
        #expect(r.sizeAdderPerDoubling == 2.5)
        #expect(r.sizeAdderPerHalving == 2.5)
    }

    @Test func ratesSavedBeforeTheNewMaterialsGetThemAtZero() throws {
        let json = #"{"typeAdder":["Ceramic",0,"Marble",4,"Slate",2]}"#
        let r = try JSONDecoder().decode(Rates.self, from: Data(json.utf8))
        #expect(r.typeAdder[.marble] == 4)
        #expect(r.typeAdder[.slate] == 2)
        for t in [TileType.granite, .quartzite, .cement, .terracotta, .zellige] {
            #expect(r.typeAdder[t] == 0)
        }
    }

    @Test func aNewMaterialIsPricedWithItsAdder() {
        var r = plainRates()
        r.base[.floor] = 20
        r.minimum[.floor] = 0
        r.floorEscAdjPerSqft = 0
        r.typeAdder[.zellige] = 6
        #expect(price(section(.floor, sqft: 100, type: .zellige), r) == 2600)
    }

    @Test func ratesSavedWithTheStepSettingsStillLoad() throws {
        // Saved between 2026-09-26 and 2026-09-27, under the step rule.
        let json = #"{"base":["Floor",21],"sizeBaseAreaSqIn":288,"sizeStepSqIn":54,"sizeStepAdder":1.25}"#
        let r = try JSONDecoder().decode(Rates.self, from: Data(json.utf8))
        #expect(r.base[.floor] == 21)
        #expect(r.sizeBaseAreaSqIn == 288)
        #expect(r.sizeAdderPerDoubling == 2.5)
        #expect(r.sizeAdderPerHalving == 2.5)
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

/// The saved estimates file must never be lost to a save after a bad read.
struct SavedEstimatesSafetyTests {
    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func estimate(_ title: String) -> SavedEstimate {
        let party = PartyInfo(name: "", address: "", phone: "", email: "")
        return SavedEstimate(title: title, estimateNumber: 1, biz: party, cust: party,
                             shipping: 0, taxPercent: 0, forceSinglePage: false, document: EstimateDocument())
    }

    private func backupFiles(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func anUnreadableFileIsKeptBeforeAnythingIsSaved() throws {
        let dir = try tempFolder()
        let file = dir.appendingPathComponent("SavedEstimates.json")
        let backups = DataBackups(folder: dir.appendingPathComponent("Data Backups"))
        let garbage = Data("[{\"title\": broken".utf8)
        try garbage.write(to: file)

        let store = SavedEstimatesStore(fileURL: file, backups: backups)
        #expect(store.items.isEmpty)
        #expect(store.loadProblem != nil)
        let kept = backupFiles(backups.folder).filter { $0.hasPrefix("SavedEstimates unreadable") }
        #expect(kept.count == 1)
        #expect(try Data(contentsOf: backups.folder.appendingPathComponent(kept[0])) == garbage)

        // Saving afterwards writes a new list; the original stays in the copy.
        store.add(estimate("New"))
        #expect(SavedEstimatesStore(fileURL: file, backups: backups).items.map(\.title) == ["New"])
        #expect(try Data(contentsOf: backups.folder.appendingPathComponent(kept[0])) == garbage)
    }

    @Test func oneUnreadableEstimateDoesNotLoseTheOthers() throws {
        let dir = try tempFolder()
        let file = dir.appendingPathComponent("SavedEstimates.json")
        let backups = DataBackups(folder: dir.appendingPathComponent("Data Backups"))
        let good = try JSONEncoder().encode([estimate("Kitchen"), estimate("Bath")])
        var list = try JSONSerialization.jsonObject(with: good) as! [Any]
        list.insert("not an estimate", at: 1)
        try JSONSerialization.data(withJSONObject: list).write(to: file)

        let store = SavedEstimatesStore(fileURL: file, backups: backups)
        #expect(store.items.map(\.title) == ["Kitchen", "Bath"])
        #expect(store.loadProblem?.hasPrefix("1 saved estimate couldn't be read") == true)
        #expect(backupFiles(backups.folder).contains { $0.hasPrefix("SavedEstimates unreadable") })
    }

    @Test func aGoodFileLoadsWithNoWarningAndIsBackedUpBeforeSaving() throws {
        let dir = try tempFolder()
        let file = dir.appendingPathComponent("SavedEstimates.json")
        let backups = DataBackups(folder: dir.appendingPathComponent("Data Backups"))
        let original = try JSONEncoder().encode([estimate("Kitchen")])
        try original.write(to: file)

        let store = SavedEstimatesStore(fileURL: file, backups: backups)
        #expect(store.loadProblem == nil)
        store.add(estimate("Bath"))
        let daily = backupFiles(backups.folder).filter { !$0.contains("unreadable") }
        #expect(daily.count == 1)
        #expect(try Data(contentsOf: backups.folder.appendingPathComponent(daily[0])) == original)
        #expect(SavedEstimatesStore(fileURL: file, backups: backups).items.map(\.title) == ["Bath", "Kitchen"])
    }

    @Test func noFileMeansAnEmptyListAndNoWarning() throws {
        let dir = try tempFolder()
        let store = SavedEstimatesStore(fileURL: dir.appendingPathComponent("SavedEstimates.json"),
                                        backups: DataBackups(folder: dir.appendingPathComponent("Data Backups")))
        #expect(store.items.isEmpty)
        #expect(store.loadProblem == nil)
    }

    @Test func dailyBackupsKeepOnlyTheNewestDays() throws {
        let backups = DataBackups(folder: try tempFolder())
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        for i in 0..<20 {
            backups.daily(Data("\(i)".utf8), name: "Rates", keep: 14, now: start + Double(i) * day)
        }
        // A second save the same day doesn't replace that day's copy.
        backups.daily(Data("later".utf8), name: "Rates", keep: 14, now: start + 19 * day + 60)
        let files = backupFiles(backups.folder)
        #expect(files.count == 14)
        #expect(try Data(contentsOf: backups.folder.appendingPathComponent(files.last!)) == Data("19".utf8))
    }
}

/// Saved estimates open priced as they were saved (2026-10-05 on). Serialized:
/// two of these use the app's own saved settings, which tests can't share at once.
@Suite(.serialized)
struct QuoteHistoryTests {
    private func estimate(rates: Rates?) -> SavedEstimate {
        let party = PartyInfo(name: "", address: "", phone: "", email: "")
        var room = EstimateRoom(name: "Bath")
        room.sections = [section(.floor, sqft: 120, type: .porcelain)]
        return SavedEstimate(title: "Bath", estimateNumber: 7, biz: party, cust: party,
                             shipping: 0, taxPercent: 0, forceSinglePage: false,
                             document: EstimateDocument(rooms: [room]), rates: rates, total: 2400)
    }

    @Test func anEstimateSavedBeforePricesWereKeptHasNoRates() throws {
        let json = #"[{"title":"Old","estimateNumber":3,"shipping":0,"taxPercent":0,"forceSinglePage":false,"document":{"rooms":[]}}]"#
        let list = try JSONDecoder().decode([SavedEstimate].self, from: Data(json.utf8))
        #expect(list.count == 1)
        #expect(list[0].rates == nil)
        #expect(list[0].total == nil)
    }

    @Test func savedRatesAndTotalComeBackAsSaved() throws {
        var r = plainRates()
        r.base[.floor] = 20
        let back = try JSONDecoder().decode(SavedEstimate.self, from: JSONEncoder().encode(estimate(rates: r)))
        #expect(back.rates == r)
        #expect(back.total == 2400)
    }

    @Test func anOpenedEstimateKeepsItsSavedRatesUntilConverted() {
        let keys = ["TileRate.state", "TileRate.rates", "TileRate.document", "TileRate.openedPricing"]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, before) { UserDefaults.standard.set(v, forKey: k) } }

        let store = Store()
        var current = plainRates()
        current.base[.floor] = 25
        current.minimum[.floor] = 0
        current.floorEscAdjPerSqft = 0
        store.rates = current
        var then = current
        then.base[.floor] = 20

        store.open(estimate(rates: then))
        #expect(store.isPricedWithSavedRates)
        #expect(computeTotals(document: store.doc, rates: store.pricingRates, shippingEnabled: false,
                              shipping: 0, taxPercent: 0).grandTotal == 2400)
        // Changing the rates in Admin doesn't move it.
        store.rates.base[.floor] = 30
        #expect(store.pricingRates.base[.floor] == 20)
        // It survives the app closing.
        #expect(Store().pricingRates.base[.floor] == 20)

        store.convertToCurrentPricing()
        #expect(!store.isPricedWithSavedRates)
        #expect(computeTotals(document: store.doc, rates: store.pricingRates, shippingEnabled: false,
                              shipping: 0, taxPercent: 0).grandTotal == 3600)
    }

    @Test func anEstimateSavedWithoutRatesIsPricedAtTheCurrentOnes() {
        let keys = ["TileRate.state", "TileRate.rates", "TileRate.document", "TileRate.openedPricing"]
        let before = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (k, v) in zip(keys, before) { UserDefaults.standard.set(v, forKey: k) } }

        let store = Store()
        store.open(estimate(rates: nil))
        #expect(store.opened != nil)
        #expect(!store.isPricedWithSavedRates)
        #expect(store.pricingRates == store.rates)
        store.reset()
        #expect(store.opened == nil)
    }
}
