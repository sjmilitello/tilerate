import Foundation

struct Line: Identifiable {
    let id = UUID()
    let label: String
    var qty: Double = 0
    var rate: Double = 0
    let amount: Double
}

struct Summary {
    let lines: [Line]
    let total: Double
}

@inline(__always)
private func perSqft(from value: Double, unit: AdderUnit, baseRate: Double) -> Double {
    switch unit {
    case .perSqft: return value
    case .percent: return baseRate * (value / 100.0)
    }
}

/// How far a square or rectangle tile's size is from the standard tile, counted
/// in doublings (bigger) or halvings (smaller) of its area, part doublings in
/// proportion: 24×48 from 12×24 is 2, 3×12 is 3, 6×36 is about 0.42. Each one
/// adds its adder (see `sizeAdderAmount`). Other shapes have none. Returns nil when the
/// tile's width or length is missing, so the size adder can't be worked out.
func sizeDoublings(size: TileSize, lengthIn: Double?, widthIn: Double?, rates: Rates) -> Double? {
    guard size == .square || size == .rectangle else { return 0 }
    guard let L = lengthIn, let W = widthIn, L > 0, W > 0 else { return nil }
    guard rates.sizeBaseAreaSqIn > 0 else { return 0 }
    return abs(log2(L * W / rates.sizeBaseAreaSqIn))
}

/// The size adder for a square or rectangle tile, in the size adder's unit
/// ($/sq ft or % of the base rate): doublings × the doubling adder for tiles
/// bigger than the standard, halvings × the halving adder for smaller ones.
/// nil when the width or length is missing.
func sizeAdderAmount(size: TileSize, lengthIn: Double?, widthIn: Double?, rates: Rates) -> Double? {
    guard let steps = sizeDoublings(size: size, lengthIn: lengthIn, widthIn: widthIn, rates: rates) else { return nil }
    guard steps > 0, let L = lengthIn, let W = widthIn else { return 0 }
    let bigger = L * W > rates.sizeBaseAreaSqIn
    return steps * (bigger ? rates.sizeAdderPerDoubling : rates.sizeAdderPerHalving)
}

/// True when a square or rectangle tile has no width or length entered, so its
/// size adder cannot be charged.
func isMissingTileDimensions(size: TileSize?, lengthIn: Double?, widthIn: Double?) -> Bool {
    guard let size, size == .square || size == .rectangle else { return false }
    return (lengthIn ?? 0) <= 0 || (widthIn ?? 0) <= 0
}

private func sizeAdderPerSq(baseRate: Double, tile: TileChoice, rates: Rates) -> Double {
    // A multi-tile layout mixes sizes: no size adder, only its layout adder.
    if tile.layout == .multiTile, tile.tileSize != .mosaic { return 0 }
    switch tile.tileSize {
    case .square, .rectangle:
        let amount = sizeAdderAmount(size: tile.tileSize, lengthIn: tile.tileLengthIn,
                                     widthIn: tile.tileWidthIn, rates: rates) ?? 0
        return perSqft(from: amount, unit: rates.sizeAdderUnit, baseRate: baseRate)
    case .mosaic:
        // The Mosaic adder, plus the adder for its style when one is chosen.
        let style = tile.mosaicStyle.map { rates.mosaicStyleAdder[$0] ?? 0 } ?? 0
        return perSqft(from: (rates.sizeAdder[.mosaic] ?? 0) + style, unit: rates.sizeAdderUnit, baseRate: baseRate)
    default:
        return perSqft(from: rates.sizeAdder[tile.tileSize] ?? 0, unit: rates.sizeAdderUnit, baseRate: baseRate)
    }
}

private func addersPerSq(baseRate: Double, tile: TileChoice, rates: Rates) -> Double {
    let typePerSq = perSqft(from: rates.typeAdder[tile.tileType] ?? 0,
                            unit: rates.typeAdderUnit,
                            baseRate: baseRate)
    let sizePerSq = sizeAdderPerSq(baseRate: baseRate, tile: tile, rates: rates)
    // Mosaics come on sheets and have no layout of their own.
    let layoutPerSq = tile.tileSize == .mosaic ? 0 : perSqft(from: rates.layoutAdder[tile.layout] ?? 0,
                                                             unit: rates.layoutAdderUnit,
                                                             baseRate: baseRate)
    return typePerSq + sizePerSq + layoutPerSq
}

@inline(__always)
private func escalatorAdjPerSqft(rates: Rates) -> Double {
    rates.floorEscAdjPerSqft
}

/// One area's tile work: what every screen and the PDF show. With the new
/// engine switched on in Admin (roadmap Phase 2) the area is priced both ways;
/// the scheme's price is used only when it matches today's line for line,
/// otherwise today's price is used and the difference is noted in Admin.
func computeSummary(state: EstimatorState, rates: Rates) -> Summary {
    // A rule chosen in Admin → Area pricing that today's code can't do: only
    // the scheme can price the area.
    if rates.hasChosenRules(for: state.area, ceiling: state.measurements.ceilingSqft > 0) {
        return schemeSummary(state: state, scheme: PricingScheme(rates: rates))
    }
    let current = legacySummary(state: state, rates: rates)
    guard PricingEngine.useScheme else { return current }
    let scheme = schemeSummary(state: state, scheme: PricingScheme(rates: rates))
    return PricingEngine.check(current: current, scheme: scheme, area: state.area)
}

/// The side-by-side check between today's pricing and the scheme.
enum PricingEngine {
    static let key = "pricing.schemeEngine"
    private static let differencesKey = "pricing.schemeEngine.differences"
    private static let lastDifferenceKey = "pricing.schemeEngine.lastDifference"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var checkedThisRun = 0

    static var useScheme: Bool { UserDefaults.standard.bool(forKey: key) }

    /// True when two summaries have the same lines, labels and amounts.
    static func same(_ a: Summary, _ b: Summary) -> Bool {
        guard a.lines.count == b.lines.count, abs(a.total - b.total) < 0.005 else { return false }
        return zip(a.lines, b.lines).allSatisfy { $0.label == $1.label && abs($0.amount - $1.amount) < 0.005 }
    }

    static func check(current: Summary, scheme: Summary, area: Area?) -> Summary {
        lock.lock(); defer { lock.unlock() }
        checkedThisRun += 1
        if same(current, scheme) { return scheme }
        let d = UserDefaults.standard
        d.set(d.integer(forKey: differencesKey) + 1, forKey: differencesKey)
        d.set("\(area?.rawValue ?? "Area"): today \(currencyString(current.total)), new engine \(currencyString(scheme.total)) "
              + "(\(Date().formatted(date: .abbreviated, time: .shortened)))", forKey: lastDifferenceKey)
        return current
    }

    /// For Admin: areas compared since the app opened, and differences found.
    static var status: (checked: Int, differences: Int, last: String?) {
        lock.lock(); defer { lock.unlock() }
        let d = UserDefaults.standard
        return (checkedThisRun, d.integer(forKey: differencesKey), d.string(forKey: lastDifferenceKey))
    }

    static func clearDifferences() {
        UserDefaults.standard.removeObject(forKey: differencesKey)
        UserDefaults.standard.removeObject(forKey: lastDifferenceKey)
    }
}

/// Today's pricing, area by area in code: the reference the scheme engine is
/// checked against until it is retired.
func legacySummary(state: EstimatorState, rates: Rates) -> Summary {
    var lines: [Line] = []

    // A mosaic needs no layout; anything else does.
    guard let area = state.area,
          let type = state.tileType,
          let size = state.tileSize,
          size == .mosaic || state.layout != nil
    else {
        return Summary(lines: [], total: 0)
    }

    let mainTile = TileChoice(tileType: type, tileSize: size, layout: state.layout ?? .straightStacked,
                              tileWidthIn: state.tileWidthIn, tileLengthIn: state.tileLengthIn,
                              mosaicStyle: state.mosaicStyle, pieces: state.multiTilePieces)

    func currency(rates: Rates, value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    @discardableResult
    func appendComponent(labelPrefix: String,
                         sqft: Double,
                         baseRate: Double,
                         minCharge: Double?,
                         addersPerSq: Double) -> Double {
        guard sqft > 0 else { return 0 }

        let baseOnlyRaw = baseRate * sqft
        let addersRaw   = addersPerSq * sqft
        let perSq       = baseRate + addersPerSq
        let raw         = perSq * sqft

        if let min = minCharge, baseOnlyRaw < min {
            lines.append(Line(label: "\(labelPrefix) — Minimum Applied", amount: min))
            if addersPerSq != 0 {
                lines.append(Line(label: "\(labelPrefix) adders @ \(currency(rates: rates, value: addersPerSq))/sqft × \(Int(sqft.rounded()))",
                                  amount: addersRaw))
            }
            return min + addersRaw
        } else {
            if let min = minCharge, min > raw {
                lines.append(Line(label: "\(labelPrefix) — Minimum Applied", amount: min))
                return min
            } else {
                lines.append(Line(label: "\(labelPrefix) @ \(currency(rates: rates, value: perSq))/sqft × \(Int(sqft.rounded()))",
                                  amount: raw))
                return raw
            }
        }
    }

    /// Shower or tub-surround walls. With all walls the same, one area in the
    /// main tile. Otherwise each wall has its own tile: the base rate and the
    /// minimum apply to all the walls together, and each wall adds its own
    /// adders on top.
    func appendWalls(labelPrefix: String, allSameSqft: Double,
                     baseRate: Double, minCharge: Double?) -> Double {
        guard !state.walls.isEmpty else {
            return appendComponent(labelPrefix: labelPrefix,
                                   sqft: allSameSqft,
                                   baseRate: baseRate,
                                   minCharge: minCharge,
                                   addersPerSq: addersPerSq(baseRate: baseRate, tile: mainTile, rates: rates))
        }

        let walls = state.walls.filter { $0.sqft > 0 }
        guard !walls.isEmpty else { return 0 }
        let totalSqft = walls.reduce(0) { $0 + $1.sqft }
        let baseOnly = baseRate * totalSqft
        let minimum = minCharge ?? 0
        if baseOnly < minimum {
            lines.append(Line(label: "\(labelPrefix) — Minimum Applied", amount: minimum))
        } else {
            lines.append(Line(label: "\(labelPrefix) @ \(currency(rates: rates, value: baseRate))/sqft × \(Int(totalSqft.rounded()))",
                              amount: baseOnly))
        }
        var amount = max(baseOnly, minimum)

        for (i, wall) in state.walls.enumerated() where wall.sqft > 0 {
            let adders = addersPerSq(baseRate: baseRate, tile: wall.tile, rates: rates)
            guard adders != 0 else { continue }
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            lines.append(Line(label: "\(name) adders @ \(currency(rates: rates, value: adders))/sqft × \(Int(wall.sqft.rounded()))",
                              amount: adders * wall.sqft))
            amount += adders * wall.sqft
        }
        return amount
    }

    var running: Double = 0

    switch area {
    case .shower:
        running += appendWalls(labelPrefix: "Shower walls",
                               allSameSqft: state.measurements.showerWallsSqft,
                               baseRate: rates.base[.shower] ?? 0,
                               minCharge: rates.minimum[.shower])

        let baseShFloor = rates.showerFloorBase
        let addersShFloor = addersPerSq(baseRate: baseShFloor,
                                        tile: state.showerFloorTile ?? mainTile,
                                        rates: rates)
        running += appendComponent(labelPrefix: "Shower floor",
                                   sqft: state.measurements.showerFloorSqft,
                                   baseRate: baseShFloor,
                                   minCharge: rates.showerFloorMinimum,
                                   addersPerSq: addersShFloor)

    case .floor:
        let base = rates.base[.floor] ?? 0
        let adders = addersPerSq(baseRate: base, tile: mainTile, rates: rates)

        let sqft = state.measurements.sqft
        if sqft > 0 {
            let minCharge = rates.minimum[.floor] ?? 0
            let lower = max(0, rates.floorEscThresholdLower)      // e.g. 50
            let upper = max(lower, rates.floorEscThresholdUpper)  // e.g. 99
            let perSqEsc = escalatorAdjPerSqft(rates: rates)

            // The escalator charges only the square feet above the lower
            // threshold, on top of the minimum, and only inside the window:
            // 50 sf and under is the minimum, 51-99 is the minimum plus the
            // escalator for each foot over 50, and from 100 the base rate
            // takes over. Adding the escalator to every square foot is what
            // the March restructure did, and it overcharged the whole window.
            let sqftInt = Int(sqft.rounded(.down))
            let unitsOverLower = sqftInt <= upper ? max(0, sqftInt - lower) : 0
            let escalatorPart = Double(unitsOverLower) * perSqEsc

            let baseOnlyRaw = base * sqft
            let minPlusEsc = minCharge + escalatorPart

            if baseOnlyRaw >= minPlusEsc {
                lines.append(Line(label: "Floor @ \(currency(rates: rates, value: base))/sqft × \(Int(sqft.rounded()))",
                                  amount: baseOnlyRaw))
                running += baseOnlyRaw
            } else {
                if minCharge > 0 {
                    lines.append(Line(label: "Floor — Minimum Applied", amount: minCharge))
                }
                if escalatorPart > 0 {
                    lines.append(Line(label: "Floor escalator @ \(currency(rates: rates, value: perSqEsc))/sqft × \(unitsOverLower)",
                                      amount: escalatorPart))
                }
                running += minPlusEsc
            }

            // Tile type, size and layout adders go on top of whichever base won.
            if adders != 0 {
                let addersRaw = adders * sqft
                lines.append(Line(label: "Floor adders @ \(currency(rates: rates, value: adders))/sqft × \(Int(sqft.rounded()))",
                                  amount: addersRaw))
                running += addersRaw
            }
        }

    case .wall:
        let base = rates.base[.wall] ?? 0
        let adders = addersPerSq(baseRate: base, tile: mainTile, rates: rates)
        running += appendComponent(labelPrefix: "Wall",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.wall],
                                   addersPerSq: adders)

    case .tub:
        running += appendWalls(labelPrefix: "Tub surround",
                               allSameSqft: state.measurements.sqft,
                               baseRate: rates.base[.tub] ?? 0,
                               minCharge: rates.minimum[.tub])

    case .backsplash:
        let base = rates.base[.backsplash] ?? 0
        let adders = addersPerSq(baseRate: base, tile: mainTile, rates: rates)
        running += appendComponent(labelPrefix: "Backsplash",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.backsplash],
                                   addersPerSq: adders)

    case .fireplace:
        let base = rates.base[.fireplace] ?? 0
        let adders = addersPerSq(baseRate: base, tile: mainTile, rates: rates)
        running += appendComponent(labelPrefix: "Fireplace",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.fireplace],
                                   addersPerSq: adders)
    }

    if state.measurements.ceilingSqft > 0 {
        let baseC = rates.ceilingBase
        let addersC = addersPerSq(baseRate: baseC, tile: state.ceilingTile ?? mainTile, rates: rates)
        running += appendComponent(labelPrefix: "Ceiling",
                                   sqft: state.measurements.ceilingSqft,
                                   baseRate: baseC,
                                   minCharge: rates.ceilingMinimum,
                                   addersPerSq: addersC)
    }

    // Shelves, niches, footrests and benches don't go on a floor; the Features
    // step greys them out there, and anything left over is not charged.
    if area != .floor {
        // A niche's own tile: its adders at the area's wall rate.
        let wallRate = rates.base[area] ?? 0
        for line in featureLines(state.features, prices: FeaturePrices(rates: rates),
                                 money: { currency(rates: rates, value: $0) },
                                 tileAdders: { addersPerSq(baseRate: wallRate, tile: $0, rates: rates) }) {
            lines.append(line)
            running += line.amount
        }
    }

    // Bands and borders by the linear foot, inlays by the square foot, each
    // at its own rate. The tile chosen for each describes it; it doesn't
    // change the price.
    for item in state.decoratives where item.quantity > 0 {
        let rate = decorativeRate(item.kind, rates: rates)
        guard rate != 0 else { continue }
        let name = item.name.isEmpty ? item.kind.rawValue : "\(item.kind.rawValue): \(item.name)"
        let amount = item.quantity * rate
        lines.append(Line(label: "\(name) @ \(currency(rates: rates, value: rate))/\(item.kind.unit) × \(trimmedNumber(item.quantity))",
                          amount: amount))
        running += amount
    }

    return Summary(lines: lines, total: running)
}

/// The rate for a band or border (per linear foot) or an inlay (per sq ft).
func decorativeRate(_ kind: DecorativeKind, rates: Rates) -> Double {
    switch kind {
    case .band: rates.bandRatePerLinFt
    case .border: rates.borderRatePerLinFt
    case .inlay: rates.mosaicInlayRate
    }
}

/// 12 → "12", 7.5 → "7.5"
private func trimmedNumber(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(0...2)))
}

// MARK: - Whole estimate

struct SectionPrice {
    let room: EstimateRoom
    let section: EstimateSection
    let core: Summary
    /// The area's labor and material lines: what was added by hand, plus the
    /// radiant heat kit and its installation when the area has them.
    let laborItems: [AdditionItem]
    let materialItems: [AdditionItem]
    let radiant: RadiantHeatPrice?
    /// The wording templates it is described with (from the same rates).
    let wording: WordingTemplates
    var labor: Double { laborItems.reduce(0) { $0 + $1.amount } }
    var mats: Double { materialItems.reduce(0) { $0 + $1.amount } }
    var subtotal: Double { core.total + labor + mats }
    /// "Primary bath - Shower Tile installation consisting of …"
    var sentence: String { estimateSentence(room: room, section: section, wording: wording) }
}

/// One area's whole price: its tile work, its added lines and its radiant heat.
func sectionPrice(room: EstimateRoom, section sec: EstimateSection, rates: Rates) -> SectionPrice {
    var labor = sec.additionsLabor
    var materials = sec.additionsMaterials
    let radiant = radiantHeatPrice(for: sec, rates: rates)
    if let r = radiant {
        materials.append(AdditionItem(id: r.kitLineID, activity: r.system.name, qty: 1,
                                      rate: r.materials, taxable: r.system.taxable))
        if r.labor > 0 {
            labor.append(AdditionItem(id: r.laborLineID, activity: r.system.laborName, qty: 1, rate: r.labor))
        }
    }
    return SectionPrice(room: room, section: sec,
                        core: computeSummary(state: EstimatorState(section: sec), rates: rates),
                        laborItems: labor, materialItems: materials, radiant: radiant, wording: rates.wording)
}

/// Every number on the estimate. The Summary screen and the PDF both read
/// this, so they cannot disagree.
struct EstimateTotals {
    let sections: [SectionPrice]
    let subtotal: Double
    /// Material lines marked taxable; tax is charged on these only.
    let taxableBase: Double
    let taxPercent: Double
    /// Shipping is charged only when shipping is switched on and the estimate
    /// has material lines to ship.
    let shipping: Double

    var tax: Double { taxableBase * (taxPercent / 100.0) }
    var grandTotal: Double { subtotal + shipping + tax }
}

func computeTotals(document: EstimateDocument,
                   rates: Rates,
                   shippingEnabled: Bool,
                   shipping: Double,
                   taxPercent: Double) -> EstimateTotals {
    var sections: [SectionPrice] = []
    for room in document.rooms {
        for sec in room.sections {
            sections.append(sectionPrice(room: room, section: sec, rates: rates))
        }
    }

    let materials = sections.flatMap(\.materialItems)
    let taxableBase = materials.filter { $0.taxable }.reduce(0) { $0 + $1.amount }

    return EstimateTotals(
        sections: sections,
        subtotal: sections.reduce(0) { $0 + $1.subtotal },
        taxableBase: taxableBase,
        taxPercent: taxPercent,
        shipping: (shippingEnabled && !materials.isEmpty) ? shipping : 0
    )
}

// MARK: - Electric radiant heat

/// What radiant heat adds to an area, part by part.
struct RadiantHeatPrice {
    struct Part {
        let name: String
        /// e.g. "8 × $16.59" or "1 × 200 LF (120V)"
        let detail: String
        let cost: Double
    }
    let system: HeatingSystem
    let floorSqft: Double
    let heatedSqft: Double
    let parts: [Part]
    /// The parts at cost.
    let cost: Double
    /// The parts with the markup: the kit's line on the estimate.
    let materials: Double
    /// Installation: floor (or heated) sq ft × the rate, or the minimum.
    let labor: Double
    let laborMinimumApplied: Bool
    /// Ids for the kit and installation lines, the same every time an area is
    /// priced so the screens don't redraw them as new rows.
    let kitLineID: UUID
    let laborLineID: UUID
}

/// The floor radiant heat goes under: a floor area's square feet, or a
/// shower's floor. Other areas can't have it.
func radiantFloorSqft(area: Area?, measurements m: Measurements) -> Double? {
    switch area {
    case .floor: m.sqft
    case .shower: m.showerFloorSqft
    default: nil
    }
}

func radiantHeatPrice(for sec: EstimateSection, rates: Rates) -> RadiantHeatPrice? {
    guard let choice = sec.radiantHeat,
          let floor = radiantFloorSqft(area: sec.area, measurements: sec.measurements), floor > 0,
          let system = rates.heatingSystems.first(where: { $0.id == choice.systemID }) ?? rates.heatingSystems.first
    else { return nil }
    let heated = choice.heatedSqft ?? floor
    guard heated > 0 else { return nil }

    func money(_ v: Double) -> String {
        v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
    func trim(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }

    var parts: [RadiantHeatPrice.Part] = []
    var sizedCount = 0

    // Sized parts first: "one per sized item" parts count what they chose.
    for part in system.parts where part.rule == .sizedToHeatedArea {
        let need = heated * part.amountPerHeatedSqft
        // The group for this size of area: the smallest limit it fits under.
        let groups = part.sizeGroups.sorted { ($0.maxHeatedSqft ?? .infinity) < ($1.maxHeatedSqft ?? .infinity) }
        guard need > 0,
              let group = groups.first(where: { heated <= ($0.maxHeatedSqft ?? .infinity) }),
              let largest = group.sizes.map(\.amount).max(), largest > 0
        else { continue }
        // Split evenly across the fewest pieces that cover it.
        let count = need <= largest ? 1 : Int((need / largest).rounded(.up))
        let each = need / Double(count)
        guard let size = group.sizes.sorted(by: { $0.amount < $1.amount })
                .first(where: { $0.amount >= each - 1e-9 }) else { continue }
        sizedCount += count
        let groupName = group.name.isEmpty ? "" : " (\(group.name))"
        parts.append(.init(name: part.name,
                           detail: "\(count) × \(trim(size.amount)) \(part.unitLabel)\(groupName)",
                           cost: Double(count) * size.cost))
    }
    for part in system.parts where part.rule != .sizedToHeatedArea {
        let quantity: Double
        switch part.rule {
        case .coversFloor:
            guard part.coverageSqft > 0 else { continue }
            quantity = (floor / part.coverageSqft - 1e-9).rounded(.up)
        case .onePerSizedItem:
            quantity = Double(max(1, sizedCount))
        case .fixedPerJob:
            quantity = part.quantity
        case .sizedToHeatedArea:
            continue
        }
        guard quantity > 0 else { continue }
        parts.append(.init(name: part.name, detail: "\(trim(quantity)) × \(money(part.unitCost))",
                           cost: quantity * part.unitCost))
    }

    let cost = parts.reduce(0) { $0 + $1.cost }
    let materials = (cost * (1 + system.markupPercent / 100) * 100).rounded() / 100
    let laborByArea = (system.laborOnHeatedAreaOnly ? heated : floor) * system.laborPerSqft
    return RadiantHeatPrice(
        system: system, floorSqft: floor, heatedSqft: heated, parts: parts,
        cost: cost, materials: materials,
        labor: max(laborByArea, system.laborMinimum),
        laborMinimumApplied: system.laborMinimum > laborByArea,
        kitLineID: lineID(sec.id, salt: 1), laborLineID: lineID(sec.id, salt: 2)
    )
}

/// A UUID derived from a section's id, so a generated line keeps its id.
private func lineID(_ id: UUID, salt: UInt8) -> UUID {
    var bytes = id.uuid
    bytes.15 ^= salt
    return UUID(uuid: bytes)
}
