import Foundation

/// An area's stone for drawing: which pieces are stone (and which bare,
/// "none#<key>", `AreaTakeoff.drawnFinishKeys`), and how each looks — its
/// own stone, else the area's (owner, 2026-10-17).
struct StoneKeys: Equatable {
    var keys: Set<String> = []
    var area: StoneAppearance = .standard
    var looks: [String: StoneAppearance] = [:]

    func contains(_ key: String) -> Bool { keys.contains(key) }
    func look(_ key: String) -> StoneAppearance { looks[key] ?? area }

    /// Several areas' together, each key keeping its own area's look (keys
    /// with a wall's or item's id in them are the same in every area).
    static func merged(_ sets: [StoneKeys]) -> StoneKeys {
        var out = StoneKeys()
        for s in sets {
            out.keys.formUnion(s.keys)
            for k in s.keys where out.looks[k] == nil { out.looks[k] = s.look(k) }
        }
        return out
    }
}

extension StoneKeys: ExpressibleByArrayLiteral {
    /// Stone keys in the standard look.
    init(arrayLiteral keys: String...) { self.init(keys: Set(keys)) }
}

extension AreaTakeoff {
    /// The area's stone: its own, else the standard white marble.
    var areaStone: StoneAppearance { stoneLook ?? .standard }

    /// A piece's stone: its own, else the area's.
    func stone(for key: String) -> StoneAppearance { stoneLooks[key] ?? areaStone }

    /// A corner shelf's, seat's or footrest's key for its stone.
    static func cornerKey(_ item: Item) -> String { "corner:\(item.id)" }

    /// For drawing: these pieces' stone and bare ones, with their looks.
    func stoneKeys(_ pieces: [TrimPiece]) -> StoneKeys {
        StoneKeys(keys: Self.drawnFinishKeys(pieces), area: areaStone, looks: stoneLooks)
    }
}
