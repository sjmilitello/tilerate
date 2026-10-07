import Foundation
@testable import TileRate_Installation_Estimator

// Areas whose estimate wording was recorded on 2026-10-06 (WordingGolden.swift)
// before the wording became templates. The standard templates must reproduce
// every sentence exactly. Never edit a case: add new ones under new names.

enum WordingCases {
    static var all: [(name: String, section: EstimateSection)] {
        var out: [(String, EstimateSection)] = []
        func t(_ type: TileType, _ size: TileSize, _ layout: Layout, w: Double? = nil, l: Double? = nil,
               style: MosaicStyle? = nil, pieces: [TilePiece] = []) -> TileChoice {
            PricingCases.tile(type, size, layout, w: w, l: l, style: style, pieces: pieces)
        }

        // Every pricing case's area: shapes, sizes, layouts, mosaics, walls,
        // ceilings, features and bands.
        for c in PricingCases.all { out.append(("pricing/" + c.name, c.section)) }

        // Sizes written different ways.
        for (w, l) in [(12.0, 24.0), (12.5, 24), (3, 0), (0, 6), (2.25, 2.25), (48, 96)] {
            out.append(("size/\(w)x\(l)", PricingCases.section(.floor, tile: t(.porcelain, .rectangle, .runningBond, w: w, l: l), sqft: 80)))
        }

        // A room name on the section itself.
        var named = PricingCases.section(.wall, tile: t(.ceramic, .square, .straightStacked, w: 4, l: 4), sqft: 30)
        named.roomName = "Kitchen"
        out.append(("roomname", named))

        // Feature counts, singular and plural, and every decorative wording.
        for (i, counts) in [(1, 1, 1, 1), (2, 3, 0, 2), (0, 0, 4, 0)].enumerated() {
            var s = PricingCases.section(.shower, tile: t(.porcelain, .rectangle, .runningBond, w: 12, l: 24),
                                         showerWalls: 80, showerFloor: 15)
            s.features = Features(shelves: counts.0, niches: counts.1, footrests: counts.2, benches: counts.3)
            out.append(("features/\(i)", s))
        }
        var deco = PricingCases.section(.shower, tile: t(.porcelain, .rectangle, .runningBond, w: 12, l: 24),
                                        showerWalls: 80, showerFloor: 15, ceiling: 20)
        deco.decoratives = [
            DecorativeItem(kind: .band, name: "Chair rail", quantity: 10, tile: t(.marble, .rectangle, .straightStacked, w: 3, l: 12),
                           locations: ["Back Wall", "Left Wall"]),
            DecorativeItem(kind: .border, name: "", quantity: 6, tile: t(.glass, .mosaic, .straightStacked, style: .pennyRound),
                           locations: ["Ceiling"]),
            DecorativeItem(kind: .inlay, name: "", quantity: 4, tile: t(.porcelain, .hexagon, .straightStacked),
                           locations: ["Shower Floor"]),
            DecorativeItem(kind: .band, name: "Unplaced", quantity: 3, tile: t(.ceramic, .square, .straightStacked)),
        ]
        out.append(("decoratives", deco))

        // Walls each with their own tile, and every surface with its own tile.
        var walls = PricingCases.section(.shower, tile: t(.porcelain, .rectangle, .runningBond, w: 12, l: 24),
                                         showerWalls: 90, showerFloor: 15, ceiling: 20)
        walls.walls = [TiledWall(name: "Back", sqft: 40, tile: t(.marble, .rectangle, .herringbone, w: 3, l: 12)),
                       TiledWall(name: "", sqft: 25, tile: t(.porcelain, .rectangle, .runningBond, w: 12, l: 24)),
                       TiledWall(name: "Right", sqft: 0, tile: t(.porcelain, .square, .straightStacked, w: 6, l: 6))]
        out.append(("walls/split", walls))
        var allOwn = walls
        allOwn.showerFloorTile = t(.porcelain, .mosaic, .straightStacked, style: .hexagon)
        allOwn.ceilingTile = t(.porcelain, .rectangle, .multiTile,
                               pieces: [TilePiece(shape: .rectangle, widthIn: 12, lengthIn: 24),
                                        TilePiece(shape: .hexagon, widthIn: 6, lengthIn: 6)])
        out.append(("walls/allown", allOwn))
        var allOwnFeatures = allOwn
        allOwnFeatures.features = Features(niches: 1)
        out.append(("walls/allownfeatures", allOwnFeatures))
        var tubSplit = PricingCases.section(.tub, tile: t(.ceramic, .rectangle, .runningBond, w: 3, l: 6), sqft: 60, ceiling: 10)
        tubSplit.walls = [TiledWall(name: "Back", sqft: 30, tile: t(.ceramic, .rectangle, .runningBond, w: 3, l: 6))]
        out.append(("tub/split", tubSplit))

        // Empty measurements: the default surfaces.
        for a in Area.allCases {
            out.append(("empty/\(a.rawValue)", PricingCases.section(a, tile: t(.porcelain, .rectangle, .runningBond, w: 12, l: 24))))
        }

        // Nothing chosen yet.
        out.append(("blank", EstimateSection()))
        var onlyArea = EstimateSection(); onlyArea.area = .floor; onlyArea.measurements.sqft = 50
        out.append(("onlyarea", onlyArea))
        return out
    }
}
