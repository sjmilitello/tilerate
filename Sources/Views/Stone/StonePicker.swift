import PhotosUI
import SwiftUI

/// A stone drawn as a swatch, rendered off the main thread the first time.
struct StoneSwatch: View {
    let look: StoneAppearance
    var pixels: Int = 160
    /// Polished stone gets a soft reflection.
    var showFinish: Bool = false
    @State private var image: UIImage?

    init(look: StoneAppearance, pixels: Int = 160, showFinish: Bool = false) {
        self.look = look
        self.pixels = pixels
        self.showFinish = showFinish
        _image = State(initialValue: look.photoID == nil
                       ? StonePatterns.cachedPattern(look, pixels: pixels).map { StonePatterns.turned($0, look) } : nil)
    }

    var body: some View {
        ZStack {
            Color(uiColor: StonePatterns.uiColor(look.base))
            if let image {
                Image(uiImage: image).resizable().interpolation(.medium).scaledToFill()
            }
            if showFinish, !look.honed {
                LinearGradient(stops: [.init(color: .clear, location: 0.15), .init(color: .white.opacity(0.22), location: 0.38),
                                       .init(color: .clear, location: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipped()
        .task(id: "\(look.drawingKey)@\(pixels)\(look.runsAcross ? "x" : "")") { image = await render() }
    }

    private func render() async -> UIImage? {
        if let id = look.photoID { return TilePhotos.image(id) }
        if let done = StonePatterns.cachedPattern(look, pixels: pixels) { return StonePatterns.turned(done, look) }
        let l = look, px = pixels
        let made = await Task.detached(priority: .userInitiated) { StonePatterns.patternImage(l, pixels: px) }.value
        return StonePatterns.turned(made, look)
    }
}

/// Choosing how a stone looks (owner's design, 2026-10-17/18): a big
/// preview, its name (optional: a named stone is kept in My Stones and
/// shows on the estimate), the colours for the base, the veins (flecks,
/// bands…) and a second colour — pinned with the preview — then polished or
/// honed, the veins' direction, My Stones, Recently used and the patterns
/// grouped by look (each swatch in its usual colours). Or a photo of the slab.
struct StonePickerSheet: View {
    let title: String
    let start: StoneAppearance
    /// For one piece: the area's stone, which it can follow.
    var areaLook: StoneAppearance? = nil
    var startsFollowingArea = false
    /// The stone chosen; nil when a piece follows the area's.
    let onDone: (StoneAppearance?) -> Void
    /// For one piece: make this the area's stone and every piece follow it.
    var onUseForAll: ((StoneAppearance) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = StoneLibrary.shared
    @State private var look: StoneAppearance
    @State private var follow: Bool
    @State private var well: Well = .base
    /// The name typed: the stone's name on Done, kept in My Stones.
    @State private var nameText: String
    @State private var newName = ""
    @State private var renaming: Int? = nil
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var takingPhoto = false

    enum Well { case base, markings, second }

    init(title: String, start: StoneAppearance, areaLook: StoneAppearance? = nil, startsFollowingArea: Bool = false,
         onUseForAll: ((StoneAppearance) -> Void)? = nil, onDone: @escaping (StoneAppearance?) -> Void) {
        self.onUseForAll = onUseForAll
        self.title = title
        self.start = start
        self.areaLook = areaLook
        self.startsFollowingArea = startsFollowingArea
        self.onDone = onDone
        _look = State(initialValue: start)
        _nameText = State(initialValue: start.name ?? "")
        _follow = State(initialValue: startsFollowingArea && areaLook != nil)
    }

    private var shown: StoneAppearance { follow ? (areaLook ?? look) : look }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                // The stone and its colours stay in view while the rest scrolls
                // (owner, 2026-10-17: the preview scrolled away while choosing colours).
                VStack(alignment: .leading, spacing: 10) {
                    preview
                    nameField
                    colourStrip
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
                .background(ND.ground)
                Divider().overlay(ND.border)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let areaLook { followRow(areaLook) }
                        Picker("Finish", selection: Binding(get: { look.honed }, set: { v in edit { $0.honed = v } })) {
                            Text("Polished").tag(false)
                            Text("Honed").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if shown.photoID == nil, shown.pattern.hasDirection {
                            VStack(alignment: .leading, spacing: 8) {
                                NDLabel("\(shown.pattern.markings) run")
                                Picker("Direction", selection: Binding(get: { shown.across }, set: { v in edit { $0.across = v } })) {
                                    Text("Along the piece").tag(false)
                                    Text("Across").tag(true)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        if !library.mine.isEmpty { myStones }
                        if !library.recent.isEmpty { recentRow }
                        patterns(width: geo.size.width - 32)
                        photoRow
                        if let onUseForAll {
                            Button {
                                onUseForAll(finish())
                                dismiss()
                            } label: {
                                Label("Use this stone for every piece", systemImage: "square.stack.3d.up").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NDSecondaryButtonStyle())
                        }
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
                    Button("Done") {
                        onDone(follow ? nil : finish())
                        dismiss()
                    }
                    .fontWeight(.semibold)
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
                       let id = TilePhotos.save(image) {
                        edit { $0.photoID = id }
                    }
                    pickedPhoto = nil
                }
            }
            .sheet(isPresented: $takingPhoto) {
                CameraPicker { image in
                    if let image, let id = TilePhotos.save(image) { edit { $0.photoID = id } }
                    takingPhoto = false
                }
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Any change makes the stone this piece's own (no longer following the
    /// area's). Its name stays: Done keeps the changes under it.
    private func edit(_ change: (inout StoneAppearance) -> Void) {
        if follow, let areaLook { look = areaLook; nameText = areaLook.name ?? "" }
        follow = false
        change(&look)
    }

    private var typedName: String { nameText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A stone in My Stones already called what's typed.
    private var savedWithName: StoneAppearance? {
        typedName.isEmpty ? nil : library.mine.first { $0.name?.caseInsensitiveCompare(typedName) == .orderedSame }
    }

    /// The stone as chosen: named, it's kept in My Stones (owner, 2026-10-18);
    /// blank, it's this piece's alone.
    private func finish() -> StoneAppearance {
        var l = shown
        if !follow {
            l.name = typedName.isEmpty ? nil : typedName
            if !typedName.isEmpty { library.save(l, name: typedName) }
            library.used(l)
        }
        return l
    }

    /// Name it (optional): what it's called on the estimate, and in My Stones.
    @ViewBuilder
    private var nameField: some View {
        if follow {
            Text(areaLook?.name.map { "Same as the area's stone: \($0)" } ?? "Same as the area's stone")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(ND.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField(look.photoID != nil ? "Name this slab to keep it" : "Name it (optional), e.g. Taj Duna Quartz",
                              text: $nameText)
                        .font(.system(size: 17))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    if let saved = savedWithName {
                        if saved.looksLike(look) {
                            Label("In My Stones", systemImage: "star.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(ND.link)
                        } else {
                            Button("Use the saved one") { pick(saved) }
                                .font(.system(size: 13, weight: .semibold)).tint(ND.link)
                        }
                    }
                }
                .padding(.horizontal, 12).frame(height: 46)
                .background(ND.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ND.border))
                Text(nameHint).font(.system(size: 12)).foregroundStyle(ND.muted)
            }
        }
    }

    private var nameHint: String {
        if typedName.isEmpty { return "\(caption(look)). Name it to keep it in My Stones and show it on the estimate." }
        if let saved = savedWithName, !saved.looksLike(look) { return "\(caption(look)). Done updates \(saved.name ?? typedName) in My Stones." }
        return "\(caption(look)). Kept in My Stones."
    }

    private var preview: some View {
        StoneSwatch(look: shown, pixels: 512, showFinish: true)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "Sweeping · polished · veins along".
    private func caption(_ l: StoneAppearance) -> String {
        var parts = [l.photoID != nil ? "Photo of the slab" : l.pattern.name]
        parts.append(l.honed ? "honed" : "polished")
        if l.photoID == nil, l.pattern.hasDirection { parts.append("\(l.pattern.markings.lowercased()) \(l.across ? "across" : "along")") }
        return parts.joined(separator: " · ")
    }

    private func followRow(_ area: StoneAppearance) -> some View {
        Button { follow = true } label: {
            HStack(spacing: 12) {
                StoneSwatch(look: area, pixels: 96).frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Same as the area's stone").font(.system(size: 16, weight: .semibold)).foregroundStyle(ND.text)
                    Text("Changes when the area's stone does").font(.system(size: 13)).foregroundStyle(ND.muted)
                }
                Spacer()
                if follow { Image(systemName: "checkmark.circle.fill").foregroundStyle(ND.link).font(.title3) }
            }
            .padding(12)
            .background(follow ? ND.selectedBg : ND.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(follow ? ND.link : ND.border, lineWidth: follow ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func pick(_ l: StoneAppearance) {
        follow = false
        look = l
        nameText = l.name ?? ""
    }

    private var myStones: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("My Stones")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(library.mine.enumerated()), id: \.offset) { i, s in
                        Button { pick(s) } label: {
                            VStack(spacing: 6) {
                                swatchTile(s, size: 72, selected: !follow && look.looksLike(s) && typedName == (s.name ?? ""))
                                    .overlay(alignment: .bottomTrailing) {
                                        if s.photoID != nil {
                                            Text("Photo").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                                .padding(.horizontal, 4).padding(.vertical, 2)
                                                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                                .padding(8)
                                        }
                                    }
                                Text(s.name ?? "").font(.system(size: 12)).foregroundStyle(ND.secondary)
                                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 76)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { newName = s.name ?? ""; renaming = i } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { library.delete(at: i) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            Text("Touch and hold one to rename or delete it.").font(.system(size: 12)).foregroundStyle(ND.muted)
        }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Recently used")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(library.recent.enumerated()), id: \.offset) { _, s in
                        Button { pick(s) } label: { swatchTile(s, size: 64, selected: !follow && look.looksLike(s)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func swatchTile(_ s: StoneAppearance, size: CGFloat, selected: Bool) -> some View {
        StoneSwatch(look: s, pixels: Int(size * 2.5))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).inset(by: -4)
                .stroke(selected ? ND.link : .clear, lineWidth: 3))
            .padding(4)
    }

    /// Grouped by look (owner, 2026-10-18): Veined; Moving and Speckled;
    /// Plain and Natural stone — up to six swatches across.
    private func patterns(width: CGFloat) -> some View {
        let gap: CGFloat = 8
        let cell = max(40, (width - 5 * gap) / 6)
        let g = StoneAppearance.Pattern.groups
        let rows = [[g[0]], [g[1], g[2]], [g[3], g[4]]]
        return VStack(alignment: .leading, spacing: 12) {
            NDLabel("Pattern")
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: gap) {
                    ForEach(row, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group).font(.system(size: 12)).foregroundStyle(ND.muted)
                            HStack(alignment: .top, spacing: gap) {
                                ForEach(StoneAppearance.Pattern.allCases.filter { $0.group == group }) { p in
                                    patternButton(p, cell: cell)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func patternButton(_ p: StoneAppearance.Pattern, cell: CGFloat) -> some View {
        let on = !follow && look.photoID == nil && look.pattern == p
        return Button {
            edit { l in
                l.pattern = p
                l.photoID = nil
                // A pattern with a second colour starts with its usual one.
                if p.usesSecond, l.second == nil { l.second = p.usual.second }
            }
            if !p.usesMarkings { well = .base } else if !p.usesSecond, well == .second { well = .markings }
        } label: {
            VStack(spacing: 4) {
                StoneSwatch(look: .usual(p), pixels: Int(cell * 2.5))
                    .frame(width: cell, height: cell)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).inset(by: -3)
                        .stroke(on ? ND.link : .clear, lineWidth: 3))
                Text(p.name).font(.system(size: 11)).foregroundStyle(ND.text).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: cell)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Colour

    /// The wells, then every colour in one sideways strip: each family
    /// light to dark, a gap between families, Any colour at the end.
    @ViewBuilder
    private var colourStrip: some View {
        let p = shown.pattern
        if shown.photoID != nil {
            Text("Using your photo of the slab. Choose a pattern below to draw it from colours instead.")
                .font(.system(size: 13)).foregroundStyle(ND.muted)
        } else {
            HStack(spacing: 8) {
                wellButton(.base, "Base", shown.base)
                if p.usesMarkings { wellButton(.markings, p.markings, shown.markings) }
                if p.usesSecond { wellButton(.second, "2nd " + p.markings.lowercased(), shown.second) }
            }
            let chosen = current?.uppercased()
            let inFamily = StonePatterns.families.first { $0.colours.contains(chosen ?? "") }?.name
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    // Each family's name jumps the strip to it.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(StonePatterns.families, id: \.name) { f in
                                Button { withAnimation { proxy.scrollTo("family:\(f.name)", anchor: .leading) } } label: {
                                    Text(f.name).font(.system(size: 13, weight: f.name == inFamily ? .semibold : .regular))
                                        .foregroundStyle(f.name == inFamily ? ND.text : ND.muted)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(f.name == inFamily ? ND.raised : ND.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            if well == .second {
                                Button { edit { $0.second = nil } } label: {
                                    RoundedRectangle(cornerRadius: 8).fill(ND.surface)
                                        .overlay(Image(systemName: "slash.circle").foregroundStyle(ND.muted))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(look.second == nil ? ND.link : ND.border,
                                                                                          lineWidth: look.second == nil ? 3 : 1))
                                        .frame(width: 38, height: 46)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                            ForEach(StonePatterns.families, id: \.name) { f in
                                HStack(spacing: 4) {
                                    ForEach(f.colours, id: \.self) { hex in
                                        Button { set(hex) } label: {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color(uiColor: StonePatterns.uiColor(hex)))
                                                .frame(width: 38, height: 46)
                                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(chosen == hex ? ND.link : Color.white.opacity(0.08),
                                                            lineWidth: chosen == hex ? 3 : 1))
                                        }
                                        .buttonStyle(.plain)
                                        .id(hex)
                                    }
                                }
                                .id("family:\(f.name)")
                                .padding(.trailing, 10)
                            }
                            ColorPicker(selection: Binding(
                                get: { Color(uiColor: StonePatterns.uiColor(current ?? look.base)) },
                                set: { set(StonePatterns.hex(UIColor($0))) }), supportsOpacity: false) { EmptyView() }
                                .labelsHidden()
                                .frame(width: 46, height: 46)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .onAppear { if let chosen { proxy.scrollTo(chosen, anchor: .center) } }
                .onChange(of: well) { _, _ in
                    if let c = current?.uppercased() { withAnimation { proxy.scrollTo(c, anchor: .center) } }
                }
            }
        }
    }

    private var current: String? {
        switch well {
        case .base: shown.base
        case .markings: shown.markings
        case .second: shown.second
        }
    }

    private func set(_ hex: String) {
        edit { l in
            switch well {
            case .base: l.base = hex
            case .markings: l.markings = hex
            case .second: l.second = hex
            }
        }
    }

    private func wellButton(_ w: Well, _ label: String, _ hex: String?) -> some View {
        let on = well == w
        return Button { well = w } label: {
            HStack(spacing: 8) {
                Circle().fill(hex.map { Color(uiColor: StonePatterns.uiColor($0)) } ?? .clear)
                    .overlay(Circle().stroke(ND.border))
                    .overlay(hex == nil ? Image(systemName: "slash.circle").foregroundStyle(ND.muted) : nil)
                    .frame(width: 22, height: 22)
                Text(label).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(ND.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 46).frame(maxWidth: .infinity)
            .background(ND.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? ND.link : ND.border, lineWidth: on ? 2.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Photo of the slab")
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(look.photoID == nil ? "Choose photo" : "Change photo", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(NDSecondaryButtonStyle())
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { takingPhoto = true } label: { Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity) }
                        .buttonStyle(NDSecondaryButtonStyle())
                }
            }
            if look.photoID != nil {
                Button(role: .destructive) { edit { $0.photoID = nil } } label: { Label("Remove photo", systemImage: "trash") }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }
}
