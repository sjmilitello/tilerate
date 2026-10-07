import Foundation

// The words an estimate uses for its areas, shared by both designs so the
// Summary, the PDF and the new design all describe a section the same way.

/// "Primary bath - Shower Tile installation consisting of …"
func estimateSentence(room: EstimateRoom, section: EstimateSection, wording: WordingTemplates) -> String {
    let areaText = section.area?.rawValue ?? "Area"
    return "\(room.name) - \(areaText) \(areaWording(section, wording: wording).text)"
}

/// What an area says on the estimate: the owner's own wording when they
/// typed some, otherwise the sentence generated from the templates.
struct AreaWording {
    let text: String
    let generated: String
    let isCustom: Bool
    /// Typed before the area last changed: the typed words may no longer
    /// describe it.
    let isOutOfDate: Bool
}

func areaWording(_ section: EstimateSection, wording: WordingTemplates) -> AreaWording {
    let generated = describeSection(section, wording: wording)
    guard let custom = section.customWording else {
        return AreaWording(text: generated, generated: generated, isCustom: false, isOutOfDate: false)
    }
    return AreaWording(text: custom.text, generated: generated, isCustom: true,
                       isOutOfDate: custom.generatedFrom != generated)
}

extension EstimateSection {
    /// Sets the area's own wording; wording identical to the generated
    /// sentence clears it.
    mutating func setWording(_ text: String, wording: WordingTemplates) {
        let generated = describeSection(self, wording: wording)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        customWording = trimmed.isEmpty || trimmed == generated
            ? nil : CustomWording(text: trimmed, generatedFrom: generated)
    }

    /// Keeps the typed wording after the area changed: it is no longer flagged.
    mutating func keepWording(wording: WordingTemplates) {
        let generated = describeSection(self, wording: wording)
        customWording?.generatedFrom = generated
    }
}

/// Turns wording typed for one area into a sentence template for every area
/// of its kind: the parts the app wrote for this area go back to brace words
/// ({tiles}, {features}, {sqft}), and the words joining features are put in
/// brackets so they drop out when there are none. nil when the tile
/// description was changed, which a sentence template can't hold — that is
/// edited under "Each tile".
func templateFromEdit(_ text: String, section: EstimateSection, wording: WordingTemplates) -> String? {
    let (prefix, values) = sentenceParts(section, wording: wording)
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !prefix.isEmpty, t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
    guard let tiles = values["tiles"], !tiles.isEmpty, t.contains(tiles) else { return nil }
    t = t.replacingOccurrences(of: tiles, with: "{tiles}")
    if let features = values["features"], !features.isEmpty {
        t = t.replacingOccurrences(of: features, with: "{features}")
    }
    if let sqft = values["sqft"], !sqft.isEmpty {
        t = t.replacingOccurrences(of: sqft, with: "{sqft}")
    }
    // " with {features}", ", including {features}", " ({sqft})" … in brackets.
    for word in ["features", "sqft"] {
        let pattern = #"((?:,|;|:)?\s*(?:(?:with|including|and|plus|featuring|also)\s+)?\(?\{"# + word + #"\}\)?)"#
        if let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
           !t[..<r.lowerBound].hasSuffix("[") {
            t.replaceSubrange(r, with: "[" + t[r] + "]")
        }
    }
    return t
}


/// Warnings for square/rectangle tiles with no width or length: their size
/// adder cannot be charged until one is entered.
func missingSizeWarnings(_ sec: EstimateSection) -> [String] {
    var out: [String] = []
    if sec.layout != .multiTile,
       isMissingTileDimensions(size: sec.tileSize, lengthIn: sec.tileLengthIn, widthIn: sec.tileWidthIn) {
        out.append("Tile width and length missing: no size adder charged.")
    }
    if sec.area == .shower || sec.area == .tub {
        for (i, wall) in sec.walls.enumerated() where wall.sqft > 0 && needsSize(wall.tile) {
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            out.append("\(name) tile width and length missing: no size adder charged.")
        }
    }
    if sec.area == .shower, sec.measurements.showerFloorSqft > 0, let t = sec.showerFloorTile, needsSize(t) {
        out.append("Shower floor tile width and length missing: no size adder charged.")
    }
    if sec.measurements.ceilingSqft > 0, let t = sec.ceilingTile, needsSize(t) {
        out.append("Ceiling tile width and length missing: no size adder charged.")
    }
    return out
}

/// A square or rectangle tile with no width or length, outside a multi-tile
/// layout (which has no size adder).
private func needsSize(_ t: TileChoice) -> Bool {
    t.layout != .multiTile && isMissingTileDimensions(size: t.tileSize, lengthIn: t.tileLengthIn, widthIn: t.tileWidthIn)
}

/// A section is priced only once it has an area and a main tile type, size
/// and layout (a mosaic needs no layout); until then it comes to $0.
func isSectionReady(_ sec: EstimateSection) -> Bool {
    sec.area != nil && sec.tileType != nil && sec.tileSize != nil
        && (sec.tileSize == .mosaic || sec.layout != nil)
}

/// The sentence describing one section on the Summary and the PDF, from the
/// owner's wording templates. `WordingTemplates.standard` gives the wording
/// the app always used; WordingGoldenTests holds it to that.
func describeSection(_ section: EstimateSection, wording: WordingTemplates) -> String {
    let (roomPrefix, values) = sentenceParts(section, wording: wording)
    return roomPrefix + fillTemplate(wording.sentence(for: section.area), values)
}

/// The "Room – " lead-in and what the sentence template's brace words stand
/// for, for one area.
private func sentenceParts(_ section: EstimateSection, wording: WordingTemplates) -> (prefix: String, values: [String: String]) {
    let roomPrefix = section.roomName.isEmpty ? "" : "\(section.roomName) – "

    let mainPhrase = fillTemplate(wording.tile, tileValues(
        type: section.tileType?.rawValue ?? "Tile", size: section.tileSize,
        layout: section.layout?.rawValue ?? "Layout", widthIn: section.tileWidthIn,
        lengthIn: section.tileLengthIn, style: section.mosaicStyle, pieces: section.multiTilePieces))

    // The surfaces the area's own tile goes on, from the measurements entered.
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
    // Walls, floor or ceiling with their own tile are described separately.
    var otherTiles: [String] = []
    if section.area == .shower || section.area == .tub {
        for (i, wall) in section.walls.enumerated() where wall.sqft > 0 {
            let name = wall.name.isEmpty ? "Wall \(i + 1)" : wall.name
            otherTiles.append("\(tilePhrase(wall.tile, wording)) on \(name)")
        }
    }
    if section.area == .shower, section.measurements.showerFloorSqft > 0, let t = section.showerFloorTile {
        surfaces.removeAll { $0 == "Floor" }
        otherTiles.append("\(tilePhrase(t, wording)) on Floor")
    }
    if section.measurements.ceilingSqft > 0, let t = section.ceilingTile {
        surfaces.removeAll { $0 == "Ceiling" }
        otherTiles.append("\(tilePhrase(t, wording)) on Ceiling")
    }

    // Every surface with its own tile: no area tile to lead with.
    let tiles: String
    if surfaces.isEmpty, !otherTiles.isEmpty {
        tiles = otherTiles.joined(separator: "; ")
    } else {
        tiles = mainPhrase + (surfaces.isEmpty ? "" : " on " + surfaces.joined(separator: ", "))
            + otherTiles.map { "; " + $0 }.joined()
    }

    var features: [String] = []
    if section.area != .floor {
        if section.features.shelves   > 0 { features.append(section.features.shelves   == 1 ? "Shelf"    : "\(section.features.shelves) Shelves") }
        if section.features.niches    > 0 { features.append(section.features.niches    == 1 ? "Niche"    : "\(section.features.niches) Niches") }
        if section.features.footrests > 0 { features.append(section.features.footrests == 1 ? "Footrest" : "\(section.features.footrests) Footrests") }
        if section.features.benches   > 0 { features.append(section.features.benches   == 1 ? "Bench"    : "\(section.features.benches) Benches") }
        if section.features.seats     > 0 { features.append(section.features.seats     == 1 ? "Corner Seat" : "\(section.features.seats) Corner Seats") }
        if section.features.windows   > 0 { features.append(section.features.windows   == 1 ? "Window"   : "\(section.features.windows) Windows") }
    }
    for item in section.decoratives where item.quantity > 0 {
        features.append(decorativePhrase(item, in: section))
    }

    let sqft = section.areaSqft
    return (roomPrefix, [
        "tiles": tiles,
        "features": features.joined(separator: ", "),
        "area": section.area?.rawValue ?? "",
        "sqft": sqft > 0 ? "\(sqft.formatted(.number.precision(.fractionLength(0...2)))) sq ft" : "",
    ])
}

/// "2×2 Porcelain Tile in Straight Stacked pattern", for a separate tile.
private func tilePhrase(_ t: TileChoice, _ wording: WordingTemplates) -> String {
    fillTemplate(wording.tile, tileValues(type: t.tileType.rawValue, size: t.tileSize, layout: t.layout.rawValue,
                                          widthIn: t.tileWidthIn, lengthIn: t.tileLengthIn,
                                          style: t.mosaicStyle, pieces: t.pieces))
}

/// What the tile template's brace words stand for, for one tile.
private func tileValues(type: String, size shape: TileSize?, layout: String, widthIn: Double?, lengthIn: Double?,
                        style: MosaicStyle?, pieces: [TilePiece]) -> [String: String] {
    let isMosaic = shape == .mosaic
    // A multi-tile layout's sizes are listed with its pieces instead.
    let isMultiTile = layout == Layout.multiTile.rawValue && !isMosaic
    let size = isMultiTile ? "" : [describeInches(widthIn), describeInches(lengthIn)].compactMap { $0 }.joined(separator: "×")
    let pieceList = pieces.map(pieceLabel).filter { !$0.isEmpty }.joined(separator: ", ")
    return [
        "size": size,
        "material": type,
        "tile": tileWord(size: shape, style: style),
        "shape": shape?.rawValue ?? "",
        "mosaic": isMosaic ? (style?.rawValue ?? "") : "",
        "layout": isMosaic ? "" : layout,
        "pieces": isMultiTile ? pieceList : "",
    ]
}

/// Fills a wording template. "{name}" is replaced by its value; a part in
/// square brackets is left out when every brace word in it is empty. A brace
/// word the app doesn't know is left as typed, so a typo shows.
func fillTemplate(_ template: String, _ values: [String: String]) -> String {
    /// The text with its brace words filled in, and whether it had any
    /// known brace word, and whether any of them had a value.
    func fill(_ text: Substring) -> (text: String, hasWords: Bool, anyFilled: Bool) {
        var out = "", hasWords = false, anyFilled = false
        var rest = text
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                out += rest[open...]; rest = ""; break
            }
            let name = String(rest[rest.index(after: open)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
            if let value = values[name] {
                hasWords = true
                if !value.isEmpty { anyFilled = true }
                out += value
            } else {
                out += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return (out, hasWords, anyFilled)
    }

    var out = ""
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "[") {
        out += fill(rest[..<open]).text
        guard let close = rest[open...].firstIndex(of: "]") else {
            rest = rest[open...]; break
        }
        let part = fill(rest[rest.index(after: open)..<close])
        if !part.hasWords || part.anyFilled { out += part.text }
        rest = rest[rest.index(after: close)...]
    }
    out += fill(rest).text
    return out
}

/// " (12×24, 24×24, 6×6 Hexagon)" for the tiles in a multi-tile layout.
func piecesText(_ pieces: [TilePiece]) -> String {
    let parts = pieces.map(pieceLabel).filter { !$0.isEmpty }
    return parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
}

/// "12×24" for a square or rectangle, "6×6 Hexagon" for other shapes.
func pieceLabel(_ p: TilePiece) -> String {
    let size = [describeInches(p.widthIn), describeInches(p.lengthIn)].compactMap { $0 }.joined(separator: "×")
    let shape = p.shape == .square || p.shape == .rectangle ? "" : p.shape.rawValue
    return [size, shape].filter { !$0.isEmpty }.joined(separator: " ")
}

/// "Tile", or "Penny Round Mosaic" for a mosaic with a style chosen.
private func tileWord(size: TileSize?, style: MosaicStyle?) -> String {
    guard size == .mosaic, let style else { return "Tile" }
    return "\(style.rawValue) Mosaic"
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
    guard let size, let amount = sizeAdderAmount(size: size, lengthIn: lengthIn, widthIn: widthIn, rates: rates),
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
        adds = "adds \(amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) per sq ft"
    case .percent:
        adds = "adds \(trim(amount))% of the base rate"
    }
    return "\(trim(area)) sq in · \(comparison) · \(adds)"
}

/// "Band of Glass Penny Round Mosaic on Back Wall & Left Wall", or with its
/// name, "Band “Chair rail” of 3×12 Marble Tile". The quantity is left out.
func decorativePhrase(_ item: DecorativeItem, in section: EstimateSection) -> String {
    let named = item.name.isEmpty ? "" : " “\(item.name)”"
    let w = describeInches(item.tile.tileWidthIn), l = describeInches(item.tile.tileLengthIn)
    let size = [w, l].compactMap { $0 }.joined(separator: "×")
    let tile = "\(size.isEmpty ? "" : size + " ")\(item.tile.tileType.rawValue) \(tileWord(size: item.tile.tileSize, style: item.tile.mosaicStyle))"
    let places = decorativeLocationLabels(item, in: section)
    // "&" rather than commas, so the places don't run into the features list.
    let whereText = places.isEmpty ? "" : " on " + places.joined(separator: " & ")
    return "\(item.kind.rawValue)\(named) of \(tile)\(whereText)"
}

/// Where a band, border or inlay can go in a shower or tub surround: its
/// walls (Back, Left and Right when all walls are the same, otherwise each
/// wall by name), the ceiling when tiled, and a shower's floor when measured.
/// Keys are what `DecorativeItem.locations` stores; labels are shown.
func decorativeLocationOptions(_ sec: EstimateSection) -> [(key: String, label: String)] {
    guard sec.area == .shower || sec.area == .tub else { return [] }
    var out: [(String, String)] = []
    if sec.walls.isEmpty {
        out += ["Back Wall", "Left Wall", "Right Wall"].map { ($0, $0) }
    } else {
        out += sec.walls.enumerated().map { i, w in
            ("wall:\(w.id.uuidString)", w.name.isEmpty ? "Wall \(i + 1)" : w.name)
        }
    }
    if sec.area == .shower, sec.measurements.showerFloorSqft > 0 { out.append(("Shower Floor", "Shower Floor")) }
    if sec.measurements.ceilingSqft > 0 { out.append(("Ceiling", "Ceiling")) }
    return out
}

/// The labels of an item's chosen locations that still exist in the area, in
/// the area's order. A location chosen before the walls were split matches a
/// wall of the same name.
func decorativeLocationLabels(_ item: DecorativeItem, in sec: EstimateSection) -> [String] {
    decorativeLocationOptions(sec).filter { item.isAt($0) }.map(\.label)
}

/// The tile a new band, border or inlay starts with: in a shower, the shower
/// floor's mosaic when it has one; otherwise the area's main tile.
func defaultDecorativeTile(for sec: EstimateSection) -> TileChoice {
    if sec.area == .shower, let floor = sec.showerFloorTile, floor.tileSize == .mosaic {
        return floor
    }
    return mainTile(of: sec) ?? TileChoice()
}

/// The section's main tile, when its type and shape are chosen.
private func mainTile(of sec: EstimateSection) -> TileChoice? {
    guard let tileType = sec.tileType, let tileSize = sec.tileSize else { return nil }
    return TileChoice(tileType: tileType, tileSize: tileSize, layout: sec.layout ?? .straightStacked,
                      tileWidthIn: sec.tileWidthIn, tileLengthIn: sec.tileLengthIn, mosaicStyle: sec.mosaicStyle,
                      pieces: sec.multiTilePieces)
}

extension DecorativeItem {
    func isAt(_ option: (key: String, label: String)) -> Bool {
        locations.contains(option.key)
            || locations.contains { $0.caseInsensitiveCompare(option.label) == .orderedSame }
    }

    /// Selects or clears a location. Bands and borders can span several; an
    /// inlay sits in one place, so choosing another replaces it.
    mutating func toggleLocation(_ option: (key: String, label: String)) {
        if isAt(option) {
            locations.removeAll { $0 == option.key || $0.caseInsensitiveCompare(option.label) == .orderedSame }
        } else if kind == .inlay {
            locations = [option.key]
        } else {
            locations.append(option.key)
        }
    }
}
