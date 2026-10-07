import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Rules chosen per surface in Admin → Area pricing (roadmap Phase 5).
struct SurfaceRuleTests {
    /// The owner's floor as recorded on the phone (2026-10-05): $22/sq ft, a
    /// $1,500 minimum, $14 per sq ft over 50 up to 99.
    private var ownersFloor: SurfaceRule {
        .escalator(perSqft: 22, minimum: 1500, window: EscalatorWindow(from: 50, through: 99, perSqft: 14))
    }

    @Test func theUsualRulesComeFromTheRateFieldsAndGoBackIntoThem() {
        var r = PricingCases.ownerLike
        #expect(r.rule(for: .floor) == .escalator(perSqft: 21, minimum: 1500,
                                                  window: EscalatorWindow(from: 50, through: 99, perSqft: 14)))
        #expect(r.rule(for: .backsplash) == .rate(perSqft: 32, minimum: 650))
        #expect(r.rule(for: .ceiling) == .rate(perSqft: 25, minimum: 600))

        r.setRule(ownersFloor, for: .floor)
        #expect(r.base[.floor] == 22 && r.floorEscAdjPerSqft == 14)
        r.setRule(.rate(perSqft: 40, minimum: 700), for: .showerFloor)
        #expect(r.showerFloorBase == 40 && r.showerFloorMinimum == 700)
        #expect(r.surfaceRules.isEmpty)
    }

    @Test func aDifferentKindOfRuleIsKeptApartAndPricesTheArea() {
        var r = PricingCases.ownerLike
        r.setRule(.rate(perSqft: 30, minimum: 900), for: .floor)
        #expect(r.surfaceRules[.floor] == .rate(perSqft: 30, minimum: 900))
        #expect(r.base[.floor] == 21)        // the fields are left as they were
        let floor = PricingCases.section(.floor, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked), sqft: 60)
        #expect(computeSummary(state: EstimatorState(section: floor), rates: r).total == 60 * (30 + 2))

        // Back to the usual kind: the override goes, the fields take it.
        r.setRule(ownersFloor, for: .floor)
        #expect(r.surfaceRules.isEmpty)
        #expect(r.base[.floor] == 22)
    }

    @Test func aCeilingCanHaveItsOwnEscalator() throws {
        let e = try #require(suggestedEscalator(perSqft: 25, minimum: 600, from: 15, through: 30))
        #expect(e == 10.93)
        let rule = SurfaceRule.escalator(perSqft: 25, minimum: 600, window: EscalatorWindow(from: 15, through: 30, perSqft: e))
        #expect(basePrice(rule, sqft: 10) == 600)
        #expect(abs(basePrice(rule, sqft: 20) - 654.65) < 0.001)
        #expect(abs(basePrice(rule, sqft: 30) - 763.95) < 0.001)
        #expect(basePrice(rule, sqft: 31) == 775)
        #expect(firstPriceDrop(rule) == nil)

        var r = PricingCases.ownerLike
        r.setRule(rule, for: .ceiling)
        var shower = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked),
                                          showerWalls: 90, showerFloor: 16, ceiling: 20)
        shower.ceilingTile = PricingCases.tile(.ceramic, .hexagon, .straightStacked)
        let lines = computeSummary(state: EstimatorState(section: shower), rates: r).lines.map(\.label)
        #expect(lines.contains("Ceiling — Minimum Applied"))
        #expect(lines.contains("Ceiling escalator @ $10.93/sqft × 5"))
        #expect(lines.contains("Ceiling adders @ $2.00/sqft × 20"))
    }

    @Test func theOwnersFloorNeedsTheEscalatorItHas() {
        #expect(suggestedEscalator(perSqft: 22, minimum: 1500, from: 50, through: 99) == 14)
        #expect(firstPriceDrop(ownersFloor) == nil)
        // At $21/sq ft the same escalator would make 100 sq ft cheaper than 99.
        let cheaper = SurfaceRule.escalator(perSqft: 21, minimum: 1500, window: EscalatorWindow(from: 50, through: 99, perSqft: 14))
        let drop = firstPriceDrop(cheaper)
        #expect(drop?.sqft == 99 && drop?.price == 2186 && drop?.next == 2100)
    }

    @Test func noEscalatorIsSuggestedWithoutAGapToBridge() {
        #expect(suggestedEscalator(perSqft: 40, minimum: 1500, from: 50, through: 99) == nil)   // 40 × 50 ≥ 1500
        #expect(suggestedEscalator(perSqft: 10, minimum: 1500, from: 50, through: 99) == nil)   // 10 × 100 < 1500
    }

    @Test func wallsWithTheirOwnTilesShareAnEscalator() {
        var r = PricingCases.ownerLike
        r.setRule(.escalator(perSqft: 30, minimum: 2500, window: EscalatorWindow(from: 60, through: 99, perSqft: 20)),
                  for: .showerWalls)
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked),
                                     showerWalls: 0, showerFloor: 0)
        s.walls = [TiledWall(name: "Back", sqft: 30, tile: PricingCases.tile(.ceramic, .hexagon, .straightStacked)),
                   TiledWall(name: "Left", sqft: 40, tile: PricingCases.tile(.marble, .hexagon, .straightStacked))]
        let summary = computeSummary(state: EstimatorState(section: s), rates: r)
        // 70 sq ft together: max(30 × 70, 2500 + 10 × 20) = 2700, plus each wall's adders.
        let expected: Double = 2700 + 30 * 2 + 40 * 6
        #expect(summary.total == expected)
        #expect(summary.lines.map(\.label) == ["Shower walls — Minimum Applied", "Shower walls escalator @ $20.00/sqft × 10",
                                               "Back adders @ $2.00/sqft × 30", "Left adders @ $6.00/sqft × 40"])
    }

    @Test func chosenRulesAreSavedWithTheRates() throws {
        var r = Rates()
        r.setRule(.escalator(perSqft: 25, minimum: 600, window: EscalatorWindow(from: 15, through: 30, perSqft: 10.93)), for: .ceiling)
        r.setRule(.rate(perSqft: 30, minimum: nil), for: .floor)
        let back = try JSONDecoder().decode(Rates.self, from: JSONEncoder().encode(r))
        #expect(back.surfaceRules == r.surfaceRules)
        #expect(back.rule(for: .ceiling) == r.rule(for: .ceiling))
    }
}
