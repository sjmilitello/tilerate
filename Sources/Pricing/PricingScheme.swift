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
}

// MARK: - The owner's pricing, as a scheme

extension PricingScheme {
    /// The pricing the Admin rates describe today.
    init(rates r: Rates) {
        func rate(_ a: Area) -> SurfaceRule { .rate(perSqft: r.base[a] ?? 0, minimum: r.minimum[a]) }
        func one(_ label: String, _ a: Area) -> AreaPricing {
            AreaPricing(surfaces: [SurfacePricing(label: label, measure: .area, tile: .main, rule: rate(a))],
                        chargesFeatures: true)
        }
        let lower = max(0, r.floorEscThresholdLower)
        let window = EscalatorWindow(from: lower, through: max(lower, r.floorEscThresholdUpper),
                                     perSqft: r.floorEscAdjPerSqft)
        areas = [
            .floor: AreaPricing(
                surfaces: [SurfacePricing(label: "Floor", measure: .area, tile: .main,
                                          rule: .escalator(perSqft: r.base[.floor] ?? 0,
                                                           minimum: r.minimum[.floor] ?? 0, window: window))],
                chargesFeatures: false),
            .wall: one("Wall", .wall),
            .tub: AreaPricing(
                surfaces: [SurfacePricing(label: "Tub surround", measure: .area, tile: .main,
                                          rule: rate(.tub), wallsCanDiffer: true)],
                chargesFeatures: true),
            .shower: AreaPricing(
                surfaces: [SurfacePricing(label: "Shower walls", measure: .showerWalls, tile: .main,
                                          rule: rate(.shower), wallsCanDiffer: true),
                           SurfacePricing(label: "Shower floor", measure: .showerFloor, tile: .showerFloor,
                                          rule: .rate(perSqft: r.showerFloorBase, minimum: r.showerFloorMinimum))],
                chargesFeatures: true),
            .backsplash: one("Backsplash", .backsplash),
            .fireplace: one("Fireplace", .fireplace),
        ]
        ceiling = SurfacePricing(label: "Ceiling", measure: .ceiling, tile: .ceiling,
                                 rule: .rate(perSqft: r.ceilingBase, minimum: r.ceilingMinimum))
        adders = TileAdders(material: r.typeAdder, materialUnit: r.typeAdderUnit,
                            shape: r.sizeAdder, shapeUnit: r.sizeAdderUnit,
                            mosaicStyle: r.mosaicStyleAdder,
                            layout: r.layoutAdder, layoutUnit: r.layoutAdderUnit,
                            standardTileSqIn: r.sizeBaseAreaSqIn,
                            perDoubling: r.sizeAdderPerDoubling, perHalving: r.sizeAdderPerHalving)
        features = FeaturePrices(shelf: r.unitShelf, niche: r.unitNiche, footrest: r.unitFootrest, bench: r.unitBench)
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
        if adders != 0 {
            lines.append(Line(label: "\(label) adders @ \(money(adders))/sqft × \(Int(sqft.rounded()))",
                              amount: adders * sqft))
            amount += adders * sqft
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
            return escalated(surface.label, sqft: feet, rate: rate, minimum: minimum, window: window,
                             adders: scheme.adders.perSqft(for: tile(surface.tile), rate: rate))
        }
    }

    var total = 0.0
    for surface in pricing.surfaces { total += price(surface) }
    if state.measurements.ceilingSqft > 0 { total += price(scheme.ceiling) }

    if pricing.chargesFeatures {
        let f = state.features
        for (label, qty, rate) in [("Shelves", f.shelves, scheme.features.shelf),
                                   ("Niches", f.niches, scheme.features.niche),
                                   ("Footrests", f.footrests, scheme.features.footrest),
                                   ("Benches", f.benches, scheme.features.bench)] where qty > 0 && rate != 0 {
            let amount = Double(qty) * rate
            lines.append(Line(label: "\(label) (\(qty)× @ \(money(rate)))", amount: amount))
            total += amount
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
