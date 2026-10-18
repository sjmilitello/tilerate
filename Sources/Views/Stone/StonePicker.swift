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
        _image = State(initialValue: look.photoID == nil ? StonePatterns.cachedPattern(look, pixels: pixels) : nil)
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
        .task(id: "\(look.drawingKey)@\(pixels)") { image = await render() }
    }

    private func render() async -> UIImage? {
        if let id = look.photoID { return TilePhotos.image(id) }
        if let done = StonePatterns.cachedPattern(look, pixels: pixels) { return done }
        let l = look, px = pixels
        return await Task.detached(priority: .userInitiated) { StonePatterns.patternImage(l, pixels: px) }.value
    }
}

/// Choosing how a stone looks (owner's design, 2026-10-17): a big preview,
/// polished or honed, My Stones and Recently used, the patterns grouped as
/// stone is asked for (each swatch in its usual colours), and one colour
/// grid for the base, the veins (flecks, bands…) and a second colour, chosen
/// with the wells above it. Or a photo of the slab.
struct StonePickerSheet: View {
    let title: String
    let start: StoneAppearance
    /// For one piece: the area's stone, which it can follow.
    var areaLook: StoneAppearance? = nil
    var startsFollowingArea = false
    /// The stone chosen; nil when a piece follows the area's.
    let onDone: (StoneAppearance?) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = StoneLibrary.shared
    @State private var look: StoneAppearance
    @State private var follow: Bool
    @State private var well: Well = .base
    @State private var naming = false
    @State private var newName = ""
    @State private var renaming: Int? = nil
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var takingPhoto = false

    enum Well { case base, markings, second }

    init(title: String, start: StoneAppearance, areaLook: StoneAppearance? = nil, startsFollowingArea: Bool = false,
         onDone: @escaping (StoneAppearance?) -> Void) {
        self.title = title
        self.start = start
        self.areaLook = areaLook
        self.startsFollowingArea = startsFollowingArea
        self.onDone = onDone
        _look = State(initialValue: start)
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
                        if !library.mine.isEmpty { myStones }
                        if !library.recent.isEmpty { recentRow }
                        patterns(width: geo.size.width - 32)
                        photoRow
                        Button { newName = look.name ?? ""; naming = true } label: {
                            Label(look.name == nil ? "Save to My Stones" : "Save to My Stones as…", systemImage: "star")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NDSecondaryButtonStyle())
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
                        if !follow { library.used(look) }
                        onDone(follow ? nil : look)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Save to My Stones", isPresented: $naming) {
                TextField("Name, e.g. Taj Mahal", text: $newName)
                Button("Save") {
                    library.save(look, name: newName)
                    look.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It stays on this phone for every estimate.")
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

    /// Any change makes the stone its own (no longer following the area's,
    /// and no longer the named one from My Stones).
    private func edit(_ change: (inout StoneAppearance) -> Void) {
        if follow, let areaLook { look = areaLook }
        follow = false
        change(&look)
        look.name = library.mine.first { $0.looksLike(look) }?.name
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            StoneSwatch(look: shown, pixels: 512, showFinish: true)
                .frame(height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(caption(shown)).font(.system(size: 14)).foregroundStyle(ND.muted)
        }
    }

    private func caption(_ l: StoneAppearance) -> String {
        var parts = [l.photoID != nil ? "Photo of the slab" : l.pattern.fullName]
        parts.append(l.honed ? "honed" : "polished")
        if follow { parts.insert("Same as the area", at: 0) } else if let n = l.name { parts.insert(n, at: 0) }
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
    }

    private var myStones: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("My Stones")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(library.mine.enumerated()), id: \.offset) { i, s in
                        Button { pick(s) } label: {
                            VStack(spacing: 6) {
                                swatchTile(s, size: 72, selected: !follow && look.looksLike(s) && look.name == s.name)
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

    /// Marble and quartzite on one row, granite and quartz on the next, then
    /// the other stones — six swatches across, as in the mock-up.
    private func patterns(width: CGFloat) -> some View {
        let gap: CGFloat = 8
        let cell = max(40, (width - 5 * gap) / 6)
        let families = ["Marble", "Quartzite", "Granite", "Quartz", "Other stone"]
        let rows = [[families[0], families[1]], [families[2], families[3]], [families[4]]]
        return VStack(alignment: .leading, spacing: 12) {
            NDLabel("Pattern")
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: gap) {
                    ForEach(row, id: \.self) { family in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(family).font(.system(size: 12)).foregroundStyle(ND.muted)
                            HStack(alignment: .top, spacing: gap) {
                                ForEach(StoneAppearance.Pattern.allCases.filter { $0.family == family }) { p in
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
            ScrollViewReader { proxy in
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
                        ForEach(0..<StonePatterns.palette[0].count, id: \.self) { column in
                            HStack(spacing: 4) {
                                ForEach(StonePatterns.palette.map { $0[column] }, id: \.self) { hex in
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
                    .frame(width: 26, height: 26)
                Text(label).font(.system(size: 14, weight: on ? .semibold : .regular)).foregroundStyle(ND.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 46).frame(maxWidth: .infinity)
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
