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
/// adds `sizeAdderPerDoubling`. Other shapes have none. Returns nil when the
/// tile's width or length is missing, so the size adder can't be worked out.
func sizeDoublings(size: TileSize, lengthIn: Double?, widthIn: Double?, rates: Rates) -> Double? {
    guard size == .square || size == .rectangle else { return 0 }
    guard let L = lengthIn, let W = widthIn, L > 0, W > 0 else { return nil }
    guard rates.sizeBaseAreaSqIn > 0 else { return 0 }
    return abs(log2(L * W / rates.sizeBaseAreaSqIn))
}

/// True when a square or rectangle tile has no width or length entered, so its
/// size adder cannot be charged.
func isMissingTileDimensions(size: TileSize?, lengthIn: Double?, widthIn: Double?) -> Bool {
    guard let size, size == .square || size == .rectangle else { return false }
    return (lengthIn ?? 0) <= 0 || (widthIn ?? 0) <= 0
}

private func sizeAdderPerSq(baseRate: Double, tile: TileChoice, rates: Rates) -> Double {
    switch tile.tileSize {
    case .square, .rectangle:
        let doublings = sizeDoublings(size: tile.tileSize, lengthIn: tile.tileLengthIn,
                                      widthIn: tile.tileWidthIn, rates: rates) ?? 0
        return doublings * perSqft(from: rates.sizeAdderPerDoubling, unit: rates.sizeAdderUnit, baseRate: baseRate)
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

func computeSummary(state: EstimatorState, rates: Rates) -> Summary {
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
                              mosaicStyle: state.mosaicStyle)

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

    @inline(__always)
    func addUnits(_ label: String, qty: Int, rate: Double) {
        guard qty > 0, rate != 0 else { return }
        let amt = Double(qty) * rate
        lines.append(Line(label: "\(label) (\(qty)× @ \(currency(rates: rates, value: rate)))", amount: amt))
        running += amt
    }

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
        addUnits("Shelves",   qty: state.features.shelves,   rate: rates.unitShelf)
        addUnits("Niches",    qty: state.features.niches,    rate: rates.unitNiche)
        addUnits("Footrests", qty: state.features.footrests, rate: rates.unitFootrest)
        addUnits("Benches",   qty: state.features.benches,   rate: rates.unitBench)
    }

    if state.features.mosaicBand, state.measurements.mosaicSqft > 0, rates.mosaicInlayRate != 0 {
        let m = state.measurements.mosaicSqft * rates.mosaicInlayRate
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        let rateStr = f.string(from: NSNumber(value: rates.mosaicInlayRate)) ?? "$\(rates.mosaicInlayRate)"
        lines.append(Line(label: "Mosaic inlay @ \(rateStr)/sqft × \(Int(state.measurements.mosaicSqft.rounded()))", amount: m))
        running += m
    }

    return Summary(lines: lines, total: running)
}

// MARK: - Whole estimate

struct SectionPrice {
    let room: EstimateRoom
    let section: EstimateSection
    let core: Summary
    let labor: Double
    let mats: Double
    var subtotal: Double { core.total + labor + mats }
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
            sections.append(SectionPrice(
                room: room,
                section: sec,
                core: computeSummary(state: EstimatorState(section: sec), rates: rates),
                labor: sec.additionsLabor.reduce(0) { $0 + $1.amount },
                mats: sec.additionsMaterials.reduce(0) { $0 + $1.amount }
            ))
        }
    }

    let materials = document.rooms.flatMap { $0.sections }.flatMap { $0.additionsMaterials }
    let taxableBase = materials.filter { $0.taxable }.reduce(0) { $0 + $1.amount }

    return EstimateTotals(
        sections: sections,
        subtotal: sections.reduce(0) { $0 + $1.subtotal },
        taxableBase: taxableBase,
        taxPercent: taxPercent,
        shipping: (shippingEnabled && !materials.isEmpty) ? shipping : 0
    )
}
