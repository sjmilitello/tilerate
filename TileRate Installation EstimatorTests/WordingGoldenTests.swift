import Foundation
import Testing
@testable import TileRate_Installation_Estimator

/// The estimate wording as templates (roadmap Phase 3).
struct WordingGoldenTests {
    private struct Expected: Decodable { let name: String; let text: String }

    private static let expected: [String: String] = {
        let list = try! JSONDecoder().decode([Expected].self, from: Data(wordingGoldenJSON.utf8))
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0.text) })
    }()

    /// The owner's deliberate wording changes since the recording, applied
    /// to it here rather than re-recording it (2026-10-09): Limestone/
    /// Travertine is now Limestone, and a tile shape other than square or
    /// rectangle is named — "6×6 Ceramic Hexagon Tile". Anything else that
    /// differs from the recording still fails.
    static func withOwnersChanges(_ text: String, _ s: EstimateSection) -> String {
        var out = text.replacingOccurrences(of: "Limestone/Travertine", with: "Limestone")
        var tiles: [TileChoice] = s.mainTile.map { [$0] } ?? []
        tiles += s.walls.map(\.tile) + [s.showerFloorTile, s.ceilingTile].compactMap { $0 } + s.decoratives.compactMap(\.tile)
        // Each such tile's own phrase, as recorded (no shape) → as now.
        for t in tiles where ![.square, .rectangle, .mosaic].contains(t.tileSize) {
            let now = tilePhrase(t, .standard)
            let then = now.replacingOccurrences(of: " \(t.tileSize.rawValue) Tile", with: " Tile")
            for lead in ["of ", "; ", "with "] {
                out = out.replacingOccurrences(of: lead + then, with: lead + now)
            }
        }
        // Bands, borders and inlays name their tile without its pattern.
        for t in s.decoratives.compactMap(\.tile) where ![.square, .rectangle, .mosaic].contains(t.tileSize) {
            let material = t.tileType.rawValue
            out = out.replacingOccurrences(of: "of \(material) Tile on", with: "of \(material) \(t.tileSize.rawValue) Tile on")
        }
        return out
    }

    @Test func theStandardTemplatesGiveTheRecordedWording() {
        let cases = WordingCases.all
        #expect(Set(cases.map(\.name)) == Set(Self.expected.keys))
        let failures = cases.compactMap { c -> String? in
            let got = describeSection(c.section, wording: .standard)
            let want = Self.expected[c.name].map { Self.withOwnersChanges($0, c.section) }
            return got == want ? nil : "\(c.name):\n  got  \(got)\n  want \(want ?? "-")"
        }
        #expect(failures.isEmpty, "\(failures.count) differ, e.g.\n\(failures.prefix(5).joined(separator: "\n"))")
    }

    @Test func bracketsDropOutOnlyWhenEveryWordInThemIsEmpty() {
        let v = ["a": "A", "b": "", "c": "C"]
        #expect(fillTemplate("x[ {a}][ {b}]y", v) == "x Ay")
        #expect(fillTemplate("[{a} and {b}]", v) == "A and ")
        #expect(fillTemplate("[{b}{b}]!", v) == "!")
        #expect(fillTemplate("[plain words]", v) == "plain words")
        #expect(fillTemplate("{ A }-{c}", v) == "A-C")
    }

    @Test func typosAndUnclosedMarksAreLeftAsTyped() {
        let v = ["a": "A"]
        #expect(fillTemplate("{a} {colour}", v) == "A {colour}")
        #expect(fillTemplate("{a} {open", v) == "A {open")
        #expect(fillTemplate("[{a} unclosed", v) == "[A unclosed")
    }

    @Test func theOwnerCanRewordTheTileAndTheSentence() {
        var w = WordingTemplates()
        w.tile = "{material} {shape} {size}[, {layout} layout]"
        w.areas[.shower] = "Install {tiles} ({sqft})[, including {features}]"
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.porcelain, .rectangle, .herringbone, w: 12, l: 24),
                                     showerWalls: 80, showerFloor: 15)
        s.features = Features(niches: 1)
        #expect(describeSection(s, wording: w)
                == "Install Porcelain Rectangle 12×24, Herringbone layout on Walls, Floor (95 sq ft), including Niche")

        // A mosaic has no layout: its bracket drops out.
        s.tileSize = .mosaic
        s.mosaicStyle = .pennyRound
        s.features = Features()
        #expect(describeSection(s, wording: w) == "Install Porcelain Mosaic 12×24 on Walls, Floor (95 sq ft)")

        // Other areas keep the standard sentence.
        let floor = PricingCases.section(.floor, tile: PricingCases.tile(.porcelain, .rectangle, .runningBond, w: 12, l: 24), sqft: 60)
        #expect(describeSection(floor, wording: w) == "Tile installation consisting of Porcelain Rectangle 12×24, Running Bond layout on Floor.")
    }

    @Test func wordingIsSavedWithTheRates() throws {
        var r = Rates()
        r.wording.areas[.floor] = "Floor: {tiles}"
        let back = try JSONDecoder().decode(Rates.self, from: JSONEncoder().encode(r))
        #expect(back.wording == r.wording)
        // Rates saved before wording existed get the standard wording.
        let old = try JSONDecoder().decode(Rates.self, from: Data(#"{"base":["Floor",21]}"#.utf8))
        #expect(old.wording == .standard)
    }

    @Test func theEstimateUsesTheWordingOfTheRatesItIsPricedWith() {
        var r = PricingCases.ownerLike
        r.wording.areas[.wall] = "Wall tile: {tiles}."
        var room = EstimateRoom(name: "Kitchen")
        room.sections = [PricingCases.section(.wall, tile: PricingCases.tile(.ceramic, .square, .straightStacked, w: 4, l: 4), sqft: 30)]
        let totals = computeTotals(document: EstimateDocument(rooms: [room]), rates: r,
                                   shippingEnabled: false, shipping: 0, taxPercent: 0)
        #expect(totals.sections.first?.sentence == "Kitchen - Wall Wall tile: 4×4 Ceramic Tile in Straight Stacked pattern on Walls.")
    }
}

/// Wording typed over the generated sentence on one estimate.
struct CustomWordingTests {
    private func shower() -> EstimateSection {
        var s = PricingCases.section(.shower, tile: PricingCases.tile(.porcelain, .rectangle, .runningBond, w: 12, l: 24),
                                     showerWalls: 80, showerFloor: 15)
        s.features = Features(niches: 1)
        return s
    }

    @Test func typedWordingReplacesTheSentenceEverywhere() {
        var s = shower()
        s.setWording("Full shower rebuild in 12×24 porcelain.", wording: .standard)
        #expect(areaWording(s, wording: .standard).text == "Full shower rebuild in 12×24 porcelain.")
        #expect(estimateSentence(room: EstimateRoom(name: "Bath"), section: s, wording: .standard)
                == "Bath - Shower Full shower rebuild in 12×24 porcelain.")
        #expect(!areaWording(s, wording: .standard).isOutOfDate)
    }

    @Test func wordingTheSameAsGeneratedOrEmptyIsNotKept() {
        var s = shower()
        s.setWording(describeSection(s, wording: .standard), wording: .standard)
        #expect(s.customWording == nil)
        s.setWording("   ", wording: .standard)
        #expect(s.customWording == nil)
    }

    @Test func changingTheAreaFlagsTypedWordingUntilKept() {
        var s = shower()
        s.setWording("Custom words.", wording: .standard)
        s.tileWidthIn = 24; s.tileLengthIn = 48
        #expect(areaWording(s, wording: .standard).isOutOfDate)
        #expect(areaWording(s, wording: .standard).text == "Custom words.")
        s.keepWording(wording: .standard)
        #expect(!areaWording(s, wording: .standard).isOutOfDate)
    }

    @Test func customWordingIsSavedWithTheEstimate() throws {
        var s = shower()
        s.setWording("Custom words.", wording: .standard)
        let back = try JSONDecoder().decode(EstimateSection.self, from: JSONEncoder().encode(s))
        #expect(back.customWording == s.customWording)
    }

    @Test func anEditBecomesATemplateForFutureAreas() throws {
        let s = shower()
        let generated = describeSection(s, wording: .standard)
        #expect(generated == "Tile installation consisting of 12×24 Porcelain Tile in Running Bond pattern on Walls, Floor with Niche.")
        let edited = "Supply labor to install 12×24 Porcelain Tile in Running Bond pattern on Walls, Floor (95 sq ft), including Niche. Grout and caulk included."
        let template = try #require(templateFromEdit(edited, section: s, wording: .standard))
        #expect(template == "Supply labor to install {tiles}[ ({sqft})][, including {features}]. Grout and caulk included.")

        // Used for another shower with no features: the bracket drops out.
        var w = WordingTemplates()
        w.areas[.shower] = template
        var other = PricingCases.section(.shower, tile: PricingCases.tile(.marble, .square, .diagonal, w: 12, l: 12),
                                         showerWalls: 60, showerFloor: 10)
        other.features = Features()
        #expect(describeSection(other, wording: w)
                == "Supply labor to install 12×12 Marble Tile in Diagonal pattern on Walls, Floor (70 sq ft). Grout and caulk included.")
    }

    @Test func anEditInsideTheTileDescriptionCannotBecomeASentenceTemplate() {
        let edited = "Tile installation consisting of large porcelain tiles on Walls, Floor with Niche."
        #expect(templateFromEdit(edited, section: shower(), wording: .standard) == nil)
    }
}

/// Suggestions left for Admin from wording typed on an estimate.
@Suite(.serialized)
struct WordingSuggestionTests {
    @Test func aSuggestionWaitsUntilUsedOrDismissed() {
        let before = UserDefaults.standard.object(forKey: WordingSuggestions.key)
        defer { UserDefaults.standard.set(before, forKey: WordingSuggestions.key) }
        UserDefaults.standard.removeObject(forKey: WordingSuggestions.key)

        WordingSuggestions.suggest("Install {tiles}.", for: .shower)
        WordingSuggestions.suggest("Floor: {tiles}.", for: .floor)
        #expect(WordingSuggestions.all() == [.shower: "Install {tiles}.", .floor: "Floor: {tiles}."])
        WordingSuggestions.remove(.shower)
        #expect(WordingSuggestions.all() == [.floor: "Floor: {tiles}."])
        WordingSuggestions.remove(.floor)
        #expect(WordingSuggestions.all().isEmpty)
        #expect(UserDefaults.standard.object(forKey: WordingSuggestions.key) == nil)
    }
}
