import Foundation
@testable import TileRate_Installation_Estimator

// The fixed set of areas the pricing engines are checked against
// (PricingGoldenTests). Each case is a name, the rates and one area. The
// expected results in PricingGolden.swift were recorded from the pricing as
// it stood on 2026-10-06, checked against the owner's rules in CLAUDE.md, and
// must not change unless the owner changes a rule. Never edit a case: add new
// ones instead, so the recorded results keep meaning what they meant.

struct PricingCase {
    let name: String
    let rates: Rates
    let section: EstimateSection
}

enum PricingCases {
    /// Rates like the owner's in shape: a floor minimum with the escalator,
    /// adders on materials, sizes, layouts and mosaic styles, priced features.
    static var ownerLike: Rates {
        var r = Rates()
        r.base = [.floor: 21, .wall: 27, .tub: 27, .shower: 30, .backsplash: 32, .fireplace: 35]
        r.minimum = [.floor: 1500, .wall: 900, .tub: 1200, .shower: 2500, .backsplash: 650, .fireplace: 800]
        r.ceilingBase = 25; r.ceilingMinimum = 600
        r.showerFloorBase = 28; r.showerFloorMinimum = 700
        for t in TileType.allCases { r.typeAdder[t] = 0 }
        r.typeAdder[.porcelain] = 1; r.typeAdder[.marble] = 4; r.typeAdder[.zellige] = 6
        for s in TileSize.allCases { r.sizeAdder[s] = 0 }
        r.sizeAdder[.hexagon] = 2; r.sizeAdder[.arabesque] = 3; r.sizeAdder[.starCross] = 3; r.sizeAdder[.mosaic] = 5
        for l in Layout.allCases { r.layoutAdder[l] = 0 }
        r.layoutAdder[.runningBond] = 0.5; r.layoutAdder[.diagonal] = 1.5
        r.layoutAdder[.herringbone] = 3; r.layoutAdder[.multiTile] = 4
        for m in MosaicStyle.allCases { r.mosaicStyleAdder[m] = 0 }
        r.mosaicStyleAdder[.pennyRound] = 2; r.mosaicStyleAdder[.herringbone] = 4
        r.sizeBaseAreaSqIn = 288; r.sizeAdderPerDoubling = 2.5; r.sizeAdderPerHalving = 1.5
        r.typeAdderUnit = .perSqft; r.sizeAdderUnit = .perSqft; r.layoutAdderUnit = .perSqft
        r.bandRatePerLinFt = 20; r.borderRatePerLinFt = 25; r.mosaicInlayRate = 40
        r.unitShelf = 600; r.unitNiche = 600; r.unitFootrest = 200; r.unitBench = 350
        r.floorEscThresholdLower = 50; r.floorEscThresholdUpper = 99; r.floorEscAdjPerSqft = 14
        return r
    }

    /// The same, with every adder as a percentage of the base rate.
    static var percentAdders: Rates {
        var r = ownerLike
        r.typeAdderUnit = .percent; r.sizeAdderUnit = .percent; r.layoutAdderUnit = .percent
        r.typeAdder[.porcelain] = 5; r.typeAdder[.marble] = 20
        r.sizeAdder[.hexagon] = 10; r.sizeAdder[.mosaic] = 25
        r.layoutAdder[.herringbone] = 15; r.layoutAdder[.runningBond] = 2
        r.mosaicStyleAdder[.pennyRound] = 10
        r.sizeAdderPerDoubling = 8; r.sizeAdderPerHalving = 6
        return r
    }

    /// No minimums, no escalator rate, and a different escalator window.
    static var noMinimums: Rates {
        var r = ownerLike
        for a in Area.allCases { r.minimum[a] = 0 }
        r.ceilingMinimum = 0; r.showerFloorMinimum = 0
        r.floorEscThresholdLower = 40; r.floorEscThresholdUpper = 80; r.floorEscAdjPerSqft = 0
        return r
    }

    /// An escalator but no floor minimum, and a window starting at zero.
    static var escalatorOnly: Rates {
        var r = ownerLike
        r.minimum[.floor] = 0
        r.floorEscThresholdLower = 0; r.floorEscThresholdUpper = 60; r.floorEscAdjPerSqft = 30
        return r
    }

    static let rateSets: [(String, Rates)] = [
        ("owner", ownerLike), ("percent", percentAdders), ("nomin", noMinimums), ("esconly", escalatorOnly),
    ]

    static func tile(_ type: TileType, _ size: TileSize, _ layout: Layout,
                     w: Double? = nil, l: Double? = nil, style: MosaicStyle? = nil,
                     pieces: [TilePiece] = []) -> TileChoice {
        TileChoice(tileType: type, tileSize: size, layout: layout, tileWidthIn: w, tileLengthIn: l,
                   mosaicStyle: style, pieces: pieces)
    }

    static let tiles: [(String, TileChoice)] = [
        ("porc12x24rb", tile(.porcelain, .rectangle, .runningBond, w: 12, l: 24)),
        ("porc24x48hb", tile(.porcelain, .rectangle, .herringbone, w: 24, l: 48)),
        ("cer3x12st", tile(.ceramic, .rectangle, .straightStacked, w: 3, l: 12)),
        ("marb12sq", tile(.marble, .square, .diagonal, w: 12, l: 12)),
        ("sqNoSize", tile(.ceramic, .square, .straightStacked)),
        ("hex", tile(.ceramic, .hexagon, .straightStacked)),
        ("arab", tile(.zellige, .arabesque, .runningBond)),
        ("mosPenny", tile(.porcelain, .mosaic, .herringbone, style: .pennyRound)),
        ("mosPlain", tile(.marble, .mosaic, .straightStacked)),
        ("multi", tile(.porcelain, .rectangle, .multiTile, w: 24, l: 48,
                       pieces: [TilePiece(shape: .rectangle, widthIn: 12, lengthIn: 24),
                                TilePiece(shape: .square, widthIn: 24, lengthIn: 24)])),
    ]

    static func section(_ area: Area, tile t: TileChoice, sqft: Double = 0,
                        showerWalls: Double = 0, showerFloor: Double = 0, ceiling: Double = 0) -> EstimateSection {
        var s = EstimateSection()
        s.area = area
        s.tileType = t.tileType
        s.tileSize = t.tileSize
        s.layout = t.layout
        s.tileWidthIn = t.tileWidthIn
        s.tileLengthIn = t.tileLengthIn
        s.mosaicStyle = t.mosaicStyle
        s.multiTilePieces = t.pieces
        s.measurements.sqft = sqft
        s.measurements.showerWallsSqft = showerWalls
        s.measurements.showerFloorSqft = showerFloor
        s.measurements.ceilingSqft = ceiling
        return s
    }

    static let recordedLayouts: [Layout] = [.straightStacked, .runningBond, .diagonal, .herringbone, .multiTile]
    static let recordedShapes: [TileSize] = [.square, .rectangle, .hexagon, .arabesque, .starCross, .mosaic]
    static let recordedStyles: [MosaicStyle] = [.square, .hexagon, .octagonDot, .diamond, .rectangular, .miniBrick,
                                                 .picket, .herringbone, .chevron, .basketweave, .pinwheel, .pennyRound,
                                                 .fishscale, .arabesque, .pebble, .randomStrip, .waterjet]

    static var all: [PricingCase] {
        var out: [PricingCase] = []
        let main = tiles[0].1

        // 1. Every area across sizes either side of each minimum and threshold.
        let floorSizes: [Double] = [0, 1, 20, 39, 40, 41, 49, 49.5, 50, 50.9, 51, 52, 60, 70, 71.4, 72,
                                    79, 80, 81, 98, 99, 99.5, 100, 101, 120, 150, 400]
        let otherSizes: [Double] = [0, 5, 18, 20, 21, 24.9, 25, 30, 33.3, 40, 100, 250]
        for (rn, r) in rateSets {
            for a in Area.allCases where a != .shower {
                for q in (a == .floor ? floorSizes : otherSizes) {
                    out.append(.init(name: "size/\(rn)/\(a.rawValue)/\(q)", rates: r,
                                     section: section(a, tile: main, sqft: q)))
                }
            }
            for w in otherSizes + [60, 83.4, 90] {
                for f in [0.0, 9, 15, 25, 30] {
                    out.append(.init(name: "shower/\(rn)/w\(w)/f\(f)", rates: r,
                                     section: section(.shower, tile: main, showerWalls: w, showerFloor: f)))
                }
            }
        }

        // 2. Every tile against every area, small and large.
        for (rn, r) in rateSets.prefix(2) {
            for (tn, t) in tiles {
                for a in Area.allCases {
                    for q in [12.0, 45, 75, 140] {
                        out.append(.init(name: "tile/\(rn)/\(tn)/\(a.rawValue)/\(q)", rates: r,
                                         section: section(a, tile: t, sqft: q, showerWalls: q, showerFloor: q / 5)))
                    }
                }
            }
        }

        // 3. Every material, layout, shape and mosaic style on a wall.
        for (rn, r) in rateSets.prefix(2) {
            for m in TileType.allCases {
                out.append(.init(name: "material/\(rn)/\(m.rawValue)", rates: r,
                                 section: section(.wall, tile: tile(m, .hexagon, .straightStacked), sqft: 80)))
            }
            // The layouts, shapes and styles there were when this was recorded
            // (2026-10-06); later ones are tested in NewTileChoicesTests.
            for l in Self.recordedLayouts {
                out.append(.init(name: "layout/\(rn)/\(l.rawValue)", rates: r,
                                 section: section(.wall, tile: tile(.ceramic, .hexagon, l), sqft: 80)))
            }
            for s in Self.recordedShapes {
                out.append(.init(name: "shape/\(rn)/\(s.rawValue)", rates: r,
                                 section: section(.wall, tile: tile(.ceramic, s, .straightStacked, w: 6, l: 6), sqft: 80)))
            }
            for st in Self.recordedStyles {
                out.append(.init(name: "mosaic/\(rn)/\(st.rawValue)", rates: r,
                                 section: section(.backsplash, tile: tile(.ceramic, .mosaic, .runningBond, style: st), sqft: 30)))
            }
            for (w, l) in [(1.0, 1.0), (2, 2), (4, 4), (6, 6), (4, 12), (12, 12), (12, 24), (16, 32), (24, 24),
                           (24, 48), (32, 32), (48, 48), (48, 96), (12, 0), (0, 12)] {
                out.append(.init(name: "sizeadder/\(rn)/\(w)x\(l)", rates: r,
                                 section: section(.floor, tile: tile(.ceramic, .rectangle, .straightStacked, w: w, l: l), sqft: 200)))
            }
        }

        // 4. Ceilings, separate shower floor and ceiling tiles.
        for (rn, r) in rateSets {
            for c in [0.0, 10, 24, 30, 60] {
                for a in [Area.shower, .tub, .wall] {
                    var s = section(a, tile: main, sqft: 70, showerWalls: 90, showerFloor: 16, ceiling: c)
                    out.append(.init(name: "ceiling/\(rn)/\(a.rawValue)/\(c)", rates: r, section: s))
                    s.ceilingTile = tile(.marble, .mosaic, .straightStacked, style: .herringbone)
                    s.showerFloorTile = tile(.porcelain, .hexagon, .straightStacked)
                    out.append(.init(name: "ceilingtile/\(rn)/\(a.rawValue)/\(c)", rates: r, section: s))
                }
            }
        }

        // 5. Walls with their own tiles, below and above the shared minimum.
        let wallTiles = [tiles[1].1, tiles[2].1, tiles[5].1, tiles[7].1]
        for (rn, r) in rateSets {
            for a in [Area.shower, .tub] {
                for sizes in [[20.0, 20, 20], [30, 40, 40], [0, 50, 10], [5, 0, 0], [0, 0, 0], [35, 35, 35, 35]] {
                    var s = section(a, tile: main, sqft: 999, showerWalls: 999, showerFloor: 12)
                    s.walls = sizes.enumerated().map { i, q in
                        TiledWall(name: i == 1 ? "" : "Wall \(["Back", "Left", "Right", "Niche"][i])", sqft: q,
                                  tile: wallTiles[i % wallTiles.count])
                    }
                    out.append(.init(name: "walls/\(rn)/\(a.rawValue)/\(sizes)", rates: r, section: s))
                }
                // Identical tiles must cost what "all the same" costs.
                var same = section(a, tile: main, sqft: 90, showerWalls: 90, showerFloor: 12)
                same.walls = [TiledWall(name: "Back", sqft: 40, tile: main), TiledWall(name: "Left", sqft: 25, tile: main),
                              TiledWall(name: "Right", sqft: 25, tile: main)]
                out.append(.init(name: "wallssame/\(rn)/\(a.rawValue)", rates: r, section: same))
            }
        }

        // 6. Features (never on floors) and bands, borders and inlays.
        for (rn, r) in rateSets.prefix(2) {
            for a in Area.allCases {
                var s = section(a, tile: main, sqft: 60, showerWalls: 60, showerFloor: 12)
                s.features = Features(shelves: 2, niches: 1, footrests: 1, benches: 3)
                s.decoratives = [
                    DecorativeItem(kind: .band, name: "", quantity: 12.5),
                    DecorativeItem(kind: .border, name: "Top", quantity: 7),
                    DecorativeItem(kind: .inlay, name: "Medallion", quantity: 9),
                    DecorativeItem(kind: .band, name: "Empty", quantity: 0),
                ]
                out.append(.init(name: "extras/\(rn)/\(a.rawValue)", rates: r, section: s))
            }
        }

        // 7. Incomplete areas price at nothing.
        var noLayout = section(.wall, tile: main, sqft: 50); noLayout.layout = nil
        var noType = section(.wall, tile: main, sqft: 50); noType.tileType = nil
        var noArea = section(.wall, tile: main, sqft: 50); noArea.area = nil
        var mosaicNoLayout = section(.wall, tile: tiles[7].1, sqft: 50); mosaicNoLayout.layout = nil
        for (n, s) in [("nolayout", noLayout), ("notype", noType), ("noarea", noArea), ("mosaicnolayout", mosaicNoLayout)] {
            out.append(.init(name: "incomplete/\(n)", rates: ownerLike, section: s))
        }
        return out
    }
}
