import Foundation
import SwiftUI

// MARK: - Keeping copies of saved data

/// Copies of saved data, in Documents/Data Backups, so that nothing the app
/// can't read is ever lost by the next save. Until 2026-10-05 a saved
/// estimates file that failed to read came up as an empty list, and the next
/// save wrote that over the file.
struct DataBackups {
    let folder: URL

    static let standard = DataBackups(folder: FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Data Backups", isDirectory: true))

    /// Keeps data the app could not read, under a name never reused.
    @discardableResult
    func keepUnreadable(_ data: Data, name: String, now: Date = Date()) -> URL? {
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted))
        return write(data, to: "\(name) unreadable \(stamp).json")
    }

    /// One copy a day, taken before the first save of the day, keeping the
    /// newest `keep` days.
    func daily(_ data: Data, name: String, keep: Int = 14, now: Date = Date()) {
        let day = now.formatted(.iso8601.year().month().day())
        let file = folder.appendingPathComponent("\(name) \(day).json")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        write(data, to: file.lastPathComponent)
        let old = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let days = old.filter { $0.hasPrefix("\(name) 2") && !$0.contains("unreadable") }.sorted()
        for f in days.dropLast(keep) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(f))
        }
    }

    @discardableResult
    private func write(_ data: Data, to fileName: String) -> URL? {
        let url = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .withoutOverwriting)
            return url
        } catch {
            print("Backup failed:", error)
            return nil
        }
    }
}

/// Decodes one element of a list, so a single unreadable estimate doesn't
/// take the rest of the list with it.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

final class SavedEstimatesStore: ObservableObject {
    /// Both designs share one list, so neither can save over the other's.
    static let shared = SavedEstimatesStore()

    @Published private(set) var items: [SavedEstimate] = []
    /// Set when some or all of the saved file could not be read. The file
    /// as it was is kept in Data Backups before anything is saved.
    @Published private(set) var loadProblem: String? = nil

    private let fileURL: URL
    private let backups: DataBackups

    init(fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SavedEstimates.json"),
         backups: DataBackups = .standard) {
        self.fileURL = fileURL
        self.backups = backups
        load()
    }

    /// True when the saved file holds something that couldn't be read and
    /// no copy of it could be kept: saving would lose it, so nothing is saved.
    private(set) var savingBlocked = false

    func load() {
        loadProblem = nil
        savingBlocked = false
        items = []
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else {
            loadProblem = "The saved estimates file couldn't be opened, so nothing will be saved over it."
            savingBlocked = true
            return
        }
        if data.isEmpty { return }
        let list = try? JSONDecoder().decode([Lossy<SavedEstimate>].self, from: data)
        items = list?.compactMap(\.value) ?? []
        let lost = list.map { $0.count - items.count }
        guard lost != 0 else { return }
        let what = lost.map { "\($0) saved estimate\($0 == 1 ? "" : "s") couldn't be read." }
            ?? "The saved estimates couldn't be read."
        if backups.keepUnreadable(data, name: "SavedEstimates") != nil {
            loadProblem = what + " A copy of the file as it was is kept in Data Backups."
        } else {
            loadProblem = what + " Nothing will be saved over them."
            savingBlocked = true
        }
    }

    private func persist() {
        guard !savingBlocked else {
            print("Not saving: the saved estimates file couldn't be read or copied.")
            return
        }
        if let existing = try? Data(contentsOf: fileURL), !existing.isEmpty {
            backups.daily(existing, name: "SavedEstimates")
        }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Save estimates failed:", error)
        }
    }

    func add(_ e: SavedEstimate) {
        items.insert(e, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }
}

// MARK: - Store (Persistence)

final class Store: ObservableObject {
    @Published var state: EstimatorState { didSet { save() } }
    @Published var rates: Rates { didSet { saveRates() } }
    @Published var doc: EstimateDocument { didSet { saveDoc() } }
    /// Set when the estimate being worked on was opened from a saved one.
    @Published private(set) var opened: OpenedEstimatePricing? { didSet { saveOpened() } }

    private let stateKey  = "TileRate.state"
    private let ratesKey  = "TileRate.rates"
    private let docKey    = "TileRate.document"
    private let openedKey = "TileRate.openedPricing"

    init() {
        if let s = Self.load(EstimatorState.self, key: stateKey) { state = s } else { state = EstimatorState() }
        if let r = Self.load(Rates.self, key: ratesKey) { rates = r } else { rates = Rates() }
        if let d = Self.load(EstimateDocument.self, key: docKey) { doc = d } else { doc = EstimateDocument() }
        opened = Self.load(OpenedEstimatePricing.self, key: openedKey)
    }

    /// The rates the estimate being worked on is priced with: the ones it
    /// was saved with when it was opened from a saved estimate (until it is
    /// converted), otherwise the current rates. Admin edits `rates`.
    var pricingRates: Rates { opened?.rates ?? rates }

    /// True when the estimate is priced with rates other than the current ones.
    var isPricedWithSavedRates: Bool { opened?.rates != nil }

    func reset() {
        state  = EstimatorState()
        doc    = EstimateDocument()
        opened = nil
    }

    /// Puts a saved estimate's document in place, priced as it was saved.
    func open(_ e: SavedEstimate) {
        doc = e.document
        opened = OpenedEstimatePricing(savedAt: e.createdAt, rates: e.rates)
    }

    /// From now on the estimate is priced with the current rates.
    func convertToCurrentPricing() {
        opened = nil
    }

    private func save()     { Self.persist(state, key: stateKey) }
    private func saveRates(){ Self.persist(rates, key: ratesKey) }
    private func saveDoc()  { Self.persist(doc,   key: docKey) }
    private func saveOpened() {
        if let opened { Self.persist(opened, key: openedKey) }
        else { UserDefaults.standard.removeObject(forKey: openedKey) }
    }

    private static func persist<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        // A daily copy of the rates as they were, before today's changes.
        if key == "TileRate.rates", let old = UserDefaults.standard.data(forKey: key) {
            DataBackups.standard.daily(old, name: "Rates")
        }
        UserDefaults.standard.set(data, forKey: key)
    }
    /// What was saved, or nil. Saved data that can't be read is copied to
    /// Data Backups first, since the defaults will be saved over it.
    private static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        DataBackups.standard.keepUnreadable(data, name: key)
        return nil
    }
}
