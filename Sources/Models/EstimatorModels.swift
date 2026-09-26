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
        .ceramic: 0, .porcelain: 0, .glass: 0, .marble: 0, .limestone: 0, .slate: 0
    ]
    var sizeAdder: [TileSize: Double] = [
        .mosaic: 0, .starCross: 0, .arabesque: 0, .hexagon: 0, .rectangle: 0, .square: 0
    ]
    var layoutAdder: [Layout: Double] = [
        .straightStacked: 0, .runningBond: 0, .diagonal: 0, .herringbone: 0, .multiTile: 0
    ]

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

    var rectSquareOverLengthIn: Double = 0
    var rectSquareOverWidthIn: Double = 0
    var rectSquareOverAdder: Double = 0
    var rectSquareUnderLengthIn: Double = 0
    var rectSquareUnderWidthIn: Double = 0
    var rectSquareUnderAdder: Double = 0

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

        func read<T: Decodable>(_ key: CodingKeys, into value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        // A saved table replaces the default entry by entry, so a case added
        // to Area, TileType, TileSize or Layout starts at its default.
        func merge<K, V: Decodable>(_ key: CodingKeys, into table: inout [K: V]) where K: Decodable & Hashable {
            if let v = try? c.decodeIfPresent([K: V].self, forKey: key) {
                table.merge(v) { _, saved in saved }
            }
        }

        merge(.base, into: &base)
        merge(.minimum, into: &minimum)
        read(.ceilingBase, into: &ceilingBase)
        read(.ceilingMinimum, into: &ceilingMinimum)
        read(.showerFloorBase, into: &showerFloorBase)
        read(.showerFloorMinimum, into: &showerFloorMinimum)
        merge(.typeAdder, into: &typeAdder)
        merge(.sizeAdder, into: &sizeAdder)
        merge(.layoutAdder, into: &layoutAdder)
        merge(.sizeSpecs, into: &sizeSpecs)
        read(.rectSquareOverLengthIn, into: &rectSquareOverLengthIn)
        read(.rectSquareOverWidthIn, into: &rectSquareOverWidthIn)
        read(.rectSquareOverAdder, into: &rectSquareOverAdder)
        read(.rectSquareUnderLengthIn, into: &rectSquareUnderLengthIn)
        read(.rectSquareUnderWidthIn, into: &rectSquareUnderWidthIn)
        read(.rectSquareUnderAdder, into: &rectSquareUnderAdder)
        read(.typeAdderUnit, into: &typeAdderUnit)
        read(.sizeAdderUnit, into: &sizeAdderUnit)
        read(.layoutAdderUnit, into: &layoutAdderUnit)
        read(.mosaicInlayRate, into: &mosaicInlayRate)
        read(.unitShelf, into: &unitShelf)
        read(.unitNiche, into: &unitNiche)
        read(.unitFootrest, into: &unitFootrest)
        read(.unitBench, into: &unitBench)
        read(.floorEscThresholdLower, into: &floorEscThresholdLower)
        read(.floorEscThresholdUpper, into: &floorEscThresholdUpper)
        read(.floorEscAdjPerSqft, into: &floorEscAdjPerSqft)
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

    var additionsLabor: [AdditionItem] = []
    var additionsMaterials: [AdditionItem] = []
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
