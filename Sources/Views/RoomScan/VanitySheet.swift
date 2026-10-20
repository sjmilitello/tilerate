import SwiftUI

/// One vanity (owner, 2026-10-19): its size, sinks and top overhang; its
/// stone; its backsplash — stone, tile or none, its height, and which of the
/// walls it touches get it; and Move, Turn, Remove.
struct VanitySheet: View {
    @Binding var vanity: ScannedRoom.Vanity
    let room: ScannedRoom
    let onMove: () -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickingStone = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        InchField(title: "Width", inches: Binding(get: { vanity.rect.widthFt * 12 }, set: {
                            vanity.rect.widthFt = max(12, $0) / 12
                            vanity.fitSinks()
                        }), applyWhenDone: true)
                        InchField(title: "Depth", inches: Binding(get: { vanity.rect.depthFt * 12 }, set: {
                            vanity.rect.depthFt = max(12, $0) / 12
                        }), applyWhenDone: true)
                        InchField(title: "Height", inches: $vanity.heightIn, applyWhenDone: true)
                    }
                    Stepper("Sinks: \(vanity.sinks)", value: Binding(get: { vanity.sinks }, set: {
                        vanity.sinks = $0
                        vanity.sinksTyped = true
                    }), in: 0...3)
                    InchField(title: "Top past the cabinet (open sides)", inches: $vanity.overhangIn, applyWhenDone: true)
                } header: { Text("Cabinet and top") } footer: {
                    Text("The stone top runs past the cabinet on its open sides. It's charged as materials — its square feet and each sink cut-out, prices in Admin → Stone pieces → Vanity — when stone material is listed as its own line.")
                }
                Section("Stone") {
                    Button { pickingStone = true } label: {
                        HStack {
                            Text("Top and stone backsplash")
                            Spacer()
                            Text(vanity.top?.name ?? (vanity.top == nil ? "White marble" : "Chosen")).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Picker("Backsplash", selection: $vanity.splash) {
                        ForEach(ScannedRoom.Vanity.Splash.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if vanity.splash != .none {
                        InchField(title: "Height", inches: $vanity.splashHeightIn, applyWhenDone: true)
                        let walls = room.wallsTouching(vanity)
                        if walls.isEmpty {
                            Text("It isn't against a wall.").foregroundStyle(.secondary)
                        }
                        ForEach(walls) { w in
                            Toggle(room.name(of: w), isOn: Binding(get: { vanity.splashWalls.contains(w.id) }, set: { on in
                                vanity.splashWalls.removeAll { $0 == w.id }
                                if on { vanity.splashWalls.append(w.id) }
                            }))
                        }
                    }
                } header: { Text("Backsplash") } footer: {
                    Text(vanity.splash == .tile
                         ? "Tile: in the Vanity area's tile, at your backsplash price."
                         : vanity.splash == .stone ? "Stone: on its own line, \"Stone vanity backsplash\", at Admin's price, and in the stone cutlist."
                         : "No backsplash.")
                }
                Section {
                    Button { dismiss(); onMove() } label: { Label("Move: tap where it goes", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                    Button { vanity.rect = vanity.rect.turnedInPlace } label: { Label("Turn", systemImage: "rotate.right") }
                    Button(role: .destructive) { dismiss(); onRemove() } label: { Label("Remove the vanity", systemImage: "trash") }
                }
            }
            .navigationTitle("Vanity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $pickingStone) {
                StonePickerSheet(title: "Vanity top", start: vanity.top ?? .standard) { look in
                    vanity.top = look
                }
            }
        }
    }
}
