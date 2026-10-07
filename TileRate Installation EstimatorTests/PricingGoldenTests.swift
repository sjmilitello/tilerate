import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// Both pricing engines against the prices recorded on 2026-10-06
/// (PricingCases.swift, PricingGolden.swift): every line, label and amount.
@Suite(.serialized)
struct PricingGoldenTests {
    private struct Expected: Decodable {
        let name: String
        let total: Double
        let lines: [[Value]]

        enum Value: Decodable {
            case text(String), number(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .text(s) } else { self = .number(try c.decode(Double.self)) }
            }
        }

        var pairs: [(String, Double)] {
            lines.map { line in
                guard case let .text(label) = line[0], case let .number(amount) = line[1] else { return ("?", .nan) }
                return (label, amount)
            }
        }
    }

    private static let expected: [String: Expected] = {
        let list = try! JSONDecoder().decode([Expected].self, from: Data(pricingGoldenJSON.utf8))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
    }()

    /// Differences between a summary and what was recorded, for the failure message.
    private func differences(_ s: Summary, _ e: Expected) -> [String] {
        var out: [String] = []
        if abs(s.total - e.total) > 1e-6 { out.append("total \(s.total) ≠ \(e.total)") }
        let got = s.lines.map { ($0.label, $0.amount) }
        if got.count != e.pairs.count { out.append("\(got.count) lines ≠ \(e.pairs.count)") }
        for (g, x) in zip(got, e.pairs) where g.0 != x.0 || abs(g.1 - x.1) > 1e-6 {
            out.append("\"\(g.0)\" \(g.1) ≠ \"\(x.0)\" \(x.1)")
        }
        return out
    }

    @Test func everyCaseWasRecorded() {
        let names = PricingCases.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(Set(names) == Set(Self.expected.keys))
    }

    @Test func todaysPricingStillGivesTheRecordedPrices() {
        let failures = PricingCases.all.compactMap { c -> String? in
            guard let e = Self.expected[c.name] else { return nil }
            let d = differences(legacySummary(state: EstimatorState(section: c.section), rates: c.rates), e)
            return d.isEmpty ? nil : "\(c.name): \(d.joined(separator: "; "))"
        }
        #expect(failures.isEmpty, "\(failures.count) differ, e.g.\n\(failures.prefix(10).joined(separator: "\n"))")
    }

    @Test func theSchemeGivesTheRecordedPrices() {
        let failures = PricingCases.all.compactMap { c -> String? in
            guard let e = Self.expected[c.name] else { return nil }
            let s = schemeSummary(state: EstimatorState(section: c.section), scheme: PricingScheme(rates: c.rates))
            let d = differences(s, e)
            return d.isEmpty ? nil : "\(c.name): \(d.joined(separator: "; "))"
        }
        #expect(failures.isEmpty, "\(failures.count) differ, e.g.\n\(failures.prefix(10).joined(separator: "\n"))")
    }

    @Test func theOwnersFloorRuleIsAnEscalatorWindow() {
        let scheme = PricingScheme(rates: PricingCases.ownerLike)
        let floor = scheme.areas[.floor]
        #expect(floor?.chargesFeatures == false)
        #expect(floor?.surfaces.first?.rule ==
                .escalator(perSqft: 21, minimum: 1500, window: EscalatorWindow(from: 50, through: 99, perSqft: 14)))
        #expect(scheme.areas[.shower]?.surfaces.map(\.label) == ["Shower walls", "Shower floor"])
    }

    @Test func withTheSwitchOnTheSchemePricesAndNothingDiffers() {
        let d = UserDefaults.standard
        let before = d.object(forKey: PricingEngine.key)
        PricingEngine.clearDifferences()
        d.set(true, forKey: PricingEngine.key)
        defer { d.set(before, forKey: PricingEngine.key) }

        let differing = PricingCases.all.prefix(300).filter { c in
            let state = EstimatorState(section: c.section)
            return !PricingEngine.same(computeSummary(state: state, rates: c.rates),
                                       legacySummary(state: state, rates: c.rates))
        }
        #expect(differing.isEmpty, "\(differing.prefix(10).map(\.name))")
        #expect(PricingEngine.status.differences == 0)
    }

    @Test func aDifferenceFallsBackToTodaysPriceAndIsNoted() {
        PricingEngine.clearDifferences()
        defer { PricingEngine.clearDifferences() }
        let today = Summary(lines: [Line(label: "Wall @ $27.00/sqft × 10", amount: 270)], total: 270)
        let other = Summary(lines: [Line(label: "Wall @ $27.00/sqft × 10", amount: 280)], total: 280)
        #expect(PricingEngine.check(current: today, scheme: other, area: .wall).total == 270)
        #expect(PricingEngine.status.differences == 1)
        #expect(PricingEngine.status.last?.hasPrefix("Wall:") == true)
        #expect(PricingEngine.check(current: today, scheme: today, area: .wall).total == 270)
        #expect(PricingEngine.status.differences == 1)
    }
}
