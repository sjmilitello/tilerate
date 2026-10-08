import Foundation

struct AdditionItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var activity: String = ""
    var qty: Double = 1
    var rate: Double = 0
    var taxable: Bool = false
    /// What the quantity counts, e.g. "sq ft"; empty for a typed line.
    var unit: String = ""
    /// A per-sq-ft line from the price list keeps its quantity equal to the
    /// area's square feet until a quantity is typed in.
    var followsAreaSqft: Bool = false
    /// Which square feet a following line tracks.
    var measure: PriceListMeasure = .wholeArea
    /// The least this line charges; 0 means no minimum.
    var minimum: Double = 0
    var amount: Double { max(qty * rate, minimum) }
    /// True when the minimum, not quantity × price, sets the amount.
    var minimumApplied: Bool { minimum > 0 && qty * rate < minimum }
}

// MARK: - Price list for extras

enum PriceListUnit: String, Codable, CaseIterable, Identifiable {
    case perSqft = "per sq ft"
    case perLinFt = "per linear ft"
    case each = "each"
    case flat = "flat per job"
    var id: String { rawValue }
    /// What a line's quantity counts.
    var quantityLabel: String {
        switch self {
        case .perSqft: "sq ft"
        case .perLinFt: "lin ft"
        case .each: "each"
        case .flat: "job"
        }
    }
}

/// Which square feet a per-sq-ft extra fills in.
enum PriceListMeasure: String, Codable, CaseIterable, Identifiable {
    case wholeArea = "Whole area"
    case wallsOnly = "Walls only"
    case wallsAndCeiling = "Walls and ceiling"
    case floorOnly = "Floor areas only"
    case showerFloorOnly = "Shower floor only"
    case ceilingOnly = "Ceiling only"
    var id: String { rawValue }
}

/// An extra the owner charges regularly, set up once in Admin and picked for
/// an area instead of typing the price each time.
struct PriceListItem: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String = ""
    var unit: PriceListUnit = .perSqft
    /// For a per-sq-ft item, which square feet it fills in.
    var measure: PriceListMeasure = .wholeArea
    var price: Double = 0
    /// The least the item charges on an area; 0 means no minimum.
    var minimum: Double = 0
    /// Materials are taxable when `taxable` is on and count toward shipping;
    /// otherwise the item is labor.
    var isMaterial: Bool = false
    var taxable: Bool = false

    /// The owner's starting list (October 2026); prices are set in Admin.
    static let ownersStartingList: [PriceListItem] = ownersDemolition + [
        PriceListItem(id: UUID(uuidString: "6B1C2D3E-0F41-4A52-8B63-7C84D5E6F702")!, name: "Floor leveling",
                      measure: .floorOnly),
        PriceListItem(id: UUID(uuidString: "6B1C2D3E-0F41-4A52-8B63-7C84D5E6F703")!, name: "Epoxy grout upgrade"),
    ]

    /// Demolition, one item per thing torn out. Fixtures are priced each;
    /// surfaces per square foot of the part they cover.
    static let ownersDemolition: [PriceListItem] = {
        func demo(_ n: Int, _ name: String, _ unit: PriceListUnit, _ measure: PriceListMeasure = .wholeArea) -> PriceListItem {
            PriceListItem(id: UUID(uuidString: String(format: "6B1C2D3E-0F41-4A52-8B63-7C84D5E6F8%02d", n))!,
                          name: "Demo: \(name)", unit: unit, measure: measure)
        }
        return [
            demo(1, "One-piece tub/shower unit", .each),
            demo(2, "Tub only", .each),
            demo(3, "Acrylic shower base", .each),
            demo(4, "Tile shower base", .perSqft, .showerFloorOnly),
            demo(5, "Tile walls", .perSqft, .wallsOnly),
            demo(6, "Tile floors", .perSqft, .floorOnly),
            demo(7, "Tile ceiling", .perSqft, .ceilingOnly),
            demo(8, "Vinyl floor", .perSqft, .floorOnly),
            demo(9, "Laminate floor", .perSqft, .floorOnly),
            demo(10, "Hardwood floor", .perSqft, .floorOnly),
            demo(11, "Carpeting", .perSqft, .floorOnly),
            demo(12, "Plywood", .perSqft, .floorOnly),
        ]
    }()

    /// The single "Demolition" item of the first starting list (2026-10-04),
    /// replaced by `ownersDemolition` when rates are read.
    static let oldDemolitionID = UUID(uuidString: "6B1C2D3E-0F41-4A52-8B63-7C84D5E6F701")!
}

// MARK: - Domain Models

enum Area: String, CaseIterable, Codable, Identifiable {
    case floor = "Floor"
    case wall = "Wall"
    case tub = "Tub Surround"
    case shower = "Shower"
    case backsplash = "Backsplash"
    case fireplace = "Fireplace"
    var id: String { rawValue }
}

enum TileType: String, CaseIterable, Codable, Identifiable {
    case ceramic = "Ceramic"
    case porcelain = "Porcelain"
    case glass = "Glass"
    case marble = "Marble"
    case limestone = "Limestone/Travertine"
    case slate = "Slate"
    case granite = "Granite"
    case quartzite = "Quartzite"
    case cement = "Cement"
    case terracotta = "Terracotta"
    case zellige = "Zellige"
    var id: String { rawValue }
}

enum TileSize: String, CaseIterable, Hashable, Codable, Identifiable {
    case square = "Square"
    case rectangle = "Rectangle"
    case hexagon = "Hexagon"
    case arabesque = "Arabesque"
    case starCross = "Star/Cross"
    case mosaic = "Mosaic"

    var id: String { rawValue }
}

enum Layout: String, CaseIterable, Codable, Identifiable {
    case straightStacked = "Straight Stacked"
    case runningBond = "Running Bond"
    case diagonal = "Diagonal"
    case herringbone = "Herringbone"
    case multiTile = "Multi-Tile"
    var id: String { rawValue }
}

/// The style of a mosaic, chosen when the tile's shape is Mosaic. For Square
/// and Rectangular the width and length entered give the piece size.
enum MosaicStyle: String, CaseIterable, Codable, Identifiable {
    case square = "Square"
    case hexagon = "Hexagon"
    case octagonDot = "Octagon and Dot"
    case diamond = "Diamond"
    case rectangular = "Rectangular"
    case miniBrick = "Mini Brick"
    case picket = "Picket"
    case herringbone = "Herringbone"
    case chevron = "Chevron"
    case basketweave = "Basketweave"
    case pinwheel = "Pinwheel"
    case pennyRound = "Penny Round"
    case fishscale = "Fishscale"
    case arabesque = "Arabesque"
    case pebble = "Pebble"
    case randomStrip = "Random Strip"
    case waterjet = "Waterjet"
    var id: String { rawValue }
}

// MARK: - Parties

struct PartyInfo: Codable, Equatable {
    var name: String
    var address: String
    var address2: String = ""
    var cityStateZip: String = ""
    var phone: String
    var email: String
}

// MARK: - Editable Rates (Admin)

enum AdderUnit: String, Codable, CaseIterable, Identifiable {
    case perSqft = "per sqft"
    case percent = "%"
    var id: String { rawValue }
}

struct Rates: Codable, Equatable {
    var base: [Area: Double] = [
        .floor: 23, .wall: 25, .tub: 26, .shower: 32, .backsplash: 22, .fireplace: 28
    ]
    var minimum: [Area: Double] = [
        .floor: 600, .wall: 600, .tub: 900, .shower: 1200, .backsplash: 300, .fireplace: 500
    ]

    var ceilingBase: Double = 23
    var ceilingMinimum: Double = 600

    var showerFloorBase: Double = 23
    var showerFloorMinimum: Double = 600

    var typeAdder: [TileType: Double] = [
        .ceramic: 0, .porcelain: 0, .glass: 0, .marble: 0, .limestone: 0, .slate: 0,
        .granite: 0, .quartzite: 0, .cement: 0, .terracotta: 0, .zellige: 0
    ]
    var sizeAdder: [TileSize: Double] = [
        .mosaic: 0, .starCross: 0, .arabesque: 0, .hexagon: 0, .rectangle: 0, .square: 0
    ]
    var layoutAdder: [Layout: Double] = [
        .straightStacked: 0, .runningBond: 0, .diagonal: 0, .herringbone: 0, .multiTile: 0
    ]
    /// Added on top of the Mosaic size adder for a mosaic of that style.
    var mosaicStyleAdder: [MosaicStyle: Double] =
        Dictionary(uniqueKeysWithValues: MosaicStyle.allCases.map { ($0, 0) })

    struct SizeSpec: Codable, Equatable {
        var lengthIn: Double = 0
        var widthIn: Double = 0
    }
    var sizeSpecs: [TileSize: SizeSpec] = [:]

    mutating func ensureSizeAdderKeys() {
        for k in TileSize.allCases where sizeAdder[k] == nil {
            sizeAdder[k] = 0
        }
    }

    // Square and rectangle tiles: a tile of `sizeBaseAreaSqIn` (12×24) pays no
    // size adder. Every time the tile's area doubles from there adds
    // `sizeAdderPerDoubling`; every time it halves adds `sizeAdderPerHalving`.
    // Part doublings count in proportion. Both were one $2.50 figure until
    // 2026-09-29, so 24×48 (two doublings) adds $5 and 3×12 (three halvings)
    // $7.50 until the owner sets them apart.
    var sizeBaseAreaSqIn: Double = 288
    var sizeAdderPerDoubling: Double = 2.5
    var sizeAdderPerHalving: Double = 2.5

    var typeAdderUnit: AdderUnit = .perSqft
    var sizeAdderUnit: AdderUnit = .perSqft
    var layoutAdderUnit: AdderUnit = .perSqft

    /// Inlays, per square foot. (Kept under its old name so the price saved
    /// for the old mosaic band/inlay carries over.)
    var mosaicInlayRate: Double = 0
    /// Bands and borders, per linear foot.
    var bandRatePerLinFt: Double = 0
    var borderRatePerLinFt: Double = 0

    var unitShelf: Double = 600
    var unitNiche: Double = 600
    var unitFootrest: Double = 200
    var unitBench: Double = 200

    /// Electric radiant heat systems, each priced from its own parts.
    var heatingSystems: [HeatingSystem] = [.ownersStrataHeat]

    /// Extras picked from a list instead of typed each time.
    var priceList: [PriceListItem] = PriceListItem.ownersStartingList

    var floorEscThresholdLower: Int = 50
    var floorEscThresholdUpper: Int = 99
    var floorEscAdjPerSqft: Double = 0

    /// How each area is worded on the estimate. Kept with the rates so a
    /// saved estimate keeps the wording it was sent with.
    var wording = WordingTemplates()

    /// The estimate layouts (roadmap Phase 4), and the one new estimates use.
    /// Kept with the rates so a saved estimate keeps the layout it was sent in.
    var estimateTemplates: [EstimateTemplate] = EstimateTemplate.starters

    /// Pricing rules chosen in Admin → Area pricing that the rate fields above
    /// can't hold, such as an escalator on a ceiling (roadmap Phase 5). A
    /// surface priced the usual way has no entry: its numbers stay in `base`,
    /// `minimum` and the escalator fields. Read with `rule(for:)`.
    var surfaceRules: [PricedSurface: SurfaceRule] = [:]

    /// A knee wall drawn on a room scan starts this thick (inches).
    var kneeWallThicknessIn: Double = 4.5
    /// Stone curbs, wall caps and jambs, per linear foot, each on its own
    /// estimate line. Tile ones are part of the wall square feet.
    var stoneCurbPerLinFt: Double = 0
    var stoneCapPerLinFt: Double = 0
    var stoneJambPerLinFt: Double = 0
    /// A shower curb's height, for measuring jambs (inches).
    var curbHeightIn: Double = 4
    /// A shower door opening drawn on a wall starts this wide and this high
    /// (inches); the header's underside is at its height.
    var showerDoorWidthIn: Double = 30
    var showerDoorHeightIn: Double = 80
    /// Each stone piece's price: per linear foot, or per square foot once a
    /// default width is set. Keyed by `StoneItem.rawValue`; read with
    /// `stoneRate(_:)` (curb, cap and jamb fall back to the per-foot fields above).
    var stoneRates: [String: StoneRate] = [:]
    /// A bench placed on a scan: the higher of `unitBench` (its minimum) and
    /// its length at this price.
    var benchPerLinFt: Double = 0
    /// A corner seat, each (always stone).
    var unitSeat: Double = 0
    /// A window placed on a scan: its minimum; a stone wrap is priced by the
    /// window stone rate when that comes to more.
    var unitWindow: Double = 0
    /// Starting sizes for benches, niches, windows and corner pieces placed on a scan.
    var scanDefaults = ScanItemDefaults()
    var defaultTemplateID: UUID = EstimateTemplate.classicID

    /// The layout with this id, else the default, else Classic.
    func template(_ id: UUID?) -> EstimateTemplate {
        estimateTemplates.first { $0.id == id }
            ?? estimateTemplates.first { $0.id == defaultTemplateID }
            ?? estimateTemplates.first
            ?? .classic
    }
}

/// How an estimate is laid out as a PDF (roadmap Phase 4). Classic is the
/// layout the app always used; the owner can change it or add others.
struct EstimateTemplate: Identifiable, Codable, Equatable, Hashable {
    enum Detail: String, Codable, CaseIterable, Identifiable {
        case everyLine = "Every line"
        case laborAndMaterials = "Labor and materials per area"
        case areaTotals = "One price per area"
        var id: String { rawValue }
    }

    enum Accent: String, Codable, CaseIterable, Identifiable {
        case blue = "Blue", teal = "Teal", green = "Green", slate = "Slate", burgundy = "Burgundy", black = "Black"
        var id: String { rawValue }
    }

    /// A titled block of text printed after the totals: terms, exclusions,
    /// warranty, notes.
    struct TextSection: Identifiable, Codable, Equatable, Hashable {
        var id = UUID()
        var heading: String = ""
        var body: String = ""
    }

    var id = UUID()
    var name: String = "New layout"
    /// The big word at the top: "Estimate", "Proposal", "Quote".
    var title: String = "Estimate"
    var detail: Detail = .everyLine
    /// The QTY and RATE columns.
    var showQuantities: Bool = true
    /// Price list items named "Group: name" (such as "Demo: Tile walls") as
    /// one line per group instead of one line each. The total is the same.
    var groupPriceList: Bool = false
    /// Under a grouped line, the items in it.
    var listGroupedItems: Bool = true
    var accent: Accent = .blue
    /// "Valid until …", this many days after the estimate's date; 0 = not shown.
    var validForDays: Int = 0
    var sections: [TextSection] = []
    var showSignature: Bool = true
    /// Pages of the estimate's chosen 3-D views after it (owner's call: off to start).
    var include3DViews: Bool = false
    var picturesPerPage: Int = 2

    static let classicID = UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1A01")!

    /// The layout chosen for the estimate being worked on (nil: the default).
    /// Saved with it as `SavedEstimate.templateID`.
    static let chosenKey = "export.templateID"
    static var chosenID: UUID? {
        get { UserDefaults.standard.string(forKey: chosenKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: chosenKey) }
    }

    /// Today's layout, unchanged.
    static let classic = EstimateTemplate(id: classicID, name: "Classic")

    static let starters: [EstimateTemplate] = [
        classic,
        EstimateTemplate(id: UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1A02")!, name: "Summary",
                         detail: .areaTotals, showQuantities: false, groupPriceList: true),
        EstimateTemplate(id: UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1A03")!, name: "Labor & Materials",
                         detail: .laborAndMaterials, showQuantities: false, groupPriceList: true),
        EstimateTemplate(id: UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1A04")!, name: "Proposal",
                         title: "Proposal", detail: .areaTotals, showQuantities: false, groupPriceList: true,
                         accent: .slate, validForDays: 30, sections: [
                            TextSection(id: UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1B01")!,
                                        heading: "Scope of work",
                                        body: "Tile installation as described above, including surface preparation, setting, grouting and cleanup."),
                            TextSection(id: UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1B02")!,
                                        heading: "Not included",
                                        body: "Plumbing, electrical, drywall repair, painting and permits, unless listed above."),
                            TextSection(id: UUID(uuidString: "7E3A1C55-2B4D-4E6F-8A10-3C5D7E9F1B03")!,
                                        heading: "Payment",
                                        body: "50% deposit to schedule the work; balance due on completion."),
                         ]),
    ]
}

/// The estimate's wording, as templates the owner can edit (roadmap Phase 3).
/// A word in braces, like {material}, is filled in from the area. A part in
/// square brackets is left out when every brace word in it is empty, so
/// "[ in {layout} pattern]" disappears for a mosaic, which has no layout.
struct WordingTemplates: Codable, Equatable {
    /// One tile: "12×24 Porcelain Tile in Running Bond pattern". Used for the
    /// area's tile and for each wall, floor or ceiling with its own tile.
    var tile: String = WordingTemplates.standardTile
    /// The sentence for each kind of area. {tiles} is every tile with the
    /// surfaces it goes on.
    var areas: [Area: String] = Dictionary(uniqueKeysWithValues: Area.allCases.map { ($0, WordingTemplates.standardSentence) })

    static let standardTile = "[{size} ]{material} {tile}[ in {layout} pattern][ ({pieces})]"
    static let standardSentence = "Tile installation consisting of {tiles}[ with {features}]."
    static let standard = WordingTemplates()

    static let tilePlaceholders: [(name: String, meaning: String)] = [
        ("size", "Width × length, e.g. 12×24"),
        ("material", "Porcelain, Marble, …"),
        ("tile", "\"Tile\", or the mosaic style, e.g. Penny Round Mosaic"),
        ("shape", "Square, Rectangle, Hexagon, …"),
        ("mosaic", "The mosaic style alone"),
        ("layout", "Running Bond, Herringbone, … (empty for mosaics)"),
        ("pieces", "A multi-tile layout's tiles, e.g. 12×24, 24×24"),
    ]
    static let sentencePlaceholders: [(name: String, meaning: String)] = [
        ("tiles", "Each tile and what it goes on"),
        ("features", "Shelves, niches, benches, bands, borders, inlays"),
        ("area", "Shower, Floor, …"),
        ("sqft", "The area's square feet, e.g. 64 sq ft"),
    ]

    func sentence(for area: Area?) -> String {
        area.flatMap { areas[$0] } ?? Self.standardSentence
    }
}

/// Area sentences suggested from wording typed on an estimate, waiting in
/// Admin → Estimate wording to be used or dismissed. Nothing changes until
/// the owner uses one there.
enum WordingSuggestions {
    static let key = "wording.suggestions"

    static func all() -> [Area: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Area: String].self, from: data) else { return [:] }
        return list
    }

    static func suggest(_ template: String, for area: Area) {
        var list = all()
        list[area] = template
        save(list)
    }

    static func remove(_ area: Area) {
        var list = all()
        list[area] = nil
        save(list)
    }

    private static func save(_ list: [Area: String]) {
        if list.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
        else if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// Rates are saved on the phone as JSON, and the synthesized decoder refuses the
// whole value when any key is missing. A field added in a later version is
// missing from every saved copy, so the decode failed and Store fell back to
// Rates() — replacing the owner's prices, minimums and escalator with the
// defaults above. Each field is read on its own here: anything absent or
// unreadable keeps its default and everything else keeps what was saved.
// A new stored property must be added here too, or it is never loaded.
extension Rates {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)

        c.merge(.base, into: &base)
        c.merge(.minimum, into: &minimum)
        c.read(.ceilingBase, into: &ceilingBase)
        c.read(.ceilingMinimum, into: &ceilingMinimum)
        c.read(.showerFloorBase, into: &showerFloorBase)
        c.read(.showerFloorMinimum, into: &showerFloorMinimum)
        c.merge(.typeAdder, into: &typeAdder)
        c.merge(.sizeAdder, into: &sizeAdder)
        c.merge(.mosaicStyleAdder, into: &mosaicStyleAdder)
        c.merge(.layoutAdder, into: &layoutAdder)
        c.merge(.sizeSpecs, into: &sizeSpecs)
        c.read(.sizeBaseAreaSqIn, into: &sizeBaseAreaSqIn)
        c.read(.sizeAdderPerDoubling, into: &sizeAdderPerDoubling)
        // Saved before the halving adder existed: it was the same figure.
        sizeAdderPerHalving = sizeAdderPerDoubling
        c.read(.sizeAdderPerHalving, into: &sizeAdderPerHalving)
        c.read(.typeAdderUnit, into: &typeAdderUnit)
        c.read(.sizeAdderUnit, into: &sizeAdderUnit)
        c.read(.layoutAdderUnit, into: &layoutAdderUnit)
        c.read(.mosaicInlayRate, into: &mosaicInlayRate)
        c.read(.bandRatePerLinFt, into: &bandRatePerLinFt)
        c.read(.borderRatePerLinFt, into: &borderRatePerLinFt)
        c.read(.unitShelf, into: &unitShelf)
        c.read(.unitNiche, into: &unitNiche)
        c.read(.unitFootrest, into: &unitFootrest)
        c.read(.unitBench, into: &unitBench)
        c.read(.heatingSystems, into: &heatingSystems)
        c.read(.priceList, into: &priceList)
        c.read(.wording, into: &wording)
        c.read(.estimateTemplates, into: &estimateTemplates)
        c.read(.surfaceRules, into: &surfaceRules)
        c.read(.kneeWallThicknessIn, into: &kneeWallThicknessIn)
        c.read(.stoneCurbPerLinFt, into: &stoneCurbPerLinFt)
        c.read(.stoneCapPerLinFt, into: &stoneCapPerLinFt)
        c.read(.stoneJambPerLinFt, into: &stoneJambPerLinFt)
        c.read(.curbHeightIn, into: &curbHeightIn)
        c.read(.showerDoorWidthIn, into: &showerDoorWidthIn)
        c.read(.showerDoorHeightIn, into: &showerDoorHeightIn)
        c.read(.stoneRates, into: &stoneRates)
        c.read(.benchPerLinFt, into: &benchPerLinFt)
        c.read(.unitSeat, into: &unitSeat)
        c.read(.unitWindow, into: &unitWindow)
        c.read(.scanDefaults, into: &scanDefaults)
        c.read(.defaultTemplateID, into: &defaultTemplateID)
        // The first starting list had one "Demolition" item; it became one
        // item per thing torn out. Its per-sq-ft price carries over to the
        // per-sq-ft ones; fixtures priced each start at $0.
        if let i = priceList.firstIndex(where: { $0.id == PriceListItem.oldDemolitionID }) {
            let old = priceList[i]
            let split = PriceListItem.ownersDemolition.map { item -> PriceListItem in
                var item = item
                if item.unit == .perSqft {
                    item.price = old.price
                    item.minimum = old.minimum
                }
                return item
            }
            priceList.replaceSubrange(i...i, with: split)
            // That list also predates measures: floor leveling is floor only.
            if let j = priceList.firstIndex(where: { $0.name == "Floor leveling" && $0.measure == .wholeArea }) {
                priceList[j].measure = .floorOnly
            }
        }
        c.read(.floorEscThresholdLower, into: &floorEscThresholdLower)
        c.read(.floorEscThresholdUpper, into: &floorEscThresholdUpper)
        c.read(.floorEscAdjPerSqft, into: &floorEscAdjPerSqft)
    }
}

// MARK: - Measurements & Features

struct Measurements: Codable, Equatable, Hashable {
    var sqft: Double = 0
    var showerWallsSqft: Double = 0
    var showerFloorSqft: Double = 0
    var ceilingSqft: Double = 0
    /// The old single mosaic band/inlay area. Read only to convert old
    /// estimates into a `DecorativeItem`.
    var mosaicSqft: Double = 0
}

struct Features: Codable, Equatable, Hashable {
    /// The old single mosaic band/inlay switch. Read only to convert old
    /// estimates into a `DecorativeItem`.
    var mosaicBand: Bool = false
    var shelves: Int = 0
    var niches: Int = 0
    var footrests: Int = 0
    var benches: Int = 0
    /// Corner seats (always stone), each at `Rates.unitSeat`.
    var seats: Int = 0
    var windows: Int = 0
    /// Benches, niches and windows placed on a room scan, with their sizes:
    /// each is priced at the higher of its minimum and its size
    /// (`featureLines`); the rest of the count at the per-unit price.
    var sized: [SizedFeature] = []
}

/// A bench, niche or window placed on a room scan.
struct SizedFeature: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case bench, niche, window }
    var kind: Kind = .bench
    /// "Framed bench 5′ 0″", "Niche 13″ × 24″ (stone all around)".
    var label: String = ""
    /// A bench's length; a stone niche's or window's stone, in linear feet.
    var linFt: Double = 0
    /// A niche or window with stone: priced by the stone when that's more
    /// than its minimum. Without stone it's the minimum.
    var stone: Bool = false
}

/// A stone piece's price: per linear foot, or per square foot once a
/// default width is set and chosen.
struct StoneRate: Codable, Equatable, Hashable {
    var perLinFt: Double = 0
    /// The piece's usual width, inches (0: not set).
    var widthIn: Double = 0
    var bySqft: Bool = false
    var perSqft: Double = 0
    var usesSqft: Bool { bySqft && widthIn > 0 }
    /// Square feet for a run of this piece.
    func sqft(linFt: Double) -> Double { linFt * widthIn / 12 }
    func amount(linFt: Double) -> Double { usesSqft ? sqft(linFt: linFt) * perSqft : linFt * perLinFt }
}

/// Every stone piece with a price in Admin.
enum StoneItem: String, CaseIterable, Codable {
    case curb, cap, jamb, benchTop, benchFront, niche, window
    var title: String {
        switch self {
        case .curb: "Curb"
        case .cap: "Wall cap & header"
        case .jamb: "Jambs"
        case .benchTop: "Bench top"
        case .benchFront: "Bench front"
        case .niche: "Niche"
        case .window: "Window"
        }
    }
}

extension Rates {
    func stoneRate(_ item: StoneItem) -> StoneRate {
        if let r = stoneRates[item.rawValue] { return r }
        switch item {
        case .curb: return StoneRate(perLinFt: stoneCurbPerLinFt)
        case .cap: return StoneRate(perLinFt: stoneCapPerLinFt)
        case .jamb: return StoneRate(perLinFt: stoneJambPerLinFt)
        default: return StoneRate()
        }
    }

    mutating func setStoneRate(_ r: StoneRate, for item: StoneItem) {
        stoneRates[item.rawValue] = r
        switch item {
        case .curb: stoneCurbPerLinFt = r.perLinFt
        case .cap: stoneCapPerLinFt = r.perLinFt
        case .jamb: stoneJambPerLinFt = r.perLinFt
        default: break
        }
    }
}

/// Starting sizes (inches) for what's placed on a room scan; all editable in Admin.
struct ScanItemDefaults: Codable, Equatable, Hashable {
    var framedBenchHeightIn: Double = 20
    var framedBenchDepthIn: Double = 15
    var floatingBenchHeightIn: Double = 20
    var floatingBenchDepthIn: Double = 15
    var windowWidthIn: Double = 36
    var windowHeightIn: Double = 24
    var windowBottomIn: Double = 48
    var nicheWidthIn: Double = 13
    var nicheHeightIn: Double = 24
    var nicheBottomIn: Double = 48
    var cornerShelfIn: Double = 9
    var cornerShelfHeightIn: Double = 48
    var cornerFootrestIn: Double = 10
    var cornerFootrestHeightIn: Double = 18
    var cornerSeatIn: Double = 18
    var cornerSeatHeightIn: Double = 20
}

/// A decorative band, border or inlay. Bands and borders are measured and
/// priced by the linear foot, inlays by the square foot.
enum DecorativeKind: String, CaseIterable, Codable, Identifiable {
    case band = "Band"
    case border = "Border"
    case inlay = "Inlay"
    var id: String { rawValue }
    var unit: String { self == .inlay ? "sq ft" : "lin ft" }
}

/// One band, border or inlay in an area, with its own tile.
struct DecorativeItem: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var kind: DecorativeKind = .band
    var name: String = ""
    /// Linear feet for a band or border, square feet for an inlay.
    var quantity: Double = 0
    var tile = TileChoice()
    /// Where it goes in a shower or tub surround: keys from
    /// `decorativeLocationOptions`. Bands and borders can take several,
    /// an inlay one. Empty means not specified.
    var locations: [String] = []
}

/// One tile in a multi-tile layout: its shape and size.
struct TilePiece: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var shape: TileSize = .rectangle
    var widthIn: Double? = nil
    var lengthIn: Double? = nil
}

/// A tile chosen for one surface when it differs from the section's main tile —
/// a mosaic shower floor under large-format walls, say.
struct TileChoice: Codable, Equatable, Hashable {
    var tileType: TileType = .ceramic
    var tileSize: TileSize = .square
    var layout: Layout = .straightStacked
    var tileWidthIn: Double? = nil
    var tileLengthIn: Double? = nil
    /// Only used when `tileSize` is Mosaic.
    var mosaicStyle: MosaicStyle? = nil
    /// The tiles in a Multi-Tile layout, each with its own shape and size.
    var pieces: [TilePiece] = []
}

/// One shower or tub-surround wall with its own tile, used when the walls are
/// not all the same.
struct TiledWall: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String = ""
    var sqft: Double = 0
    var tile = TileChoice()
}

struct EstimatorState: Codable {
    var stepIndex: Int = 0
    var area: Area? = nil
    var tileType: TileType? = nil
    var tileSize: TileSize? = nil
    var layout: Layout? = nil
    var features = Features()
    var measurements = Measurements()

    var tileWidthIn: Double? = nil
    var tileLengthIn: Double? = nil
    /// The main tile's mosaic style, used when its shape is Mosaic.
    var mosaicStyle: MosaicStyle? = nil
    /// The main tile's pieces, used when its layout is Multi-Tile.
    var multiTilePieces: [TilePiece] = []

    /// nil means the shower floor / ceiling uses the main tile.
    var showerFloorTile: TileChoice? = nil
    var ceilingTile: TileChoice? = nil
    /// Shower and tub surround walls. Empty means all walls are the same: one
    /// area (`showerWallsSqft` for a shower, `sqft` for a tub surround) in the
    /// main tile. Otherwise each wall is priced with its own tile.
    var walls: [TiledWall] = []
    /// Bands, borders and inlays, in any number and mix.
    var decoratives: [DecorativeItem] = []
    /// Electric radiant heat under a floor or shower floor; nil means none.
    var radiantHeat: RadiantHeatChoice? = nil

    var additionsLabor: [AdditionItem] = []
    var additionsMaterials: [AdditionItem] = []
}

extension EstimatorState {
    /// The pricing input for one section of a multi-room estimate.
    init(section sec: EstimateSection) {
        self.init()
        area = sec.area
        tileType = sec.tileType
        tileSize = sec.tileSize
        layout = sec.layout
        features = sec.features
        measurements = sec.measurements
        tileWidthIn = sec.tileWidthIn
        tileLengthIn = sec.tileLengthIn
        mosaicStyle = sec.mosaicStyle
        multiTilePieces = sec.multiTilePieces
        showerFloorTile = sec.showerFloorTile
        ceilingTile = sec.ceilingTile
        walls = sec.walls
        decoratives = sec.decoratives
        radiantHeat = sec.radiantHeat
        additionsLabor = sec.additionsLabor
        additionsMaterials = sec.additionsMaterials
    }
}

extension EstimatorState {
    var additionsLaborTotal: Double {
        additionsLabor.reduce(0) { $0 + $1.amount }
    }
    var additionsMaterialsTotal: Double {
        additionsMaterials.reduce(0) { $0 + $1.amount }
    }
    var additionsMaterialsTaxableBase: Double {
        additionsMaterials.filter { $0.taxable }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Multi-room

/// Wording typed over an area's generated sentence on one estimate
/// (roadmap Phase 3).
struct CustomWording: Codable, Hashable, Equatable {
    var text: String
    /// The generated sentence when it was typed. When the area's generated
    /// sentence no longer matches it, the area has changed since.
    var generatedFrom: String
}

/// A room scanned with the iPhone's LiDAR (RoomPlan), kept with the area so
/// its plan can be seen again. Feet throughout; positions are on the floor
/// plan, seen from above.
struct ScannedRoom: Codable, Hashable, Equatable {
    struct Point: Codable, Hashable, Equatable { var x: Double = 0; var y: Double = 0 }

    struct Wall: Identifiable, Codable, Hashable, Equatable {
        var id = UUID()
        /// A, B, C… in the order the walls go round the room.
        var label: String = ""
        var lengthFt: Double = 0
        var heightFt: Double = 0
        var start = Point()
        var end = Point()
        /// A wall that isn't built yet (a knee wall), drawn on the plan by
        /// the owner. It has two faces, a top and two ends.
        var planned: Bool = false
        /// A planned wall's thickness, in inches.
        var thicknessIn: Double = 0
    }

    enum OpeningKind: String, Codable, CaseIterable {
        case door = "Door", window = "Window", opening = "Opening"
        /// A shower's door opening, drawn by the owner: never tiled, with a
        /// curb across its bottom, a jamb each side and a header over it
        /// (none when it reaches the ceiling).
        case showerDoor = "Shower door"
    }

    struct Opening: Identifiable, Codable, Hashable, Equatable {
        var id = UUID()
        var kind: OpeningKind = .door
        /// The wall it is in, when the scan could tell.
        var wallID: UUID? = nil
        var widthFt: Double = 0
        var heightFt: Double = 0
        /// Height of its bottom edge above the floor (0 for a door).
        var bottomFt: Double = 0
        /// Where its middle is along its wall, measured from the wall's start.
        var alongFt: Double? = nil
    }

    var scannedAt = Date()
    var walls: [Wall] = []
    var openings: [Opening] = []
    var floorSqft: Double = 0
    var floorOutline: [Point] = []
    /// A bathtub found in the scan: its length, for a tub surround.
    var tubLengthFt: Double? = nil
    /// The bathtub's outline on the plan, when found.
    var tubOutline: [Point] = []
    /// Toilets, sinks, vanities and the like the scanner found, for the 3-D view.
    var fixtures: [Fixture] = []
    /// Corrections from tape measurements, oldest first (the last can be undone).
    var calibrations: [ScanCalibration] = []

    /// Something the scanner found in the room: its footprint and height.
    struct Fixture: Codable, Hashable, Equatable {
        /// "Toilet", "Sink", "Cabinet", "Bathtub"…
        var kind: String = ""
        /// Its four corners on the plan.
        var outline: [Point] = []
        var heightFt: Double = 0
    }
}

/// What one area takes from a room scan: pieces of walls, each tiled to its
/// own height, the openings that come off, and the floor and ceiling.
struct AreaTakeoff: Codable, Hashable, Equatable {
    /// A stretch of one wall, tiled from the floor up to `heightIn`.
    struct Piece: Identifiable, Codable, Hashable, Equatable {
        var id = UUID()
        var wallID: UUID
        /// Where it starts and ends along the wall, from the wall's start.
        var fromFt: Double
        var toFt: Double
        var heightIn: Double
        /// Which face of the wall: 0, or 1 for the other face of a planned wall.
        var face: Int = 0
    }

    /// The owner's choice for one curb, wall cap or jamb (worked out from
    /// the plan, `TrimPiece`): tile, the default and part of the wall square
    /// feet, or stone, charged per linear foot; and a length typed over the
    /// measured one.
    struct TrimChoice: Codable, Hashable, Equatable {
        /// Which piece: "curb", "cap:<wall id>", "jamb:left", …
        var key: String
        var stone: Bool = false
        var lengthFt: Double? = nil
    }

    /// A rectangle drawn on the plan: a corner, the two directions its
    /// sides run (unit vectors on the plan), and how far each side goes.
    struct FloorRect: Codable, Hashable, Equatable {
        var origin = ScannedRoom.Point()
        var u = ScannedRoom.Point(x: 1, y: 0)
        var v = ScannedRoom.Point(x: 0, y: 1)
        var widthFt: Double = 3
        var depthFt: Double = 3

        var corners: [ScannedRoom.Point] {
            func at(_ a: Double, _ b: Double) -> ScannedRoom.Point {
                ScannedRoom.Point(x: origin.x + u.x * a + v.x * b, y: origin.y + u.y * a + v.y * b)
            }
            return [at(0, 0), at(widthFt, 0), at(widthFt, depthFt), at(0, depthFt)]
        }
    }

    enum FloorSource: String, Codable, CaseIterable {
        /// A rectangle dragged into place on the plan.
        case drawn
        /// The scanned floor, less anything excluded below.
        case room
        /// Width × depth, e.g. a shower floor inside a bigger room.
        case size
        case none
    }

    /// Something placed on a wall of the scan: a bench along it, a niche or
    /// window in it, or a corner shelf, footrest or seat at one of its ends.
    struct Item: Identifiable, Codable, Hashable, Equatable {
        enum Kind: String, Codable, CaseIterable {
            case niche, window, cornerShelf, cornerFootrest, cornerSeat, floatingBench, framedBench
            var name: String {
                switch self {
                case .niche: "Niche"
                case .window: "Window"
                case .cornerShelf: "Corner shelf"
                case .cornerFootrest: "Corner footrest"
                case .cornerSeat: "Corner seat"
                case .floatingBench: "Floating bench"
                case .framedBench: "Framed bench"
                }
            }
            var isBench: Bool { self == .floatingBench || self == .framedBench }
            var isCorner: Bool { self == .cornerShelf || self == .cornerFootrest || self == .cornerSeat }
        }
        /// A niche: tile, stone all around (top, sides, base shelf and
        /// dividers) or stone shelves only (base shelf and dividers). A
        /// window: tile or stone all around.
        enum Stone: String, Codable, CaseIterable { case tile, all, shelves }

        var id = UUID()
        var kind: Kind = .niche
        var wallID = UUID()
        /// Which face of a planned wall.
        var face: Int = 0
        /// Along the wall, from its start: a niche's, window's or bench's sides.
        var fromFt: Double = 0
        var toFt: Double = 0
        /// A niche's or window's bottom edge; a corner piece's top, off the floor.
        var bottomIn: Double = 0
        /// A niche's or window's height; a bench's top.
        var heightIn: Double = 0
        var depthIn: Double = 0
        /// A corner piece: how far it comes out along each wall.
        var sizeIn: Double = 0
        /// A corner piece: at the wall's start (else its end).
        var atStart: Bool = true
        var dividers: Int = 0
        var stone: Stone = .tile
        var widthFt: Double { max(0, toFt - fromFt) }
    }

    var pieces: [Piece] = []
    var items: [Item] = []
    /// Items have been placed here, so "Use these measurements" sets the
    /// area's niches, shelves, footrests, seats, benches and windows.
    var itemsPlaced: Bool = false
    /// Choices for the area's curb, wall caps and jambs.
    var trim: [TrimChoice] = []
    /// The shower's curb height, in inches (nil: Admin's default).
    var curbHeightIn: Double? = nil
    /// Openings taken off the pieces they fall in.
    var subtracted: [UUID] = []
    var floor: FloorSource = .none
    /// `room`: leave out the bathtub's footprint.
    var excludeTub: Bool = false
    /// `room`: square feet taken off for other things on the floor (a shower).
    var excludeSqft: Double = 0
    /// `size`: the floor's width and depth, in feet.
    var floorWidthFt: Double = 0
    var floorDepthFt: Double = 0
    /// `drawn`: the rectangle on the plan.
    var floorRect: FloorRect? = nil
    var tileCeiling: Bool = false
}

struct EstimateSection: Identifiable, Codable, Hashable, Equatable {
    var id = UUID()
    var roomName: String = ""
    /// A scan of just this area (e.g. inside a shower), used instead of
    /// the room's scan.
    var roomScan: ScannedRoom? = nil
    /// What this area takes from the scan, so reopening it shows its choices.
    var scanTakeoff: AreaTakeoff? = nil
    /// In a scanned room, this area's measurements are typed instead of
    /// taken from the model ("Enter by hand instead").
    var measuredByHand: Bool = false
    /// The owner's own wording for this area, in place of the generated one.
    var customWording: CustomWording? = nil
    var area: Area? = nil
    var tileType: TileType? = nil
    var tileSize: TileSize? = nil
    var layout: Layout? = nil
    var features = Features()
    var measurements = Measurements()
    var additionsLabor: [AdditionItem] = []
    var additionsMaterials: [AdditionItem] = []
    var tileWidthIn: Double? = nil
    var tileLengthIn: Double? = nil
    /// The main tile's mosaic style, used when its shape is Mosaic.
    var mosaicStyle: MosaicStyle? = nil
    /// The main tile's pieces, used when its layout is Multi-Tile.
    var multiTilePieces: [TilePiece] = []
    /// nil means the shower floor / ceiling uses the main tile.
    var showerFloorTile: TileChoice? = nil
    var ceilingTile: TileChoice? = nil
    /// Shower and tub surround walls. Empty means all walls are the same: one
    /// area (`showerWallsSqft` for a shower, `sqft` for a tub surround) in the
    /// main tile. Otherwise each wall is priced with its own tile.
    var walls: [TiledWall] = []
    /// Bands, borders and inlays, in any number and mix.
    var decoratives: [DecorativeItem] = []
    /// Electric radiant heat under a floor or shower floor; nil means none.
    var radiantHeat: RadiantHeatChoice? = nil
}

struct EstimateRoom: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = "Room"
    var sections: [EstimateSection] = []
    /// The room scanned with LiDAR; every area in it can measure from it.
    var scan: ScannedRoom? = nil
}

struct EstimateDocument: Codable, Equatable {
    var rooms: [EstimateRoom] = []
    /// 3-D views of the scanned areas for the PDF (layouts with "3-D views"
    /// on). Only the camera is kept: the picture is drawn from the scan and
    /// the area's choices when the PDF is made.
    var pictures: [EstimatePicture] = []
}

/// One 3-D view for the PDF: which area, the camera, and whether it goes in.
struct EstimatePicture: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var sectionID = UUID()
    /// "Shower", "Whole room", "View 1"…
    var name: String = ""
    /// The camera, in plan feet (x, height, plan y), and what it looks at.
    var eye: [Double] = [0, 5, 0]
    var target: [Double] = [0, 3, 0]
    var fixtures: Bool = true
    var included: Bool = true
}

// MARK: - Saved Estimates

struct SavedEstimate: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt: Date = Date()
    var title: String
    var estimateNumber: Int
    var biz: PartyInfo
    var cust: PartyInfo
    var shipping: Double
    var taxPercent: Double
    var forceSinglePage: Bool
    var document: EstimateDocument
    /// The rates it was priced with, so it opens as it was sent. Nil for
    /// estimates saved before 2026-10-05, which were saved without them.
    var rates: Rates? = nil
    /// The grand total when it was saved; nil before 2026-10-05.
    var total: Double? = nil
    /// The layout it was sent in (one of its rates' `estimateTemplates`);
    /// nil for estimates saved before 2026-10-07, which used Classic.
    var templateID: UUID? = nil
}

/// Where the estimate being worked on is priced from, when it was opened
/// from a saved estimate. It keeps the rates it was saved with until it is
/// converted to current pricing; one saved without rates is priced at the
/// current rates.
struct OpenedEstimatePricing: Codable, Equatable {
    var savedAt: Date
    var rates: Rates?
}

// MARK: - Reading what was saved

// Everything the app keeps — the rates, the estimate in progress and the saved
// estimates list — is decoded from JSON written by an earlier version. The
// synthesized decoder refuses a whole value when one key is missing, which is
// every saved copy the moment a field is added: Store then falls back to the
// defaults, and SavedEstimatesStore to an empty list that its next save writes
// over the file. So each type below starts from its defaults and reads each
// field on its own. A new stored property needs a line in its type's
// init(from:) as well, or it is never loaded.
extension KeyedDecodingContainer {
    /// Replaces `value` with what was saved, if it is there and readable.
    func read<T: Decodable>(_ key: Key, into value: inout T) {
        if let v = try? decodeIfPresent(T.self, forKey: key) { value = v }
    }

    /// A saved table replaces the default entry by entry, so a case added to
    /// an enum used as a key starts at its default.
    func merge<TableKey: Decodable & Hashable, V: Decodable>(_ key: Key, into table: inout [TableKey: V]) {
        if let v = try? decodeIfPresent([TableKey: V].self, forKey: key) {
            table.merge(v) { _, saved in saved }
        }
    }
}

extension AdditionItem {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.activity, into: &activity)
        c.read(.qty, into: &qty)
        c.read(.rate, into: &rate)
        c.read(.taxable, into: &taxable)
        c.read(.unit, into: &unit)
        c.read(.followsAreaSqft, into: &followsAreaSqft)
        c.read(.measure, into: &measure)
        c.read(.minimum, into: &minimum)
    }
}

extension PriceListItem {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.unit, into: &unit)
        c.read(.measure, into: &measure)
        c.read(.price, into: &price)
        c.read(.minimum, into: &minimum)
        c.read(.isMaterial, into: &isMaterial)
        c.read(.taxable, into: &taxable)
    }
}

extension EstimateSection {
    /// All the square feet tiled in the area: a shower's walls, floor and
    /// ceiling, a tub surround's walls and ceiling, or the area's one figure.
    var areaSqft: Double {
        let m = measurements
        let wallTotal = walls.reduce(0) { $0 + $1.sqft }
        switch area {
        case .shower: return (walls.isEmpty ? m.showerWallsSqft : wallTotal) + m.showerFloorSqft + m.ceilingSqft
        case .tub: return (walls.isEmpty ? m.sqft : wallTotal) + m.ceilingSqft
        default: return m.sqft
        }
    }

    /// The square feet of just the walls, or of a Floor area; 0 when the area
    /// has none of that kind (a floor has no walls; a shower floor is not a
    /// Floor area).
    func sqft(_ measure: PriceListMeasure) -> Double {
        let m = measurements
        let wallTotal = walls.reduce(0) { $0 + $1.sqft }
        switch measure {
        case .wholeArea:
            return areaSqft
        case .floorOnly:
            // Floor areas only: a shower floor (mud bed and pan) is its own item.
            return area == .floor ? m.sqft : 0
        case .showerFloorOnly:
            return area == .shower ? m.showerFloorSqft : 0
        case .ceilingOnly:
            return (area == .shower || area == .tub) ? m.ceilingSqft : 0
        case .wallsAndCeiling:
            return sqft(.wallsOnly) + ((area == .shower || area == .tub) ? m.ceilingSqft : 0)
        case .wallsOnly:
            switch area {
            case .shower: return walls.isEmpty ? m.showerWallsSqft : wallTotal
            case .tub: return walls.isEmpty ? m.sqft : wallTotal
            case .wall, .backsplash, .fireplace: return m.sqft
            default: return 0
            }
        }
    }

    /// Adds a price-list item as a labor or materials line. A per-sq-ft item
    /// starts at the area's square feet (whole, walls or floor) and follows it.
    mutating func add(_ item: PriceListItem) {
        let perSqft = item.unit == .perSqft
        let line = AdditionItem(activity: item.name, qty: perSqft ? sqft(item.measure) : 1, rate: item.price,
                                taxable: item.isMaterial && item.taxable,
                                unit: item.unit.quantityLabel, followsAreaSqft: perSqft,
                                measure: item.measure, minimum: item.minimum)
        if item.isMaterial { additionsMaterials.append(line) } else { additionsLabor.append(line) }
    }

    /// Brings every line that follows the area's square feet up to date.
    mutating func syncAreaQuantities() {
        for i in additionsLabor.indices where additionsLabor[i].followsAreaSqft {
            additionsLabor[i].qty = sqft(additionsLabor[i].measure)
        }
        for i in additionsMaterials.indices where additionsMaterials[i].followsAreaSqft {
            additionsMaterials[i].qty = sqft(additionsMaterials[i].measure)
        }
    }
}

extension Measurements {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.sqft, into: &sqft)
        c.read(.showerWallsSqft, into: &showerWallsSqft)
        c.read(.showerFloorSqft, into: &showerFloorSqft)
        c.read(.ceilingSqft, into: &ceilingSqft)
        c.read(.mosaicSqft, into: &mosaicSqft)
    }
}

extension Features {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.mosaicBand, into: &mosaicBand)
        c.read(.shelves, into: &shelves)
        c.read(.niches, into: &niches)
        c.read(.footrests, into: &footrests)
        c.read(.benches, into: &benches)
        c.read(.seats, into: &seats)
        c.read(.windows, into: &windows)
        c.read(.sized, into: &sized)
    }
}

extension SizedFeature {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.kind, into: &kind)
        c.read(.label, into: &label)
        c.read(.linFt, into: &linFt)
        c.read(.stone, into: &stone)
    }
}

extension StoneRate {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.perLinFt, into: &perLinFt)
        c.read(.widthIn, into: &widthIn)
        c.read(.bySqft, into: &bySqft)
        c.read(.perSqft, into: &perSqft)
    }
}

extension ScanItemDefaults {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.framedBenchHeightIn, into: &framedBenchHeightIn)
        c.read(.framedBenchDepthIn, into: &framedBenchDepthIn)
        c.read(.floatingBenchHeightIn, into: &floatingBenchHeightIn)
        c.read(.floatingBenchDepthIn, into: &floatingBenchDepthIn)
        c.read(.windowWidthIn, into: &windowWidthIn)
        c.read(.windowHeightIn, into: &windowHeightIn)
        c.read(.windowBottomIn, into: &windowBottomIn)
        c.read(.nicheWidthIn, into: &nicheWidthIn)
        c.read(.nicheHeightIn, into: &nicheHeightIn)
        c.read(.nicheBottomIn, into: &nicheBottomIn)
        c.read(.cornerShelfIn, into: &cornerShelfIn)
        c.read(.cornerShelfHeightIn, into: &cornerShelfHeightIn)
        c.read(.cornerFootrestIn, into: &cornerFootrestIn)
        c.read(.cornerFootrestHeightIn, into: &cornerFootrestHeightIn)
        c.read(.cornerSeatIn, into: &cornerSeatIn)
        c.read(.cornerSeatHeightIn, into: &cornerSeatHeightIn)
    }
}

extension EstimatorState {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.stepIndex, into: &stepIndex)
        c.read(.area, into: &area)
        c.read(.tileType, into: &tileType)
        c.read(.tileSize, into: &tileSize)
        c.read(.layout, into: &layout)
        c.read(.features, into: &features)
        c.read(.measurements, into: &measurements)
        c.read(.tileWidthIn, into: &tileWidthIn)
        c.read(.tileLengthIn, into: &tileLengthIn)
        c.read(.mosaicStyle, into: &mosaicStyle)
        c.read(.multiTilePieces, into: &multiTilePieces)
        c.read(.showerFloorTile, into: &showerFloorTile)
        c.read(.ceilingTile, into: &ceilingTile)
        c.read(.walls, into: &walls)
        c.read(.decoratives, into: &decoratives)
        c.read(.radiantHeat, into: &radiantHeat)
        convertOldMosaicBand(features: &features, measurements: &measurements, into: &decoratives)
        c.read(.additionsLabor, into: &additionsLabor)
        c.read(.additionsMaterials, into: &additionsMaterials)
    }
}

extension EstimateSection {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.roomName, into: &roomName)
        c.read(.customWording, into: &customWording)
        c.read(.roomScan, into: &roomScan)
        c.read(.scanTakeoff, into: &scanTakeoff)
        c.read(.measuredByHand, into: &measuredByHand)
        c.read(.area, into: &area)
        c.read(.tileType, into: &tileType)
        c.read(.tileSize, into: &tileSize)
        c.read(.layout, into: &layout)
        c.read(.features, into: &features)
        c.read(.measurements, into: &measurements)
        c.read(.additionsLabor, into: &additionsLabor)
        c.read(.additionsMaterials, into: &additionsMaterials)
        c.read(.tileWidthIn, into: &tileWidthIn)
        c.read(.tileLengthIn, into: &tileLengthIn)
        c.read(.mosaicStyle, into: &mosaicStyle)
        c.read(.multiTilePieces, into: &multiTilePieces)
        c.read(.showerFloorTile, into: &showerFloorTile)
        c.read(.ceilingTile, into: &ceilingTile)
        c.read(.walls, into: &walls)
        c.read(.decoratives, into: &decoratives)
        c.read(.radiantHeat, into: &radiantHeat)
        convertOldMosaicBand(features: &features, measurements: &measurements, into: &decoratives)
    }
}

/// Estimates saved before bands, borders and inlays had a switch for one
/// "mosaic band, border or inlay" and its square feet, priced at the inlay
/// rate. That becomes one inlay, so the price is unchanged.
private func convertOldMosaicBand(features: inout Features, measurements: inout Measurements,
                                  into decoratives: inout [DecorativeItem]) {
    guard features.mosaicBand else { return }
    if measurements.mosaicSqft > 0 {
        decoratives.append(DecorativeItem(kind: .inlay, name: "Mosaic band, border or inlay",
                                          quantity: measurements.mosaicSqft,
                                          tile: TileChoice(tileSize: .mosaic)))
    }
    features.mosaicBand = false
    measurements.mosaicSqft = 0
}

extension DecorativeItem {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.kind, into: &kind)
        c.read(.name, into: &name)
        c.read(.quantity, into: &quantity)
        c.read(.tile, into: &tile)
        c.read(.locations, into: &locations)
    }
}

extension TilePiece {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.shape, into: &shape)
        c.read(.widthIn, into: &widthIn)
        c.read(.lengthIn, into: &lengthIn)
    }
}

extension TiledWall {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.sqft, into: &sqft)
        c.read(.tile, into: &tile)
    }
}

extension TileChoice {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.tileType, into: &tileType)
        c.read(.tileSize, into: &tileSize)
        c.read(.layout, into: &layout)
        c.read(.tileWidthIn, into: &tileWidthIn)
        c.read(.tileLengthIn, into: &tileLengthIn)
        c.read(.mosaicStyle, into: &mosaicStyle)
        c.read(.pieces, into: &pieces)
    }
}

extension EstimateRoom {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.sections, into: &sections)
        c.read(.scan, into: &scan)
    }
}

extension EstimateDocument {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.rooms, into: &rooms)
        c.read(.pictures, into: &pictures)
    }
}

extension EstimatePicture {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.sectionID, into: &sectionID)
        c.read(.name, into: &name)
        c.read(.eye, into: &eye)
        c.read(.target, into: &target)
        c.read(.fixtures, into: &fixtures)
        c.read(.included, into: &included)
    }
}

// These two have fields with no default, deliberately: nothing should create a
// saved estimate without a title or a party without a name. So the fallbacks
// live here, used only when a saved copy lacks the field, and never in the
// types themselves. Blank beats losing the whole saved estimates list.
extension PartyInfo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var name = "", address = "", address2 = "", cityStateZip = "", phone = "", email = ""
        c.read(.name, into: &name)
        c.read(.address, into: &address)
        c.read(.address2, into: &address2)
        c.read(.cityStateZip, into: &cityStateZip)
        c.read(.phone, into: &phone)
        c.read(.email, into: &email)
        self.init(name: name, address: address, address2: address2,
                  cityStateZip: cityStateZip, phone: phone, email: email)
    }
}

extension SavedEstimate {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = PartyInfo(name: "", address: "", phone: "", email: "")
        var id = UUID(), createdAt = Date(), title = "", estimateNumber = 0
        var biz = blank, cust = blank
        var shipping = 0.0, taxPercent = 0.0, forceSinglePage = false
        var document = EstimateDocument()
        c.read(.id, into: &id)
        c.read(.createdAt, into: &createdAt)
        c.read(.title, into: &title)
        c.read(.estimateNumber, into: &estimateNumber)
        c.read(.biz, into: &biz)
        c.read(.cust, into: &cust)
        c.read(.shipping, into: &shipping)
        c.read(.taxPercent, into: &taxPercent)
        c.read(.forceSinglePage, into: &forceSinglePage)
        c.read(.document, into: &document)
        self.init(id: id, createdAt: createdAt, title: title, estimateNumber: estimateNumber,
                  biz: biz, cust: cust, shipping: shipping, taxPercent: taxPercent,
                  forceSinglePage: forceSinglePage, document: document)
        c.read(.rates, into: &rates)
        c.read(.total, into: &total)
        c.read(.templateID, into: &templateID)
    }
}

extension OpenedEstimatePricing {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var savedAt = Date()
        c.read(.savedAt, into: &savedAt)
        self.init(savedAt: savedAt, rates: nil)
        c.read(.rates, into: &rates)
    }
}

extension WordingTemplates {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.tile, into: &tile)
        c.merge(.areas, into: &areas)
    }
}

extension CustomWording {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var text = "", generatedFrom = ""
        c.read(.text, into: &text)
        c.read(.generatedFrom, into: &generatedFrom)
        self.init(text: text, generatedFrom: generatedFrom)
    }
}

extension EstimateTemplate {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.title, into: &title)
        c.read(.detail, into: &detail)
        c.read(.showQuantities, into: &showQuantities)
        c.read(.groupPriceList, into: &groupPriceList)
        c.read(.listGroupedItems, into: &listGroupedItems)
        c.read(.accent, into: &accent)
        c.read(.validForDays, into: &validForDays)
        c.read(.sections, into: &sections)
        c.read(.showSignature, into: &showSignature)
        c.read(.include3DViews, into: &include3DViews)
        c.read(.picturesPerPage, into: &picturesPerPage)
    }
}

extension EstimateTemplate.TextSection {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.heading, into: &heading)
        c.read(.body, into: &body)
    }
}

extension ScannedRoom {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.scannedAt, into: &scannedAt)
        c.read(.walls, into: &walls)
        c.read(.openings, into: &openings)
        c.read(.floorSqft, into: &floorSqft)
        c.read(.floorOutline, into: &floorOutline)
        c.read(.tubLengthFt, into: &tubLengthFt)
        c.read(.tubOutline, into: &tubOutline)
        c.read(.fixtures, into: &fixtures)
        c.read(.calibrations, into: &calibrations)
    }
}

/// A scan corrected to tape measurements: stretched or shrunk along the
/// room's two square directions (`angle`, the squaring angle) about
/// `center`, and up and down by `sz`.
struct ScanCalibration: Codable, Equatable, Hashable {
    var angle: Double = 0
    var sx: Double = 1
    var sy: Double = 1
    var sz: Double = 1
    var center = ScannedRoom.Point()
    /// The tape measurements it came from: wall id → inches.
    var tapeIn: [String: Double] = [:]
    var ceilingIn: Double? = nil
    var date = Date()
}

extension ScanCalibration {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.angle, into: &angle)
        c.read(.sx, into: &sx)
        c.read(.sy, into: &sy)
        c.read(.sz, into: &sz)
        c.read(.center, into: &center)
        c.read(.tapeIn, into: &tapeIn)
        c.read(.ceilingIn, into: &ceilingIn)
        c.read(.date, into: &date)
    }
}

extension ScannedRoom.Fixture {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.kind, into: &kind)
        c.read(.outline, into: &outline)
        c.read(.heightFt, into: &heightFt)
    }
}

extension EstimateSection {
    /// The area's main tile, once its type and shape are chosen.
    var mainTile: TileChoice? {
        guard let type = tileType, let size = tileSize else { return nil }
        return TileChoice(tileType: type, tileSize: size, layout: layout ?? .straightStacked,
                          tileWidthIn: tileWidthIn, tileLengthIn: tileLengthIn,
                          mosaicStyle: mosaicStyle, pieces: multiTilePieces)
    }
}

extension ScannedRoom.Point {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.x, into: &x)
        c.read(.y, into: &y)
    }
}

extension ScannedRoom.Wall {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.label, into: &label)
        c.read(.lengthFt, into: &lengthFt)
        c.read(.heightFt, into: &heightFt)
        c.read(.start, into: &start)
        c.read(.end, into: &end)
        c.read(.planned, into: &planned)
        c.read(.thicknessIn, into: &thicknessIn)
    }
}

extension ScannedRoom.Opening {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.kind, into: &kind)
        c.read(.wallID, into: &wallID)
        c.read(.widthFt, into: &widthFt)
        c.read(.heightFt, into: &heightFt)
        c.read(.bottomFt, into: &bottomFt)
        c.read(.alongFt, into: &alongFt)
    }
}

extension AreaTakeoff {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.pieces, into: &pieces)
        c.read(.items, into: &items)
        c.read(.itemsPlaced, into: &itemsPlaced)
        c.read(.trim, into: &trim)
        c.read(.curbHeightIn, into: &curbHeightIn)
        c.read(.subtracted, into: &subtracted)
        c.read(.floor, into: &floor)
        c.read(.excludeTub, into: &excludeTub)
        c.read(.excludeSqft, into: &excludeSqft)
        c.read(.floorWidthFt, into: &floorWidthFt)
        c.read(.floorDepthFt, into: &floorDepthFt)
        c.read(.floorRect, into: &floorRect)
        c.read(.tileCeiling, into: &tileCeiling)
    }
}

extension AreaTakeoff.Piece {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var id = UUID(), wallID = UUID(), from = 0.0, to = 0.0, height = 0.0
        c.read(.id, into: &id)
        c.read(.wallID, into: &wallID)
        c.read(.fromFt, into: &from)
        c.read(.toFt, into: &to)
        c.read(.heightIn, into: &height)
        self.init(id: id, wallID: wallID, fromFt: from, toFt: to, heightIn: height)
        c.read(.face, into: &face)
    }
}

extension AreaTakeoff.Item {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.kind, into: &kind)
        c.read(.wallID, into: &wallID)
        c.read(.face, into: &face)
        c.read(.fromFt, into: &fromFt)
        c.read(.toFt, into: &toFt)
        c.read(.bottomIn, into: &bottomIn)
        c.read(.heightIn, into: &heightIn)
        c.read(.depthIn, into: &depthIn)
        c.read(.sizeIn, into: &sizeIn)
        c.read(.atStart, into: &atStart)
        c.read(.dividers, into: &dividers)
        c.read(.stone, into: &stone)
    }
}

extension AreaTakeoff.TrimChoice {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var key = ""
        c.read(.key, into: &key)
        self.init(key: key)
        c.read(.stone, into: &stone)
        c.read(.lengthFt, into: &lengthFt)
    }
}

extension AreaTakeoff.FloorRect {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.origin, into: &origin)
        c.read(.u, into: &u)
        c.read(.v, into: &v)
        c.read(.widthFt, into: &widthFt)
        c.read(.depthFt, into: &depthFt)
    }
}
