import Foundation

// Roadmap Phase 2: the tile work in each area priced from settings — a
// pricing scheme — instead of from code written area by area. Today the
// scheme is built from the Admin rates (`PricingScheme(rates:)`), and it must
// price every area exactly as `legacySummary` in Pricing.swift does, line for
// line; PricingGoldenTests checks 1,380 areas. Phase 5 lets a user build a
// scheme of their own. Radiant heat and the price list were already settings
// and are priced as before (`sectionPrice`).

// MARK: - The scheme

struct PricingScheme: Equatable {
    var areas: [Area: AreaPricing]
    /// A tiled ceiling, in whichever area has one.
    var ceiling: SurfacePricing
    var adders: TileAdders
    var features: FeaturePrices
    /// Bands and borders per linear foot, inlays per square foot.
    var decoratives: [DecorativeKind: Double]
}

/// How one kind of area is priced: its surfaces, in the order they appear on
/// the estimate, and whether shelves, niches, footrests and benches are charged.
struct AreaPricing: Equatable {
    var surfaces: [SurfacePricing]
    var chargesFeatures: Bool
}

/// Which square feet of an area a surface is priced on.
enum SurfaceMeasure: Equatable {
    case area, showerWalls, showerFloor, ceiling
}

/// Which tile a surface's adders come from: the area's own, or the separate
/// shower floor or ceiling tile when one is chosen.
enum SurfaceTile: Equatable {
    case main, showerFloor, ceiling
}

struct SurfacePricing: Equatable {
    /// How its lines are labelled on the estimate, e.g. "Shower floor".
    var label: String
    var measure: SurfaceMeasure
    var tile: SurfaceTile
    var rule: SurfaceRule
    /// Walls that can each have their own tile (`EstimateSection.walls`):
    /// the rate and the minimum apply to all of them together, and each wall
    /// adds its own adders.
    var wallsCanDiffer: Bool = false
}

enum SurfaceRule: Equatable {
    /// Rate × square feet, with the tile adders. When the rate alone comes to
    /// less than the minimum, the minimum is charged and the adders go on top.
    case rate(perSqft: Double, minimum: Double?)
    /// The owner's floor rule: the greater of rate × square feet and the
    /// minimum plus the escalator for each whole square foot over the window's
    /// start, counted only up to its end. The adders always go on top.
    case escalator(perSqft: Double, minimum: Double, window: EscalatorWindow)
}

struct EscalatorWindow: Equatable {
    var from: Int
    var through: Int
    var perSqft: Double
}

/// The extras per square foot for the tile chosen, each in $/sq ft or as a
/// percentage of the surface's rate.
struct TileAdders: Equatable {
    var material: [TileType: Double]
    var materialUnit: AdderUnit
    /// Flat adders for hexagon, arabesque, star/cross and mosaic.
    var shape: [TileSize: Double]
    var shapeUnit: AdderUnit
    var mosaicStyle: [MosaicStyle: Double]
    var layout: [Layout: Double]
    var layoutUnit: AdderUnit
    /// Squares and rectangles: the size that pays nothing, and the adder for
    /// each doubling (bigger) or halving (smaller) of its area.
    var standardTileSqIn: Double
    var perDoubling: Double
    var perHalving: Double
}

struct FeaturePrices: Equatable {
    var shelf: Double
    var niche: Double
    var footrest: Double
    var bench: Double
    var seat: Double = 0
    var window: Double = 0
    /// Benches, niches and windows placed on a room scan (`SizedFeature`).
    var benchPerLinFt: Double = 0
    var nicheStone = StoneRate()
    var windowStone = StoneRate()
}

extension FeaturePrices {
    init(rates r: Rates) {
        self.init(shelf: r.unitShelf, niche: r.unitNiche, footrest: r.unitFootrest, bench: r.unitBench,
                  seat: r.unitSeat, window: r.unitWindow, benchPerLinFt: r.benchPerLinFt,
                  nicheStone: r.stoneRate(.niche), windowStone: r.stoneRate(.window))
    }
}

/// The feature lines both pricing engines give: shelves, niches, footrests,
/// benches, seats and windows at their per-unit price, except that each
/// bench, niche or window placed on a scan (`Features.sized`) is the higher
/// of that price (its minimum) and its size: a bench's length at
/// `benchPerLinFt`, a stone niche's or window's stone at its stone rate.
func featureLines(_ f: Features, prices p: FeaturePrices, money: (Double) -> String) -> [Line] {
    var lines: [Line] = []
    func feet(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
    let kinds: [(String, Int, Double, SizedFeature.Kind?)] = [
        ("Shelves", f.shelves, p.shelf, nil), ("Niches", f.niches, p.niche, .niche),
        ("Footrests", f.footrests, p.footrest, nil), ("Benches", f.benches, p.bench, .bench),
        ("Seats", f.seats, p.seat, nil), ("Windows", f.windows, p.window, .window),
    ]
    for (label, count, unit, kind) in kinds {
        let sized = kind.map { k in f.sized.filter { $0.kind == k } } ?? []
        let rest = max(0, count - sized.count)
        if rest > 0, unit != 0 {
            lines.append(Line(label: "\(label) (\(rest)× @ \(money(unit)))", amount: Double(rest) * unit))
        }
        for item in sized.prefix(count) {
            let stone: StoneRate? = item.kind == .niche ? p.nicheStone : item.kind == .window ? p.windowStone : nil
            let linear: Double
            let how: String
            if item.kind == .bench {
                linear = item.linFt * p.benchPerLinFt
                how = "@ \(money(p.benchPerLinFt))/lin ft × \(feet(item.linFt))"
            } else if item.stone, let stone {
                linear = stone.amount(linFt: item.linFt)
                how = stone.usesSqft ? "@ \(money(stone.perSqft))/sq ft × \(feet(stone.sqft(linFt: item.linFt)))"
                                     : "@ \(money(stone.perLinFt))/lin ft × \(feet(item.linFt))"
            } else {
                linear = 0
                how = ""
            }
            let amount = max(unit, linear)
            guard amount != 0 else { continue }
            let name = item.label.isEmpty ? String(label.dropLast(label.hasSuffix("ches") ? 2 : 1)) : item.label
            lines.append(Line(label: linear > unit ? "\(name) \(how)" : "\(name) (minimum \(money(unit)))", amount: amount))
        }
    }
    return lines
}

// MARK: - Surfaces whose rule can be chosen (roadmap Phase 5)

/// Every surface an area can be charged for, each with its own rule.
enum PricedSurface: String, Codable, CaseIterable, Identifiable {
    case floor, wall, tubSurround, showerWalls, showerFloor, backsplash, fireplace, ceiling
    var id: String { rawValue }

    var title: String {
        switch self {
        case .floor: "Floor"
        case .wall: "Wall"
        case .tubSurround: "Tub surround"
        case .showerWalls: "Shower walls"
        case .showerFloor: "Shower floor"
        case .backsplash: "Backsplash"
        case .fireplace: "Fireplace"
        case .ceiling: "Ceiling (any area)"
        }
    }

    /// The area whose rate fields hold it, when it has one.
    var area: Area? {
        switch self {
        case .floor: .floor
        case .wall: .wall
        case .tubSurround: .tub
        case .showerWalls: .shower
        case .backsplash: .backsplash
        case .fireplace: .fireplace
        case .showerFloor, .ceiling: nil
        }
    }
}

extension SurfaceRule: Codable {
    private enum CodingKeys: String, CodingKey { case kind, perSqft, minimum, from, through, escalatorPerSqft }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(String.self, forKey: .kind)) ?? "rate"
        let perSqft = (try? c.decode(Double.self, forKey: .perSqft)) ?? 0
        let minimum: Double? = (try? c.decodeIfPresent(Double.self, forKey: .minimum)) ?? nil
        if kind == "escalator" {
            self = .escalator(perSqft: perSqft, minimum: minimum ?? 0, window: EscalatorWindow(
                from: (try? c.decode(Int.self, forKey: .from)) ?? 0,
                through: (try? c.decode(Int.self, forKey: .through)) ?? 0,
                perSqft: (try? c.decode(Double.self, forKey: .escalatorPerSqft)) ?? 0))
        } else {
            self = .rate(perSqft: perSqft, minimum: minimum)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .rate(perSqft, minimum):
            try c.encode("rate", forKey: .kind)
            try c.encode(perSqft, forKey: .perSqft)
            try c.encodeIfPresent(minimum, forKey: .minimum)
        case let .escalator(perSqft, minimum, window):
            try c.encode("escalator", forKey: .kind)
            try c.encode(perSqft, forKey: .perSqft)
            try c.encode(minimum, forKey: .minimum)
            try c.encode(window.from, forKey: .from)
            try c.encode(window.through, forKey: .through)
            try c.encode(window.perSqft, forKey: .escalatorPerSqft)
        }
    }

    var isEscalator: Bool {
        if case .escalator = self { true } else { false }
    }
}

extension Rates {
    /// The rule a surface is priced by: one chosen in Admin, or the usual one
    /// from the rate fields (an escalator window for floors, a rate with a
    /// minimum for everything else).
    func rule(for surface: PricedSurface) -> SurfaceRule {
        if let chosen = surfaceRules[surface] { return chosen }
        return standardRule(for: surface)
    }

    private func standardRule(for surface: PricedSurface) -> SurfaceRule {
        switch surface {
        case .floor:
            let lower = max(0, floorEscThresholdLower)
            return .escalator(perSqft: base[.floor] ?? 0, minimum: minimum[.floor] ?? 0,
                              window: EscalatorWindow(from: lower, through: max(lower, floorEscThresholdUpper),
                                                      perSqft: floorEscAdjPerSqft))
        case .showerFloor: return .rate(perSqft: showerFloorBase, minimum: showerFloorMinimum)
        case .ceiling: return .rate(perSqft: ceilingBase, minimum: ceilingMinimum)
        default:
            let a = surface.area!
            return .rate(perSqft: base[a] ?? 0, minimum: minimum[a])
        }
    }

    /// Sets a surface's rule. The usual kind of rule goes back into the rate
    /// fields, so prices and the Phase 2 check see it exactly as before; only
    /// a different kind is kept in `surfaceRules`.
    mutating func setRule(_ rule: SurfaceRule, for surface: PricedSurface) {
        let usual = standardRule(for: surface).isEscalator == rule.isEscalator
        guard usual else {
            surfaceRules[surface] = rule
            return
        }
        surfaceRules[surface] = nil
        switch (surface, rule) {
        case let (.floor, .escalator(rate, min, window)):
            base[.floor] = rate
            minimum[.floor] = min
            floorEscThresholdLower = window.from
            floorEscThresholdUpper = window.through
            floorEscAdjPerSqft = window.perSqft
        case let (.showerFloor, .rate(rate, min)):
            showerFloorBase = rate
            showerFloorMinimum = min ?? 0
        case let (.ceiling, .rate(rate, min)):
            ceilingBase = rate
            ceilingMinimum = min ?? 0
        case let (_, .rate(rate, min)):
            if let a = surface.area {
                base[a] = rate
                minimum[a] = min ?? 0
            }
        default:
            break
        }
    }

    /// True when an area is priced by a rule today's code-written pricing
    /// can't do, so only the scheme can price it.
    func hasChosenRules(for area: Area?, ceiling: Bool) -> Bool {
        guard !surfaceRules.isEmpty else { return false }
        let mine: [PricedSurface]
        switch area {
        case .floor: mine = [.floor]
        case .wall: mine = [.wall]
        case .tub: mine = [.tubSurround]
        case .shower: mine = [.showerWalls, .showerFloor]
        case .backsplash: mine = [.backsplash]
        case .fireplace: mine = [.fireplace]
        case nil: mine = []
        }
        return (mine + (ceiling ? [.ceiling] : [])).contains { surfaceRules[$0] != nil }
    }
}

// MARK: - Prices a rule gives, for the editor's examples and warnings

/// What a rule charges for a surface of this size, before adders.
func basePrice(_ rule: SurfaceRule, sqft: Double) -> Double {
    guard sqft > 0 else { return 0 }
    switch rule {
    case let .rate(rate, minimum):
        return max(rate * sqft, minimum ?? 0)
    case let .escalator(rate, minimum, window):
        let whole = Int(sqft.rounded(.down))
        let over = whole <= window.through ? max(0, whole - window.from) : 0
        return max(rate * sqft, minimum + Double(over) * window.perSqft)
    }
}

/// The first whole square foot where one more square foot costs less, if any.
func firstPriceDrop(_ rule: SurfaceRule) -> (sqft: Int, price: Double, next: Double)? {
    var top = 300
    if case let .escalator(_, _, window) = rule { top = min(6000, max(top, window.through * 3)) }
    var last = basePrice(rule, sqft: 1)
    for n in 2...top {
        let p = basePrice(rule, sqft: Double(n))
        if p < last - 0.005 { return (n - 1, last, p) }
        last = p
    }
    return nil
}

/// The escalator that takes the minimum up to the square-foot price with no
/// jump and no drop: (rate × first sq ft after the window − minimum) ÷ the
/// window's width, rounded down to the cent. nil when there is no gap to
/// bridge (the rate already beats the minimum at the window's start) or the
/// rate never reaches the minimum.
func suggestedEscalator(perSqft rate: Double, minimum: Double, from: Int, through: Int) -> Double? {
    let after = Double(through + 1)
    let width = after - Double(from)
    guard width > 0, rate * after > minimum, rate * Double(from) < minimum else { return nil }
    return ((rate * after - minimum) / width * 100).rounded(.down) / 100
}

// MARK: - The owner's pricing, as a scheme

extension PricingScheme {
    /// The pricing the Admin rates describe today.
    init(rates r: Rates) {
        func one(_ label: String, _ s: PricedSurface) -> AreaPricing {
            AreaPricing(surfaces: [SurfacePricing(label: label, measure: .area, tile: .main, rule: r.rule(for: s))],
                        chargesFeatures: true)
        }
        areas = [
            .floor: AreaPricing(
                surfaces: [SurfacePricing(label: "Floor", measure: .area, tile: .main, rule: r.rule(for: .floor))],
                chargesFeatures: false),
            .wall: one("Wall", .wall),
            .tub: AreaPricing(
                surfaces: [SurfacePricing(label: "Tub surround", measure: .area, tile: .main,
                                          rule: r.rule(for: .tubSurround), wallsCanDiffer: true)],
                chargesFeatures: true),
            .shower: AreaPricing(
                surfaces: [SurfacePricing(label: "Shower walls", measure: .showerWalls, tile: .main,
                                          rule: r.rule(for: .showerWalls), wallsCanDiffer: true),
                           SurfacePricing(label: "Shower floor", measure: .showerFloor, tile: .showerFloor,
                                          rule: r.rule(for: .showerFloor))],
                chargesFeatures: true),
            .backsplash: one("Backsplash", .backsplash),
            .fireplace: one("Fireplace", .fireplace),
        ]
        ceiling = SurfacePricing(label: "Ceiling", measure: .ceiling, tile: .ceiling, rule: r.rule(for: .ceiling))
        adders = TileAdders(material: r.typeAdder, materialUnit: r.typeAdderUnit,
                            shape: r.sizeAdder, shapeUnit: r.sizeAdderUnit,
                            mosaicStyle: r.mosaicStyleAdder,
                            layout: r.layoutAdder, layoutUnit: r.layoutAdderUnit,
                            standardTileSqIn: r.sizeBaseAreaSqIn,
                            perDoubling: r.sizeAdderPerDoubling, perHalving: r.sizeAdderPerHalving)
        features = FeaturePrices(rates: r)
        decoratives = [.band: r.bandRatePerLinFt, .border: r.borderRatePerLinFt, .inlay: r.mosaicInlayRate]
    }
}

// MARK: - Pricing an area from a scheme

extension TileAdders {
    private func perSqft(_ value: Double, _ unit: AdderUnit, rate: Double) -> Double {
        unit == .percent ? rate * (value / 100) : value
    }

    /// The adders for a tile, per square foot, on a surface charged `rate`.
    func perSqft(for tile: TileChoice, rate: Double) -> Double {
        let material = perSqft(self.material[tile.tileType] ?? 0, materialUnit, rate: rate)
        let shape: Double
        if tile.layout == .multiTile, tile.tileSize != .mosaic {
            shape = 0                      // mixed sizes: only the layout adder
        } else {
            switch tile.tileSize {
            case .square, .rectangle:
                shape = perSqft(sizeAdder(lengthIn: tile.tileLengthIn, widthIn: tile.tileWidthIn), shapeUnit, rate: rate)
            case .mosaic:
                let style = tile.mosaicStyle.map { mosaicStyle[$0] ?? 0 } ?? 0
                shape = perSqft((self.shape[.mosaic] ?? 0) + style, shapeUnit, rate: rate)
            default:
                shape = perSqft(self.shape[tile.tileSize] ?? 0, shapeUnit, rate: rate)
            }
        }
        // Mosaics come on sheets and have no layout of their own.
        let layout = tile.tileSize == .mosaic ? 0 : perSqft(self.layout[tile.layout] ?? 0, layoutUnit, rate: rate)
        return material + shape + layout
    }

    /// Doublings or halvings from the standard tile × their adder; nothing
    /// when a side is missing.
    private func sizeAdder(lengthIn: Double?, widthIn: Double?) -> Double {
        guard let l = lengthIn, let w = widthIn, l > 0, w > 0, standardTileSqIn > 0 else { return 0 }
        let steps = abs(log2(l * w / standardTileSqIn))
        guard steps > 0 else { return 0 }
        return steps * (l * w > standardTileSqIn ? perDoubling : perHalving)
    }
}

/// One area's tile work, priced from a scheme. Same lines, labels and
/// amounts as `legacySummary`.
func schemeSummary(state: EstimatorState, scheme: PricingScheme) -> Summary {
    // A mosaic needs no layout; anything else does.
    guard let area = state.area,
          let type = state.tileType,
          let size = state.tileSize,
          size == .mosaic || state.layout != nil,
          let pricing = scheme.areas[area]
    else { return Summary(lines: [], total: 0) }

    let mainTile = TileChoice(tileType: type, tileSize: size, layout: state.layout ?? .straightStacked,
                              tileWidthIn: state.tileWidthIn, tileLengthIn: state.tileLengthIn,
                              mosaicStyle: state.mosaicStyle, pieces: state.multiTilePieces)
    var lines: [Line] = []

    func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    func tile(_ which: SurfaceTile) -> TileChoice {
        switch which {
        case .main: mainTile
        case .showerFloor: state.showerFloorTile ?? mainTile
        case .ceiling: state.ceilingTile ?? mainTile
        }
    }

    func sqft(_ measure: SurfaceMeasure) -> Double {
        switch measure {
        case .area: state.measurements.sqft
        case .showerWalls: state.measurements.showerWallsSqft
        case .showerFloor: state.measurements.showerFloorSqft
        case .ceiling: state.measurements.ceilingSqft
        }
    }

    /// Rate × sq ft with adders, or the minimum with the adders on top.
    func rated(_ label: String, sqft: Double, rate: Double, minimum: Double?, adders: Double) -> Double {
        guard sqft > 0 else { return 0 }
        let baseOnly = rate * sqft
        let addersAmount = adders * sqft
        let full = (rate + adders) * sqft
        if let minimum, baseOnly < minimum {
            lines.append(Line(label: "\(label) — Minimum Applied", amount: minimum))
            if adders != 0 {
                lines.append(Line(label: "\(label) adders @ \(money(adders))/sqft × \(Int(sqft.rounded()))",
                                  amount: addersAmount))
            }
            return minimum + addersAmount
        }
        if let minimum, minimum > full {
            lines.append(Line(label: "\(label) — Minimum Applied", amount: minimum))
            return minimum
        }
        lines.append(Line(label: "\(label) @ \(money(rate + adders))/sqft × \(Int(sqft.rounded()))", amount: full))
        return full
    }

    /// Walls with a tile each: one rate and minimum for all, each wall's adders on top.
    func separateWalls(_ label: String, rate: Double, minimum: Double?) -> Double {
        let walls = state.walls.filter { $0.sqft > 0 }
        guard !walls.isEmpty else { return 0 }
        let total = walls.reduce(0) { $0 + $1.sqft }
        let baseOnly = rate * total
        let floorCharge = minimum ?? 0
        if baseOnly < floorCharge {
            lines.append(Line(label: "\(label) — Minimum Applied", amount: floorCharge))
        } else {
            lines.append(Line(label: "\(label) @ \(money(rate))/sqft × \(Int(total.rounded()))", amount: baseOnly))
        }
        var amount = max(baseOnly, floorCharge)
        for (i, wall) in state.walls.enumerated() where wall.sqft > 0 {
            let adders = scheme.adders.perSqft(for: wall.tile, rate: rate)
            guard adders != 0 else { continue }
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            lines.append(Line(label: "\(name) adders @ \(money(adders))/sqft × \(Int(wall.sqft.rounded()))",
                              amount: adders * wall.sqft))
            amount += adders * wall.sqft
        }
        return amount
    }

    func escalated(_ label: String, sqft: Double, rate: Double, minimum: Double,
                   window: EscalatorWindow, adders: Double) -> Double {
        guard sqft > 0 else { return 0 }
        var amount = escalatorBase(label, sqft: sqft, rate: rate, minimum: minimum, window: window)
        if adders != 0 {
            lines.append(Line(label: "\(label) adders @ \(money(adders))/sqft × \(Int(sqft.rounded()))",
                              amount: adders * sqft))
            amount += adders * sqft
        }
        return amount
    }

    /// The escalator rule's charge before adders, with its lines.
    func escalatorBase(_ label: String, sqft: Double, rate: Double, minimum: Double,
                       window: EscalatorWindow) -> Double {
        let whole = Int(sqft.rounded(.down))
        let over = whole <= window.through ? max(0, whole - window.from) : 0
        let escalator = Double(over) * window.perSqft
        let baseOnly = rate * sqft
        var amount: Double
        if baseOnly >= minimum + escalator {
            lines.append(Line(label: "\(label) @ \(money(rate))/sqft × \(Int(sqft.rounded()))", amount: baseOnly))
            amount = baseOnly
        } else {
            if minimum > 0 { lines.append(Line(label: "\(label) — Minimum Applied", amount: minimum)) }
            if escalator > 0 {
                lines.append(Line(label: "\(label) escalator @ \(money(window.perSqft))/sqft × \(over)", amount: escalator))
            }
            amount = minimum + escalator
        }
        return amount
    }

    /// Walls with a tile each under an escalator: the rule on all the walls
    /// together, each wall's adders on top.
    func separateWallsEscalated(_ label: String, rate: Double, minimum: Double, window: EscalatorWindow) -> Double {
        let walls = state.walls.filter { $0.sqft > 0 }
        guard !walls.isEmpty else { return 0 }
        var amount = escalatorBase(label, sqft: walls.reduce(0) { $0 + $1.sqft }, rate: rate,
                                   minimum: minimum, window: window)
        for (i, wall) in state.walls.enumerated() where wall.sqft > 0 {
            let adders = scheme.adders.perSqft(for: wall.tile, rate: rate)
            guard adders != 0 else { continue }
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            lines.append(Line(label: "\(name) adders @ \(money(adders))/sqft × \(Int(wall.sqft.rounded()))",
                              amount: adders * wall.sqft))
            amount += adders * wall.sqft
        }
        return amount
    }

    func price(_ surface: SurfacePricing) -> Double {
        let feet = sqft(surface.measure)
        switch surface.rule {
        case let .rate(rate, minimum):
            if surface.wallsCanDiffer, !state.walls.isEmpty {
                return separateWalls(surface.label, rate: rate, minimum: minimum)
            }
            return rated(surface.label, sqft: feet, rate: rate, minimum: minimum,
                         adders: scheme.adders.perSqft(for: tile(surface.tile), rate: rate))
        case let .escalator(rate, minimum, window):
            if surface.wallsCanDiffer, !state.walls.isEmpty {
                return separateWallsEscalated(surface.label, rate: rate, minimum: minimum, window: window)
            }
            return escalated(surface.label, sqft: feet, rate: rate, minimum: minimum, window: window,
                             adders: scheme.adders.perSqft(for: tile(surface.tile), rate: rate))
        }
    }

    var total = 0.0
    for surface in pricing.surfaces { total += price(surface) }
    if state.measurements.ceilingSqft > 0 { total += price(scheme.ceiling) }

    if pricing.chargesFeatures {
        for line in featureLines(state.features, prices: scheme.features, money: money) {
            lines.append(line)
            total += line.amount
        }
    }

    for item in state.decoratives where item.quantity > 0 {
        let rate = scheme.decoratives[item.kind] ?? 0
        guard rate != 0 else { continue }
        let name = item.name.isEmpty ? item.kind.rawValue : "\(item.kind.rawValue): \(item.name)"
        let quantity = item.quantity.formatted(.number.precision(.fractionLength(0...2)))
        lines.append(Line(label: "\(name) @ \(money(rate))/\(item.kind.unit) × \(quantity)", amount: item.quantity * rate))
        total += item.quantity * rate
    }

    return Summary(lines: lines, total: total)
}
