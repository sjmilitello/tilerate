import Foundation

// The words an estimate uses for its areas, shared by both designs so the
// Summary, the PDF and the new design all describe a section the same way.

/// "Primary bath - Shower Tile installation consisting of …"
func estimateSentence(room: EstimateRoom, section: EstimateSection) -> String {
    let areaText = section.area?.rawValue ?? "Area"
    return "\(room.name) - \(areaText) \(describeSection(section))"
}

/// Warnings for square/rectangle tiles with no width or length: their size
/// adder cannot be charged until one is entered.
func missingSizeWarnings(_ sec: EstimateSection) -> [String] {
    var out: [String] = []
    if isMissingTileDimensions(size: sec.tileSize, lengthIn: sec.tileLengthIn, widthIn: sec.tileWidthIn) {
        out.append("Tile width and length missing: no size adder charged.")
    }
    if sec.area == .shower || sec.area == .tub {
        for (i, wall) in sec.walls.enumerated() where wall.sqft > 0 &&
            isMissingTileDimensions(size: wall.tile.tileSize, lengthIn: wall.tile.tileLengthIn,
                                    widthIn: wall.tile.tileWidthIn) {
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            out.append("\(name) tile width and length missing: no size adder charged.")
        }
    }
    if sec.area == .shower, sec.measurements.showerFloorSqft > 0, let t = sec.showerFloorTile,
       isMissingTileDimensions(size: t.tileSize, lengthIn: t.tileLengthIn, widthIn: t.tileWidthIn) {
        out.append("Shower floor tile width and length missing: no size adder charged.")
    }
    if sec.measurements.ceilingSqft > 0, let t = sec.ceilingTile,
       isMissingTileDimensions(size: t.tileSize, lengthIn: t.tileLengthIn, widthIn: t.tileWidthIn) {
        out.append("Ceiling tile width and length missing: no size adder charged.")
    }
    return out
}

/// A section is priced only once it has an area and a main tile type, size
/// and layout; until then it comes to $0.
func isSectionReady(_ sec: EstimateSection) -> Bool {
    sec.area != nil && sec.tileType != nil && sec.tileSize != nil && sec.layout != nil
}

/// The sentence describing one section on the Summary and the PDF.
func describeSection(_ section: EstimateSection) -> String {
    // Room + Area (room name may already be shown elsewhere; keeping as-is)
    let roomPrefix = section.roomName.isEmpty ? "" : "\(section.roomName) – "
    
    // --- Size FIRST (Width × Length), no "in"
    // If your properties are optional, change to: let W = section.tileWidthIn ?? 0, etc.
    let W = section.tileWidthIn
    let L = section.tileLengthIn
    
    func sizePart() -> String {
        let wStr = describeInches(W) ?? ""
        let lStr = describeInches(L) ?? ""
        switch (wStr.isEmpty, lStr.isEmpty) {
        case (false, false): return "\(wStr)×\(lStr) "   // note trailing space
        case (false, true):  return "\(wStr) "           // width only
        case (true, false):  return "\(lStr) "           // length only
        default:             return ""                   // no size shown
        }
    }
    
    // Tile type
    let typeText = section.tileType?.rawValue ?? "Tile"
    
    // Layout
    let layoutText = section.layout?.rawValue ?? "Layout"
    
    // Surfaces based on entered measurements (unchanged)
    var surfaces: [String] = []
    switch section.area {
    case .some(.shower):
        let wallsSame = section.walls.isEmpty
        if wallsSame, section.measurements.showerWallsSqft > 0 { surfaces.append("Walls") }
        if section.measurements.showerFloorSqft > 0 { surfaces.append("Floor") }
        if section.measurements.ceilingSqft > 0    { surfaces.append("Ceiling") }
        if wallsSame, surfaces.isEmpty { surfaces = ["Walls", "Floor"] }
    case .some(.tub):
        let wallsSame = section.walls.isEmpty
        if wallsSame, section.measurements.sqft > 0 { surfaces.append("Walls") }
        if section.measurements.ceilingSqft > 0   { surfaces.append("Ceiling") }
        if wallsSame, surfaces.isEmpty { surfaces = ["Walls"] }
    case .some(.floor):
        if section.measurements.sqft > 0          { surfaces.append("Floor") }
    case .some(.wall), .some(.backsplash), .some(.fireplace):
        if section.measurements.sqft > 0          { surfaces.append("Walls") }
    case .none:
        break
    }
    // Shower walls, floor or ceiling with their own tile are described separately
    var otherTiles: [String] = []
    if section.area == .shower || section.area == .tub {
        for (i, wall) in section.walls.enumerated() where wall.sqft > 0 {
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            otherTiles.append("\(tilePhrase(wall.tile)) on \(name)")
        }
    }
    if section.area == .shower, section.measurements.showerFloorSqft > 0, let t = section.showerFloorTile {
        surfaces.removeAll { $0 == "Floor" }
        otherTiles.append("\(tilePhrase(t)) on Floor")
    }
    if section.measurements.ceilingSqft > 0, let t = section.ceilingTile {
        surfaces.removeAll { $0 == "Ceiling" }
        otherTiles.append("\(tilePhrase(t)) on Ceiling")
    }
    let otherTilesText = otherTiles.map { "; " + $0 }.joined()

    let surfacesText = surfaces.isEmpty ? "" : " on " + surfaces.joined(separator: ", ")

    // Feature list (unchanged)
    var features: [String] = []
    if section.area != .floor {
        if section.features.shelves   > 0 { features.append(section.features.shelves   == 1 ? "Shelf"    : "\(section.features.shelves) Shelves") }
        if section.features.niches    > 0 { features.append(section.features.niches    == 1 ? "Niche"    : "\(section.features.niches) Niches") }
        if section.features.footrests > 0 { features.append(section.features.footrests == 1 ? "Footrest" : "\(section.features.footrests) Footrests") }
        if section.features.benches   > 0 { features.append(section.features.benches   == 1 ? "Bench"    : "\(section.features.benches) Benches") }
    }
    if section.features.mosaicBand {
        features.append("Mosaic Inlay")
    }
    let featuresText = features.isEmpty ? "" : " with " + features.joined(separator: ", ")
    
    // Every surface has its own tile: no main-tile phrase to lead with
    if surfaces.isEmpty, !otherTiles.isEmpty {
        return "\(roomPrefix)Tile installation consisting of \(otherTiles.joined(separator: "; "))\(featuresText)."
    }

    // Final sentence: SIZE first, then type
    return "\(roomPrefix)Tile installation consisting of \(sizePart())\(typeText) Tile in \(layoutText) pattern\(surfacesText)\(otherTilesText)\(featuresText)."
}

/// "2×2 Porcelain Tile in Straight Stacked pattern", for a separate tile.
private func tilePhrase(_ t: TileChoice) -> String {
    let w = describeInches(t.tileWidthIn), l = describeInches(t.tileLengthIn)
    let size = [w, l].compactMap { $0 }.joined(separator: "×")
    return "\(size.isEmpty ? "" : size + " ")\(t.tileType.rawValue) Tile in \(t.layout.rawValue) pattern"
}
private func describeInches(_ v: Double?) -> String? {
    guard let v, v > 0 else { return nil }
    if v.rounded(.towardZero) == v { return String(format: "%.0f", v) }
    return String(format: "%.1f", v)
}

/// Under a square or rectangle tile's size: how it compares with the standard
/// tile and what that adds, e.g. "1,152 sq in · 4× the standard tile · adds
/// $5.00 per sq ft". nil for other shapes or when a dimension is missing.
func sizeAdderNote(size: TileSize?, lengthIn: Double?, widthIn: Double?, rates: Rates) -> String? {
    guard let size, let doublings = sizeDoublings(size: size, lengthIn: lengthIn, widthIn: widthIn, rates: rates),
          size == .square || size == .rectangle,
          let L = lengthIn, let W = widthIn, rates.sizeBaseAreaSqIn > 0 else { return nil }
    let area = L * W
    let ratio = area / rates.sizeBaseAreaSqIn
    func trim(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }

    let comparison: String
    if abs(ratio - 1) < 0.005 {
        return "\(trim(area)) sq in · the standard tile · no size adder"
    } else if ratio >= 0.5 {
        comparison = "\(trim(ratio))× the standard tile"
    } else {
        comparison = "1/\(trim(1 / ratio)) of the standard tile"
    }

    let adds: String
    switch rates.sizeAdderUnit {
    case .perSqft:
        let amount = doublings * rates.sizeAdderPerDoubling
        adds = "adds \(amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) per sq ft"
    case .percent:
        adds = "adds \(trim(doublings * rates.sizeAdderPerDoubling))% of the base rate"
    }
    return "\(trim(area)) sq in · \(comparison) · \(adds)"
}
