import Foundation

struct AdditionItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var activity: String = ""
    var qty: Double = 1
    var rate: Double = 0
    var taxable: Bool = false
    var amount: Double { qty * rate }
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
    // size adder. Every time the tile's area doubles, or halves, from there
    // adds `sizeAdderPerDoubling` — part doublings count in proportion. The
    // owner's figure (2026-09-27) is $2.50, so 24×48 (two doublings) adds $5
    // and 3×12 (three halvings) adds $7.50.
    var sizeBaseAreaSqIn: Double = 288
    var sizeAdderPerDoubling: Double = 2.5

    var typeAdderUnit: AdderUnit = .perSqft
    var sizeAdderUnit: AdderUnit = .perSqft
    var layoutAdderUnit: AdderUnit = .perSqft

    var mosaicInlayRate: Double = 0

    var unitShelf: Double = 600
    var unitNiche: Double = 600
    var unitFootrest: Double = 200
    var unitBench: Double = 200

    var floorEscThresholdLower: Int = 50
    var floorEscThresholdUpper: Int = 99
    var floorEscAdjPerSqft: Double = 0
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
        c.read(.typeAdderUnit, into: &typeAdderUnit)
        c.read(.sizeAdderUnit, into: &sizeAdderUnit)
        c.read(.layoutAdderUnit, into: &layoutAdderUnit)
        c.read(.mosaicInlayRate, into: &mosaicInlayRate)
        c.read(.unitShelf, into: &unitShelf)
        c.read(.unitNiche, into: &unitNiche)
        c.read(.unitFootrest, into: &unitFootrest)
        c.read(.unitBench, into: &unitBench)
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
    var mosaicSqft: Double = 0
}

struct Features: Codable, Equatable, Hashable {
    var mosaicBand: Bool = false
    var shelves: Int = 0
    var niches: Int = 0
    var footrests: Int = 0
    var benches: Int = 0
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

    /// nil means the shower floor / ceiling uses the main tile.
    var showerFloorTile: TileChoice? = nil
    var ceilingTile: TileChoice? = nil
    /// Shower and tub surround walls. Empty means all walls are the same: one
    /// area (`showerWallsSqft` for a shower, `sqft` for a tub surround) in the
    /// main tile. Otherwise each wall is priced with its own tile.
    var walls: [TiledWall] = []

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
        showerFloorTile = sec.showerFloorTile
        ceilingTile = sec.ceilingTile
        walls = sec.walls
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

struct EstimateSection: Identifiable, Codable, Hashable, Equatable {
    var id = UUID()
    var roomName: String = ""
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
    /// nil means the shower floor / ceiling uses the main tile.
    var showerFloorTile: TileChoice? = nil
    var ceilingTile: TileChoice? = nil
    /// Shower and tub surround walls. Empty means all walls are the same: one
    /// area (`showerWallsSqft` for a shower, `sqft` for a tub surround) in the
    /// main tile. Otherwise each wall is priced with its own tile.
    var walls: [TiledWall] = []
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
        c.read(.showerFloorTile, into: &showerFloorTile)
        c.read(.ceilingTile, into: &ceilingTile)
        c.read(.walls, into: &walls)
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
        c.read(.showerFloorTile, into: &showerFloorTile)
        c.read(.ceilingTile, into: &ceilingTile)
        c.read(.walls, into: &walls)
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
    }
}
