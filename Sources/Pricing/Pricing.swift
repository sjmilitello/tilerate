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

private func sizeAdderConsideringThresholds(
    baseRate: Double,
    size: TileSize,
    lengthIn: Double?,
    widthIn: Double?,
    rates: Rates
) -> Double {
    let raw = rates.sizeAdder[size] ?? 0
    let perSqRaw = perSqft(from: raw, unit: rates.sizeAdderUnit, baseRate: baseRate)

    switch size {
    case .square, .rectangle:
        guard let L = lengthIn, let W = widthIn, L > 0, W > 0 else { return 0 }
        let area = L * W
        var adders: Double = 0
        if rates.rectSquareOverLengthIn > 0, rates.rectSquareOverWidthIn > 0,
           area > rates.rectSquareOverLengthIn * rates.rectSquareOverWidthIn {
            adders += perSqft(from: rates.rectSquareOverAdder, unit: rates.sizeAdderUnit, baseRate: baseRate)
        }
        if rates.rectSquareUnderLengthIn > 0, rates.rectSquareUnderWidthIn > 0,
           area < rates.rectSquareUnderLengthIn * rates.rectSquareUnderWidthIn {
            adders += perSqft(from: rates.rectSquareUnderAdder, unit: rates.sizeAdderUnit, baseRate: baseRate)
        }
        return adders
    default:
        return perSqRaw
    }
}

private func unitAwareAddersPerSq(
    baseRate: Double,
    type: TileType,
    size: TileSize,
    layout: Layout,
    rates: Rates,
    tileLengthIn: Double?,
    tileWidthIn: Double?
) -> Double {
    let typePerSq = perSqft(from: rates.typeAdder[type] ?? 0,
                            unit: rates.typeAdderUnit,
                            baseRate: baseRate)

    let sizePerSq = sizeAdderConsideringThresholds(
        baseRate: baseRate,
        size: size,
        lengthIn: tileLengthIn,
        widthIn: tileWidthIn,
        rates: rates
    )

    let layoutPerSq = perSqft(from: rates.layoutAdder[layout] ?? 0,
                              unit: rates.layoutAdderUnit,
                              baseRate: baseRate)

    return typePerSq + sizePerSq + layoutPerSq
}

@inline(__always)
private func escalatorAdjPerSqft(rates: Rates) -> Double {
    rates.floorEscAdjPerSqft
}

func computeSummary(
    state: EstimatorState,
    rates: Rates,
    tileLengthIn: Double? = nil,
    tileWidthIn: Double? = nil
) -> Summary {
    var lines: [Line] = []

    guard let area = state.area,
          let type = state.tileType,
          let size = state.tileSize,
          let layout = state.layout
    else {
        return Summary(lines: [], total: 0)
    }

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
        let baseWalls = rates.base[.shower] ?? 0
        let addersWalls = unitAwareAddersPerSq(
            baseRate: baseWalls,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Shower walls",
                                   sqft: state.measurements.showerWallsSqft,
                                   baseRate: baseWalls,
                                   minCharge: rates.minimum[.shower],
                                   addersPerSq: addersWalls)

        let baseShFloor = rates.showerFloorBase
        let addersShFloor = unitAwareAddersPerSq(
            baseRate: baseShFloor,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Shower floor",
                                   sqft: state.measurements.showerFloorSqft,
                                   baseRate: baseShFloor,
                                   minCharge: rates.showerFloorMinimum,
                                   addersPerSq: addersShFloor)

    case .floor:
        let base = rates.base[.floor] ?? 0
        var adders = unitAwareAddersPerSq(
            baseRate: base,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )

        let sqft = state.measurements.sqft
        if Int(sqft) >= rates.floorEscThresholdLower && Int(sqft) <= rates.floorEscThresholdUpper {
            adders += escalatorAdjPerSqft(rates: rates)
        }

        running += appendComponent(labelPrefix: "Floor",
                                   sqft: sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.floor],
                                   addersPerSq: adders)

    case .wall:
        let base = rates.base[.wall] ?? 0
        let adders = unitAwareAddersPerSq(
            baseRate: base,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Wall",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.wall],
                                   addersPerSq: adders)

    case .tub:
        let base = rates.base[.tub] ?? 0
        let adders = unitAwareAddersPerSq(
            baseRate: base,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Tub surround",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.tub],
                                   addersPerSq: adders)

    case .backsplash:
        let base = rates.base[.backsplash] ?? 0
        let adders = unitAwareAddersPerSq(
            baseRate: base,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Backsplash",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.backsplash],
                                   addersPerSq: adders)

    case .fireplace:
        let base = rates.base[.fireplace] ?? 0
        let adders = unitAwareAddersPerSq(
            baseRate: base,
            type: type,
            size: size,
            layout: layout,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Fireplace",
                                   sqft: state.measurements.sqft,
                                   baseRate: base,
                                   minCharge: rates.minimum[.fireplace],
                                   addersPerSq: adders)
    }

    if state.measurements.ceilingSqft > 0 {
        let baseC = rates.ceilingBase
        let addersC = unitAwareAddersPerSq(
            baseRate: baseC,
            type: state.tileType!,
            size: state.tileSize!,
            layout: state.layout!,
            rates: rates,
            tileLengthIn: tileLengthIn,
            tileWidthIn: tileWidthIn
        )
        running += appendComponent(labelPrefix: "Ceiling",
                                   sqft: state.measurements.ceilingSqft,
                                   baseRate: baseC,
                                   minCharge: rates.ceilingMinimum,
                                   addersPerSq: addersC)
    }

    addUnits("Shelves",   qty: state.features.shelves,   rate: rates.unitShelf)
    addUnits("Niches",    qty: state.features.niches,    rate: rates.unitNiche)
    addUnits("Footrests", qty: state.features.footrests, rate: rates.unitFootrest)
    addUnits("Benches",   qty: state.features.benches,   rate: rates.unitBench)

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
