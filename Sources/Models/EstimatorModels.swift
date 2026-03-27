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
