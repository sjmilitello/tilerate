import PhotosUI
import SwiftUI

/// My Tiles (owner, 2026-10-18): tiles the owner has named, kept on the phone
/// for every estimate with everything about them — material, shape, size,
/// layout and how they look — and the tiles used most recently. Kept in
/// UserDefaults; a list that won't read is copied aside before it's replaced.
final class TileLibrary: ObservableObject {
    static let shared = TileLibrary()

    private let defaults: UserDefaults
    private static let mineKey = "tileLibrary.mine.v1"
    private static let recentKey = "tileLibrary.recent.v1"
    static let recentLimit = 8

    @Published private(set) var mine: [TileChoice]
    @Published private(set) var recent: [TileChoice]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mine = Self.load(Self.mineKey, from: defaults)
        recent = Self.load(Self.recentKey, from: defaults)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> [TileChoice] {
        guard let data = defaults.data(forKey: key) else { return [] }
        if let list = try? JSONDecoder().decode([TileChoice].self, from: data) { return list }
        defaults.set(data, forKey: key + ".unreadable")
        return []
    }

    private func store(_ list: [TileChoice], _ key: String) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }

    /// Saves a tile under a name; one already called that is replaced.
    func save(_ tile: TileChoice, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var named = tile
        var a = named.appearance ?? TileAppearance()
        a.name = name
        named.appearance = a
        if let i = mine.firstIndex(where: { $0.appearance?.name?.caseInsensitiveCompare(name) == .orderedSame }) {
            mine[i] = named
        } else {
            mine.append(named)
        }
        store(mine, Self.mineKey)
    }

    func rename(at i: Int, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mine.indices.contains(i), !name.isEmpty else { return }
        var a = mine[i].appearance ?? TileAppearance()
        a.name = name
        mine[i].appearance = a
        store(mine, Self.mineKey)
    }

    func delete(at i: Int) {
        guard mine.indices.contains(i) else { return }
        mine.remove(at: i)
        store(mine, Self.mineKey)
    }

    /// A tile chosen: first in Recently used, once.
    func used(_ tile: TileChoice) {
        var list = recent.filter { !Self.sameLook($0, tile) }
        list.insert(tile, at: 0)
        recent = Array(list.prefix(Self.recentLimit))
        store(recent, Self.recentKey)
    }

    /// Two tiles the same in everything but their name.
    static func sameLook(_ a: TileChoice, _ b: TileChoice) -> Bool {
        var x = a, y = b
        x.appearance?.name = nil
        y.appearance?.name = nil
        if x.appearance == TileAppearance() { x.appearance = nil }
        if y.appearance == TileAppearance() { y.appearance = nil }
        return x == y
    }
}

/// Choosing how a tile looks (owner's design, 2026-10-18), after the stone
/// picker: what prices it on top (material, shape, size, layout — Change ›
/// goes back to them), a preview of the tile laid, its name (optional: a
/// named tile is kept in My Tiles), the colours for the tile, a marble or
/// stone look's veins and the grout (Laticrete PermaColor by name) — pinned
/// with the preview — then the look, its pattern, the variation, the finish,
/// My Tiles, Recently used and a photo of the real tile.
struct TilePickerSheet: View {
    let title: String
    let start: TileChoice
    let onDone: (TileChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = TileLibrary.shared
    @State private var tile: TileChoice
    @State private var nameText: String
    @State private var well: Well = .tile
    @State private var family: String? = nil
    @State private var renaming: Int? = nil
    @State private var newName = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var takingPhoto = false

    enum Well { case tile, accent, grout }

    init(title: String, start: TileChoice, onDone: @escaping (TileChoice) -> Void) {
        self.title = title
        self.start = start
        self.onDone = onDone
        _tile = State(initialValue: start)
        _nameText = State(initialValue: start.appearance?.name ?? "")
    }

    private var look: TileAppearance { tile.appearance ?? TileAppearance() }
    private func edit(_ change: (inout TileAppearance) -> Void) {
        var a = look
        change(&a)
        tile.appearance = a
    }
    private var typedName: String { nameText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var savedWithName: TileChoice? {
        typedName.isEmpty ? nil : library.mine.first { $0.appearance?.name?.caseInsensitiveCompare(typedName) == .orderedSame }
    }
    /// The tile's colour as shown: its own, else the material's.
    private var faceHex: String { look.colour ?? StonePatterns.hex(TilePattern.color(tile.tileType)) }
    private var usesAccent: Bool { look.look == .marble || look.look == .stone }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        priceRow
                        NDTileSwatch(tile: tile, spanIn: max(24, min(72, 6 * TilePattern.drawnSize(tile).0)))
                            .frame(height: 130)
                        nameField
                        colours(width: geo.size.width - 32)
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
                    .background(ND.ground)
                    Divider().overlay(ND.border)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            looks(width: geo.size.width - 32)
                            if let l = look.look, !l.patterns.isEmpty { lookPatterns(l) }
                            chips("Variation (the V rating on the box)",
                                  [(1, "V1 Even"), (2, "V2 Slight"), (3, "V3 Some"), (4, "V4 Strong")],
                                  look.variation) { v in edit { $0.variation = $0.variation == v ? nil : v } }
                            chips("Finish", TileAppearance.Finish.allCases.map { ($0, $0.name) }, look.finish) { f in
                                edit { $0.finish = $0.finish == f ? nil : f }
                            }
                            if !library.mine.isEmpty { myTiles }
                            if !library.recent.isEmpty { recentRow }
                            photoRow
                        }
                        .padding(16)
                    }
                }
            }
            .background(ND.ground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(finish()); dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let i = renaming { library.rename(at: i, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       let id = TilePhotos.save(image) { tile.photoID = id }
                    pickedPhoto = nil
                }
            }
            .sheet(isPresented: $takingPhoto) {
                CameraPicker { image in
                    if let image, let id = TilePhotos.save(image) { tile.photoID = id }
                    takingPhoto = false
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The tile as chosen: named, it's kept in My Tiles; blank, it's this area's alone.
    private func finish() -> TileChoice {
        var t = tile
        var a = t.appearance ?? TileAppearance()
        a.name = typedName.isEmpty ? nil : typedName
        t.appearance = a == TileAppearance() ? nil : a
        if !typedName.isEmpty { library.save(t, name: typedName) }
        if t.appearance != nil || t.photoID != nil { library.used(t) }
        return t
    }

    /// What prices it, with the way back to change it.
    private var priceRow: some View {
        Button { onDone(finish()); dismiss() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.ndSummary)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(ND.text).lineLimit(1).minimumScaleFactor(0.8)
                    Text("Sets the price").font(.system(size: 12)).foregroundStyle(ND.muted)
                }
                Spacer()
                Text("Change ›").font(.system(size: 14, weight: .semibold)).foregroundStyle(ND.link)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(ND.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(tile.photoID != nil ? "Name this tile to keep it" : "Name it (optional), e.g. Cloé Sage 2.5×8", text: $nameText)
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                if let saved = savedWithName {
                    if TileLibrary.sameLook(saved, tile) {
                        Label("In My Tiles", systemImage: "star.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(ND.link)
                    } else {
                        Button("Use the saved one") { pick(saved) }.font(.system(size: 13, weight: .semibold)).tint(ND.link)
                    }
                }
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(ND.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ND.border))
            Text(caption).font(.system(size: 12)).foregroundStyle(ND.muted).lineLimit(2)
        }
    }

    private var caption: String {
        var parts: [String] = [(look.look ?? .solid).name]
        if let p = look.lookPattern { parts.append(p.name.lowercased()) }
        if let f = look.finish { parts.append(f.name.lowercased()) }
        if let v = look.variation { parts.append("V\(v)") }
        if let g = look.groutName { parts.append("\(g) grout") }
        var text = parts.joined(separator: " · ")
        if let saved = savedWithName, !TileLibrary.sameLook(saved, tile) { text += ". Done updates \(saved.appearance?.name ?? typedName) in My Tiles." }
        else if typedName.isEmpty { text += ". Name it to keep it in My Tiles." }
        else { text += ". Kept in My Tiles." }
        return text
    }

    private func pick(_ t: TileChoice) {
        tile = t
        nameText = t.appearance?.name ?? ""
    }

    // MARK: Colours

    private var current: String? {
        switch well {
        case .tile: faceHex
        case .accent: look.accent
        case .grout: look.grout
        }
    }

    @ViewBuilder
    private func colours(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            wellButton(.tile, "Tile", faceHex)
            if usesAccent { wellButton(.accent, "Veins", look.accent) }
            wellButton(.grout, "Grout", look.grout)
        }
        if well == .grout {
            groutColours(width: width)
        } else {
            let chosen = current?.uppercased()
            let families = TilePalette.families
            let open = family.flatMap { f in families.contains { $0.name == f } ? f : nil }
                ?? families.first { $0.colours.contains(chosen ?? "") }?.name ?? families[0].name
            familyButtons(families.map { ($0.name, $0.colours) }, open: open, width: width)
            colourRow((families.first { $0.name == open }?.colours ?? []).map { ($0, nil as String?) }, chosen: chosen, width: width) { hex, _ in
                setColour(hex)
            }
        }
    }

    private func setColour(_ hex: String) {
        edit { a in
            switch well {
            case .tile: a.colour = hex
            case .accent: a.accent = hex
            case .grout: a.grout = hex; a.groutName = nil
            }
        }
    }

    @ViewBuilder
    private func groutColours(width: CGFloat) -> some View {
        let chosen = look.grout?.uppercased()
        let families = TilePalette.grouts
        let open = family.flatMap { f in families.contains { $0.name == f } ? f : nil }
            ?? families.first { $0.colours.contains { $0.hex == chosen } }?.name ?? families[0].name
        familyButtons(families.map { ($0.name, $0.colours.map(\.hex)) }, open: open, width: width)
        colourRow((families.first { $0.name == open }?.colours ?? []).map { ($0.hex, $0.name as String?) }, chosen: chosen, width: width) { hex, name in
            edit { a in
                a.grout = hex
                a.groutName = name.map { "\(TilePalette.groutMaker) \($0)" }
            }
        }
        Text(look.groutName.map { "Grout: \($0). On screen it's a guide; grout dries to its own shade." }
             ?? "Grout: PermaColor colours, or + for any colour.")
            .font(.system(size: 12)).foregroundStyle(ND.muted)
    }

    private func familyButtons(_ families: [(String, [String])], open: String, width: CGFloat) -> some View {
        let gap: CGFloat = 5
        let n = CGFloat(families.count)
        let w = (width - (n - 1) * gap) / n
        return HStack(alignment: .top, spacing: gap) {
            ForEach(families, id: \.0) { name, cols in
                let on = name == open
                Button { family = name } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 0) {
                            ForEach(cols, id: \.self) { Rectangle().fill(Color(uiColor: StonePatterns.uiColor($0))) }
                        }
                        .frame(width: w, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).inset(by: -3).stroke(on ? ND.link : .clear, lineWidth: 2.5))
                        Text(TilePalette.shortName(name)).font(.system(size: 10, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? ND.text : ND.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: w)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name) colours")
            }
        }
        .onChange(of: well) { _, _ in family = nil }
    }

    /// One family's colours in a row (grout with its names under), and + for any colour.
    private func colourRow(_ items: [(String, String?)], chosen: String?, width: CGFloat,
                           pick: @escaping (String, String?) -> Void) -> some View {
        let gap: CGFloat = 6
        let slots = CGFloat(items.count + 1)
        let cw = min(54, (width - (slots - 1) * gap) / slots)
        let named = items.contains { $0.1 != nil }
        return HStack(alignment: .top, spacing: gap) {
            ForEach(items, id: \.0) { hex, name in
                Button { pick(hex, name) } label: {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: StonePatterns.uiColor(hex)))
                            .frame(width: cw, height: named ? 40 : 46)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(chosen == hex ? ND.link : Color.white.opacity(0.08), lineWidth: chosen == hex ? 3 : 1))
                        if let name {
                            Text(name).font(.system(size: 9)).foregroundStyle(ND.muted).multilineTextAlignment(.center)
                                .lineLimit(2).minimumScaleFactor(0.8).frame(width: cw + gap)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name ?? hex)
            }
            ColorPicker(selection: Binding(
                get: { Color(uiColor: StonePatterns.uiColor(current ?? faceHex)) },
                set: { setColour(StonePatterns.hex(UIColor($0))) }), supportsOpacity: false) { EmptyView() }
                .labelsHidden()
                .frame(width: cw, height: named ? 40 : 46)
            Spacer(minLength: 0)
        }
    }

    private func wellButton(_ w: Well, _ label: String, _ hex: String?) -> some View {
        let on = well == w
        return Button { well = w } label: {
            HStack(spacing: 8) {
                Circle().fill(hex.map { Color(uiColor: StonePatterns.uiColor($0)) } ?? .clear)
                    .overlay(Circle().stroke(ND.border))
                    .overlay(hex == nil ? Image(systemName: "circle.dashed").foregroundStyle(ND.muted) : nil)
                    .frame(width: 22, height: 22)
                Text(label).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(ND.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 44).frame(maxWidth: .infinity)
            .background(ND.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? ND.link : ND.border, lineWidth: on ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Look

    private func looks(width: CGFloat) -> some View {
        let gap: CGFloat = 6
        let n = CGFloat(TileAppearance.Look.allCases.count)
        let cell = (width - (n - 1) * gap) / n
        return VStack(alignment: .leading, spacing: 8) {
            NDLabel("Look")
            HStack(alignment: .top, spacing: gap) {
                ForEach(TileAppearance.Look.allCases) { l in
                    let on = (look.look ?? .solid) == l
                    Button {
                        edit { a in
                            a.look = l == .solid ? nil : l
                            if !l.patterns.isEmpty, a.pattern.map(l.patterns.contains) != true { a.pattern = l.patterns[0] }
                        }
                        if !(l == .marble || l == .stone), well == .accent { well = .tile }
                    } label: {
                        VStack(spacing: 4) {
                            NDTileSwatch(tile: withLook(l), spanIn: max(8, min(18, TilePattern.drawnSize(tile).0 * 1.2)))
                                .frame(width: cell, height: cell)
                                .overlay(RoundedRectangle(cornerRadius: 10).inset(by: -3).stroke(on ? ND.link : .clear, lineWidth: 3))
                            Text(l.name).font(.system(size: 10)).foregroundStyle(ND.text).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// This tile with another look, for its swatch.
    private func withLook(_ l: TileAppearance.Look, pattern: StoneAppearance.Pattern? = nil) -> TileChoice {
        var t = tile
        t.photoID = nil
        var a = look
        a.look = l
        a.pattern = pattern ?? (l.patterns.first)
        if l == .marble, a.colour == nil { a.colour = "#F4F2EE" }
        t.appearance = a
        return t
    }

    private func lookPatterns(_ l: TileAppearance.Look) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NDLabel("\(l.name) look")
            HStack(alignment: .top, spacing: 10) {
                ForEach(l.patterns) { p in
                    let on = look.lookPattern == p
                    Button { edit { $0.pattern = p } } label: {
                        VStack(spacing: 4) {
                            NDTileSwatch(tile: withLook(l, pattern: p), spanIn: max(10, min(24, TilePattern.drawnSize(tile).0 * 1.5)))
                                .frame(width: 72, height: 72)
                                .overlay(RoundedRectangle(cornerRadius: 10).inset(by: -3).stroke(on ? ND.link : .clear, lineWidth: 3))
                            Text(p.name).font(.system(size: 11)).foregroundStyle(ND.text)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chips<T: Equatable>(_ label: String, _ options: [(T, String)], _ chosen: T?, pick: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NDLabel(label)
            NDFlow {
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                    NDChip(title: o.1, selected: chosen == o.0) { pick(o.0) }
                }
            }
        }
    }

    // MARK: My Tiles, recent, photo

    private var myTiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("My Tiles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(library.mine.enumerated()), id: \.offset) { i, t in
                        Button { pick(t) } label: {
                            VStack(spacing: 6) {
                                NDTileSwatch(tile: t).frame(width: 72, height: 72)
                                    .overlay(RoundedRectangle(cornerRadius: 10).inset(by: -3)
                                        .stroke(TileLibrary.sameLook(t, tile) && typedName == (t.appearance?.name ?? "") ? ND.link : .clear, lineWidth: 3))
                                Text(t.appearance?.name ?? "").font(.system(size: 12)).foregroundStyle(ND.secondary)
                                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 80)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { newName = t.appearance?.name ?? ""; renaming = i } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { library.delete(at: i) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .padding(4)
            }
            Text("Touch and hold one to rename or delete it. Picking one sets its material, size and layout too.")
                .font(.system(size: 12)).foregroundStyle(ND.muted)
        }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Recently used")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(library.recent.enumerated()), id: \.offset) { _, t in
                        Button { pick(t) } label: { NDTileSwatch(tile: t).frame(width: 60, height: 60) }.buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
        }
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Photo of the tile")
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(tile.photoID == nil ? "Choose photo" : "Change photo", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(NDSecondaryButtonStyle())
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { takingPhoto = true } label: { Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity) }
                        .buttonStyle(NDSecondaryButtonStyle())
                }
            }
            if tile.photoID != nil {
                Button(role: .destructive) { tile.photoID = nil } label: { Label("Remove photo", systemImage: "trash") }
                    .font(.system(size: 14, weight: .semibold))
            }
            Text("The photo becomes each tile's face. Name it and it joins My Tiles too.")
                .font(.system(size: 12)).foregroundStyle(ND.muted)
        }
    }
}

/// "Colour, look & grout": opens the tile picker for a tile (owner, 2026-10-18).
struct TileLookRow: View {
    let title: String
    let tile: TileChoice
    let apply: (TileChoice) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                NDTileSwatch(tile: tile).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.appearance?.name ?? "Colour, look & grout").font(.system(size: 16, weight: .semibold)).foregroundStyle(ND.text)
                    Text(summary).font(.system(size: 13)).foregroundStyle(ND.muted).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(ND.muted)
            }
            .padding(12)
            .background(ND.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ND.border))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { TilePickerSheet(title: title, start: tile, onDone: apply) }
    }

    private var summary: String {
        guard let a = tile.appearance else { return "Choose its colour, look, grout, variation and finish" }
        var parts = [(a.look ?? .solid).name]
        if let f = a.finish { parts.append(f.name.lowercased()) }
        if let v = a.variation { parts.append("V\(v)") }
        parts.append(a.groutName.map { "\($0) grout" } ?? (a.grout != nil ? "custom grout" : "usual grout"))
        return parts.joined(separator: " · ")
    }
}
