import Foundation

/// My Stones (owner, 2026-10-17): stones the owner has named, kept on the
/// phone for every estimate, and the stones used most recently. Kept in
/// UserDefaults; a list that won't read is copied aside before it's replaced.
final class StoneLibrary: ObservableObject {
    static let shared = StoneLibrary()

    private let defaults: UserDefaults
    private static let mineKey = "stoneLibrary.mine.v1"
    private static let recentKey = "stoneLibrary.recent.v1"
    static let recentLimit = 8

    @Published private(set) var mine: [StoneAppearance]
    @Published private(set) var recent: [StoneAppearance]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mine = Self.load(Self.mineKey, from: defaults)
        recent = Self.load(Self.recentKey, from: defaults)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> [StoneAppearance] {
        guard let data = defaults.data(forKey: key) else { return [] }
        if let list = try? JSONDecoder().decode([StoneAppearance].self, from: data) { return list }
        // Unreadable: keep it as it was, so nothing is lost.
        defaults.set(data, forKey: key + ".unreadable")
        return []
    }

    private func store(_ list: [StoneAppearance], _ key: String) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }

    /// Saves a stone to My Stones under a name; one already called that is replaced.
    func save(_ look: StoneAppearance, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var named = look
        named.name = name
        if let i = mine.firstIndex(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) {
            mine[i] = named
        } else {
            mine.append(named)
        }
        store(mine, Self.mineKey)
    }

    func rename(at i: Int, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mine.indices.contains(i), !name.isEmpty else { return }
        mine[i].name = name
        store(mine, Self.mineKey)
    }

    func delete(at i: Int) {
        guard mine.indices.contains(i) else { return }
        mine.remove(at: i)
        store(mine, Self.mineKey)
    }

    /// A stone chosen: first in Recently used, once.
    func used(_ look: StoneAppearance) {
        var list = recent.filter { !$0.looksLike(look) }
        list.insert(look, at: 0)
        recent = Array(list.prefix(Self.recentLimit))
        store(recent, Self.recentKey)
    }
}
