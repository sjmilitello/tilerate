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

struct EstimateSection: Identifiable, Codable, Hashable, Equatable {
    var id = UUID()
    var roomName: String = ""
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
}

struct EstimateDocument: Codable, Equatable {
    var rooms: [EstimateRoom] = []
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
    }
}

extension EstimateDocument {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.rooms, into: &rooms)
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
