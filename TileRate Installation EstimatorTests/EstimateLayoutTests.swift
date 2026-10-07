import Foundation
import Testing
import UIKit
@testable import TileRate_Installation_Estimator

/// Estimate layouts (roadmap Phase 4).
@MainActor
struct EstimateLayoutTests {
    private static let party = PartyInfo(name: "Integrity Tile", address: "1 Main St", cityStateZip: "Town, ST 00000",
                                         phone: "555-0100", email: "")
    private static let customer = PartyInfo(name: "A Customer", address: "2 Oak Ave", phone: "", email: "")

    /// An estimate with tile work, labor and material extras (taxable and
    /// not), grouped demolition items and a custom line.
    private static func estimate(extras: Bool = true, rooms: Int = 1) -> EstimateDocument {
        var doc = EstimateDocument()
        for r in 0..<rooms {
            var room = EstimateRoom(name: "Room \(r + 1)")
            var shower = PricingCases.section(.shower, tile: PricingCases.tile(.porcelain, .rectangle, .runningBond, w: 12, l: 24),
                                              showerWalls: 90, showerFloor: 16)
            shower.features = Features(niches: 1, benches: 1)
            var floor = PricingCases.section(.floor, tile: PricingCases.tile(.porcelain, .rectangle, .herringbone, w: 12, l: 24), sqft: 72)
            if extras {
                shower.additionsLabor = [
                    AdditionItem(activity: "Demo: Tile walls", qty: 90, rate: 4),
                    AdditionItem(activity: "Waterproofing", qty: 1, rate: 350),
                    AdditionItem(activity: "Demo: Tile shower base", qty: 16, rate: 6, minimum: 150),
                ]
                shower.additionsMaterials = [
                    AdditionItem(activity: "Schluter trim", qty: 4, rate: 38.5, taxable: true),
                    AdditionItem(activity: "Thinset", qty: 6, rate: 31, taxable: true),
                ]
                floor.additionsLabor = [AdditionItem(activity: "Demo: Vinyl floor", qty: 72, rate: 2.25)]
            }
            room.sections = [shower, floor]
            doc.rooms.append(room)
        }
        return doc
    }

    private static func totals(_ doc: EstimateDocument, rates: Rates = PricingCases.ownerLike) -> EstimateTotals {
        computeTotals(document: doc, rates: rates, shippingEnabled: true, shipping: 85, taxPercent: 6.25)
    }

    private static func pages(_ data: Data) -> [Data] {
        guard let count = PDFKitPageCount(data) else { return [] }
        return (0..<count).compactMap { pdfToImage(data: data, pageIndex: $0, scale: 1)?.pngData() }
    }

    @Test func theClassicLayoutDrawsTheEstimateExactlyAsBefore() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        for (doc, single) in [(Self.estimate(), false), (Self.estimate(extras: false), false),
                              (Self.estimate(rooms: 4), false), (Self.estimate(rooms: 3), true)] {
            let t = Self.totals(doc)
            let before = ExportedFormPDFView(biz: Self.party, cust: Self.customer, estimateNumber: 1427, date: date,
                                             descriptionLine: "", forceSinglePage: single, logo: nil,
                                             subtotal: t.subtotal, shipping: t.shipping, taxPercent: t.taxPercent,
                                             taxBase: t.taxableBase,
                                             additionalLabor: t.sections.flatMap(\.laborItems),
                                             materials: t.sections.flatMap(\.materialItems),
                                             blocks: EstimatePDF.blocks(t))
            let now = EstimatePDF.view(totals: t, template: .classic, biz: Self.party, cust: Self.customer,
                                       logo: nil, estimateNumber: 1427, date: date)
            let a = Self.pages(try PDFGenerator.render(view: before, forceSinglePage: single))
            let b = Self.pages(try PDFGenerator.render(view: now, forceSinglePage: single))
            #expect(!a.isEmpty)
            #expect(a.count == b.count)
            #expect(a == b, "pages differ (\(doc.rooms.count) rooms, single page: \(single))")
        }
    }

    @Test func everyLayoutAddsUpToTheSameSubtotal() {
        for doc in [Self.estimate(), Self.estimate(extras: false), Self.estimate(rooms: 3)] {
            let t = Self.totals(doc)
            for template in EstimateTemplate.starters {
                for grouped in [false, true] {
                    var tpl = template
                    tpl.groupPriceList = grouped
                    let sum = estimateRows(t, template: tpl).reduce(0) { $0 + $1.amount }
                    #expect(abs(sum - t.subtotal) < 0.005, "\(template.name), grouped: \(grouped)")
                }
            }
        }
    }

    @Test func groupedPriceListItemsShareOneLineWithTheirTotal() {
        var tpl = EstimateTemplate.classic
        tpl.groupPriceList = true
        let rows = estimateRows(Self.totals(Self.estimate()), template: tpl)
        let shower = Array(rows.prefix(5))
        #expect(shower.map(\.description).dropFirst() == ["Demolition", "Waterproofing", "Schluter trim", "Thinset"])
        let demo = shower[1]
        #expect(demo.amount == 90 * 4 + 150)
        #expect(demo.details == ["Tile walls", "Tile shower base"])
        // A group with one item stays as that item.
        #expect(rows.contains { $0.description == "Demo: Vinyl floor" })

        tpl.listGroupedItems = false
        #expect(estimateRows(Self.totals(Self.estimate()), template: tpl)[1].details.isEmpty)
    }

    @Test func taxableAndUntaxedItemsAreNeverGroupedTogether() {
        let items = [AdditionItem(activity: "Trim: Schluter", qty: 1, rate: 40, taxable: true),
                     AdditionItem(activity: "Trim: Labor to miter", qty: 1, rate: 60),
                     AdditionItem(activity: "Trim: Bullnose", qty: 1, rate: 30, taxable: true)]
        var tpl = EstimateTemplate.classic
        tpl.groupPriceList = true
        let rows = extraRows(items, title: "Sales", template: tpl)
        #expect(rows.count == 2)
        #expect(rows[0].amount == 70 && rows[0].taxable)
        #expect(rows[1].description == "Trim: Labor to miter")
    }

    @Test func layoutsDecideWhatEachAreaShows() {
        let t = Self.totals(Self.estimate())
        let summary = estimateRows(t, template: EstimateTemplate.starters[1])
        #expect(summary.count == 2)
        #expect(summary[0].amount == t.sections[0].subtotal)
        #expect(summary[0].details == ["Demolition", "Waterproofing", "Schluter trim", "Thinset"])

        let split = estimateRows(t, template: EstimateTemplate.starters[2])
        #expect(split.map(\.title) == ["Installation", "Materials", "Installation"])
        #expect(split[0].amount == t.sections[0].core.total + t.sections[0].labor)
        #expect(split[1].amount == t.sections[0].mats && split[1].taxable)
    }

    @Test func layoutsAreSavedWithTheRatesAndEachEstimate() throws {
        // Rates saved before layouts get the starters, with Classic as default.
        let old = try JSONDecoder().decode(Rates.self, from: Data(#"{"base":["Floor",21]}"#.utf8))
        #expect(old.estimateTemplates == EstimateTemplate.starters)
        #expect(old.template(nil) == .classic)

        var r = Rates()
        var mine = EstimateTemplate.classic
        mine.id = UUID(); mine.name = "Mine"; mine.title = "Quote"; mine.validForDays = 14
        mine.sections = [.init(heading: "Terms", body: "Net 15.")]
        r.estimateTemplates.append(mine)
        r.defaultTemplateID = mine.id
        let back = try JSONDecoder().decode(Rates.self, from: JSONEncoder().encode(r))
        #expect(back.template(nil) == mine)
        #expect(back.template(EstimateTemplate.classicID) == .classic)
        #expect(back.template(UUID()) == mine)   // unknown: the default

        let party = PartyInfo(name: "", address: "", phone: "", email: "")
        let saved = SavedEstimate(title: "T", estimateNumber: 1, biz: party, cust: party, shipping: 0, taxPercent: 0,
                                  forceSinglePage: false, document: EstimateDocument(), rates: r, templateID: mine.id)
        let decoded = try JSONDecoder().decode(SavedEstimate.self, from: JSONEncoder().encode(saved))
        #expect(decoded.templateID == mine.id)
    }
}

private func PDFKitPageCount(_ data: Data) -> Int? {
    guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider) else { return nil }
    return doc.numberOfPages
}
