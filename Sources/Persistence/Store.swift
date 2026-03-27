import Foundation
import SwiftUI

final class SavedEstimatesStore: ObservableObject {
    @Published private(set) var items: [SavedEstimate] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("SavedEstimates.json")
    }()

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { items = []; return }
        items = (try? JSONDecoder().decode([SavedEstimate].self, from: data)) ?? []
    }

    private func persist() {
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

    private let stateKey = "TileRate.state"
    private let ratesKey = "TileRate.rates"
    private let docKey   = "TileRate.document"

    init() {
        if let s = Self.load(EstimatorState.self, key: stateKey) { state = s } else { state = EstimatorState() }
        if let r = Self.load(Rates.self, key: ratesKey) { rates = r } else { rates = Rates() }
        if let d = Self.load(EstimateDocument.self, key: docKey) { doc = d } else { doc = EstimateDocument() }
    }

    func reset() {
        state = EstimatorState()
        doc   = EstimateDocument()
    }

    private func save()     { Self.persist(state, key: stateKey) }
    private func saveRates(){ Self.persist(rates, key: ratesKey) }
    private func saveDoc()  { Self.persist(doc,   key: docKey) }

    private static func persist<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
    private static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
