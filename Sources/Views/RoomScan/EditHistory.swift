import Foundation

/// Undo and redo for the room's model, as whole snapshots (from FabSpecPro's
/// PieceHistory). A drag sends many small changes; they're gathered into one
/// step by `settle` (the editor calls it once things have stopped moving),
/// so one drag or one typed value is one undo.
struct EditHistory<Value: Equatable> {
    private(set) var current: Value
    private var past: [Value] = []
    private var future: [Value] = []
    let limit: Int

    init(_ value: Value, limit: Int = 100) {
        current = value
        self.limit = limit
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// The value now on screen becomes a step (no step if nothing changed).
    mutating func settle(_ value: Value) {
        guard value != current else { return }
        past.append(current)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
        current = value
    }

    /// Back one step; the value now on screen is settled first.
    mutating func undo(from onScreen: Value) -> Value? {
        settle(onScreen)
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        current = previous
        return previous
    }

    mutating func redo(from onScreen: Value) -> Value? {
        settle(onScreen)
        guard let next = future.popLast() else { return nil }
        past.append(current)
        current = next
        return next
    }
}
