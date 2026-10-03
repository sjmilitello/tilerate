import Foundation

// Electric radiant heat, set up by the owner in Admin rather than built in, so
// any brand and any stocked sizes can be priced. A system is the kit sold for
// one area: its parts (each with a rule for how many are needed), a markup on
// the parts' cost, and an installation charge per floor square foot.

/// How many of a part an area needs.
enum HeatingPartRule: String, Codable, CaseIterable, Identifiable {
    /// Floor sq ft ÷ coverage per piece, rounded up (mat sheets).
    case coversFloor = "Covers the floor"
    /// Heated sq ft × amount per sq ft, rounded up to the next stocked size,
    /// split across several pieces when one isn't long enough (heating wire).
    case sizedToHeatedArea = "Sized to the heated area"
    /// One for each piece chosen from a size list (a thermostat per wire).
    case onePerSizedItem = "One per sized item"
    /// A set number per job.
    case fixedPerJob = "Fixed per job"
    var id: String { rawValue }
}

/// One stocked size of a sized part: its amount (e.g. 200 LF) and its cost.
struct HeatingSize: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var amount: Double = 0
    var cost: Double = 0
}

/// A list of stocked sizes, used for heated areas up to `maxHeatedSqft`
/// (nil: any size of area), e.g. 120V wire up to 100 sq ft.
struct HeatingSizeGroup: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String = ""
    var maxHeatedSqft: Double? = nil
    var sizes: [HeatingSize] = []
}

struct HeatingPart: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String = ""
    var rule: HeatingPartRule = .fixedPerJob
    /// Cost of one piece, for every rule but `sizedToHeatedArea`.
    var unitCost: Double = 0
    /// `coversFloor`: square feet one piece covers.
    var coverageSqft: Double = 8
    /// `fixedPerJob`: how many per job.
    var quantity: Double = 1
    /// `sizedToHeatedArea`: amount needed per heated sq ft, e.g. 3.95 LF.
    var amountPerHeatedSqft: Double = 1
    /// `sizedToHeatedArea`: what the sizes are measured in, e.g. "LF".
    var unitLabel: String = "LF"
    /// `sizedToHeatedArea`: the stocked sizes, by area range.
    var sizeGroups: [HeatingSizeGroup] = []
}

struct HeatingSystem: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    /// The kit's line on the estimate.
    var name: String = "Electric Radiant Heat Kit"
    /// The installation line on the estimate.
    var laborName: String = "Radiant Heat Installation"
    /// Markup on cost: 60 means cost × 1.6.
    var markupPercent: Double = 60
    var taxable: Bool = true
    var laborPerSqft: Double = 0
    var laborMinimum: Double = 0
    /// Installation per square foot of the whole floor (the owner's way) or
    /// of the heated area only.
    var laborOnHeatedAreaOnly: Bool = false
    var parts: [HeatingPart] = []
}

/// Radiant heat chosen for a floor or shower floor.
struct RadiantHeatChoice: Codable, Equatable, Hashable {
    var systemID: UUID? = nil
    /// The area actually heated; nil means the whole floor.
    var heatedSqft: Double? = nil
}

// MARK: - The owner's system

extension HeatingSystem {
    /// The owner's Strata Heat kit at their prices (October 2026), used until
    /// a saved list of systems exists. Before an App Store release this
    /// should become an empty list, so other users enter their own.
    static let ownersStrataHeat: HeatingSystem = {
        func sizes(_ list: [(Double, Double)]) -> [HeatingSize] {
            list.map { HeatingSize(amount: $0.0, cost: $0.1) }
        }
        let wire120 = HeatingSizeGroup(name: "120V", maxHeatedSqft: 100, sizes: sizes([
            (50, 149.67), (67, 180.55), (84, 194.30), (100, 208.66), (133, 253.53), (166, 274.94),
            (200, 292.99), (233, 332.56), (266, 371.25), (299, 414.24), (332, 441.48), (365, 494.69),
            (398, 527.33),
        ]))
        let wire240 = HeatingSizeGroup(name: "240V", maxHeatedSqft: nil, sizes: sizes([
            (83, 191.97), (100, 208.66), (133, 236.22), (166, 264.73), (200, 294.91), (233, 321.69),
            (266, 353.08), (299, 371.00), (332, 411.93), (415, 458.42), (498, 530.13), (581, 581.53),
            (664, 639.25), (747, 699.40), (830, 777.12),
        ]))
        return HeatingSystem(
            id: UUID(uuidString: "5A1E7B3C-0D2F-4C8E-9B6A-1F3D5E7A9C01")!,
            name: "Strata Heat Electric Radiant Heat Kit W/ LCD Smart WiFi Thermostat",
            laborName: "Radiant Heat Installation",
            markupPercent: 60,
            taxable: true,
            laborPerSqft: 8,
            laborMinimum: 500,
            parts: [
                HeatingPart(name: "Floor mat sheet", rule: .coversFloor, unitCost: 16.59, coverageSqft: 8),
                HeatingPart(name: "Heating wire", rule: .sizedToHeatedArea, amountPerHeatedSqft: 3.95,
                            unitLabel: "LF", sizeGroups: [wire120, wire240]),
                HeatingPart(name: "Smart LCD WiFi thermostat", rule: .onePerSizedItem, unitCost: 226.68),
            ]
        )
    }()
}

// MARK: - Reading what was saved (see the note in EstimatorModels.swift)

extension HeatingSize {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.amount, into: &amount)
        c.read(.cost, into: &cost)
    }
}

extension HeatingSizeGroup {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.maxHeatedSqft, into: &maxHeatedSqft)
        c.read(.sizes, into: &sizes)
    }
}

extension HeatingPart {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.rule, into: &rule)
        c.read(.unitCost, into: &unitCost)
        c.read(.coverageSqft, into: &coverageSqft)
        c.read(.quantity, into: &quantity)
        c.read(.amountPerHeatedSqft, into: &amountPerHeatedSqft)
        c.read(.unitLabel, into: &unitLabel)
        c.read(.sizeGroups, into: &sizeGroups)
    }
}

extension HeatingSystem {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.id, into: &id)
        c.read(.name, into: &name)
        c.read(.laborName, into: &laborName)
        c.read(.markupPercent, into: &markupPercent)
        c.read(.taxable, into: &taxable)
        c.read(.laborPerSqft, into: &laborPerSqft)
        c.read(.laborMinimum, into: &laborMinimum)
        c.read(.laborOnHeatedAreaOnly, into: &laborOnHeatedAreaOnly)
        c.read(.parts, into: &parts)
    }
}

extension RadiantHeatChoice {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.read(.systemID, into: &systemID)
        c.read(.heatedSqft, into: &heatedSqft)
    }
}
