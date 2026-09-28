import SwiftUI

/// Setting up one area, one step at a time: Area, Tile, Measure, Extras,
/// Review. The price at the bottom updates as you go.
struct AreaFlowView: View {
    @ObservedObject var store: Store
    let roomID: UUID
    let sectionID: UUID
    let startStep: Int
    let onFinish: () -> Void

    @State private var step = 0
    @State private var didStart = false
    @State private var visitedExtras = false
    @State private var editing: TileTarget? = nil
    @State private var editingLine: LineTarget? = nil

    /// Which separate tile the tile sheet is editing.
    private enum TileTarget: Identifiable {
        case wall(UUID), floor, ceiling
        var id: String {
            switch self {
            case .wall(let id): "wall-\(id)"
            case .floor: "floor"
            case .ceiling: "ceiling"
            }
        }
    }

    private struct LineTarget: Identifiable {
        let id: UUID
        let materials: Bool
    }

    // MARK: Data

    private var roomIndex: Int? { store.doc.rooms.firstIndex { $0.id == roomID } }

    private var sec: Binding<EstimateSection> {
        Binding(
            get: {
                guard let r = roomIndex else { return EstimateSection() }
                return store.doc.rooms[r].sections.first { $0.id == sectionID } ?? EstimateSection()
            },
            set: { newValue in
                guard let r = roomIndex,
                      let s = store.doc.rooms[r].sections.firstIndex(where: { $0.id == sectionID }) else { return }
                store.doc.rooms[r].sections[s] = newValue
            }
        )
    }

    private var section: EstimateSection { sec.wrappedValue }
    private var roomName: String { roomIndex.map { store.doc.rooms[$0].name } ?? "" }

    private var summary: Summary { computeSummary(state: EstimatorState(section: section), rates: store.rates) }
    private var areaPrice: Double {
        summary.total
            + section.additionsLabor.reduce(0) { $0 + $1.amount }
            + section.additionsMaterials.reduce(0) { $0 + $1.amount }
    }

    private var tileReady: Bool {
        isSectionReady(section)
            && !isMissingTileDimensions(size: section.tileSize, lengthIn: section.tileLengthIn, widthIn: section.tileWidthIn)
    }

    private var measuredSqft: Double {
        let m = section.measurements
        switch section.area {
        case .shower:
            let walls = section.walls.isEmpty ? m.showerWallsSqft : section.walls.reduce(0) { $0 + $1.sqft }
            return walls + m.showerFloorSqft + m.ceilingSqft
        case .tub:
            let walls = section.walls.isEmpty ? m.sqft : section.walls.reduce(0) { $0 + $1.sqft }
            return walls + m.ceilingSqft
        default:
            return m.sqft
        }
    }

    private var completed: Set<Int> {
        var s: Set<Int> = []
        if section.area != nil { s.insert(0) }
        if tileReady { s.insert(1) }
        if measuredSqft > 0 { s.insert(2) }
        if visitedExtras { s.insert(3) }
        return s
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NDProgress(current: step, completed: completed) { go($0) }
                    switch step {
                    case 0: areaStep
                    case 1: tileStep
                    case 2: measureStep
                    case 3: extrasStep
                    default: reviewStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            footer.modifier(NDHiddenWhileTyping())
        }
        .background(ND.ground.ignoresSafeArea())
        .foregroundStyle(ND.text)
        .navigationTitle("\(roomName) · \(section.area?.rawValue ?? "New area")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ND.ground, for: .navigationBar)
        .ndKeyboardDone()
        .onAppear {
            guard !didStart else { return }
            didStart = true
            step = startStep
            if startStep >= 3 { visitedExtras = true }
        }
        .sheet(item: $editing) { target in
            tileSheet(target)
        }
        .sheet(item: $editingLine) { target in
            NDLineItemSheet(item: lineBinding(target), materials: target.materials) {
                if target.materials { sec.wrappedValue.additionsMaterials.removeAll { $0.id == target.id } }
                else { sec.wrappedValue.additionsLabor.removeAll { $0.id == target.id } }
                editingLine = nil
            }
        }
    }

    private func go(_ newStep: Int) {
        if step == 3 || newStep > 3 { visitedExtras = true }
        withAnimation(.easeInOut(duration: 0.2)) { step = newStep }
    }

    // MARK: Step 1: area

    private var areaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are we tiling?").font(.ndTitle(26))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Area.allCases) { area in
                    let selected = section.area == area
                    Button { choose(area) } label: {
                        VStack(alignment: .leading) {
                            HStack(alignment: .top) {
                                Image(systemName: area.ndIcon)
                                    .font(.system(size: 24))
                                    .foregroundStyle(selected ? Color.white : ND.link)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(ND.link)
                                }
                            }
                            Spacer()
                            Text(area.rawValue).font(.system(size: 17, weight: .semibold))
                            Text(area.ndHint).font(.system(size: 13)).foregroundStyle(selected ? ND.secondary : ND.muted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                        .background(selected ? ND.selectedBg : ND.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selected ? ND.link : ND.border, lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if section.area != nil {
                Text("Changing the area clears its measurements and extras. The tile you chose stays.")
                    .font(.system(size: 13))
                    .foregroundStyle(ND.muted)
            }
        }
    }

    private func choose(_ area: Area) {
        var s = section
        let firstTime = s.area == nil
        guard s.area != area else { go(1); return }
        if !firstTime {
            s.features = Features()
            s.measurements = Measurements()
            s.additionsLabor = []
            s.additionsMaterials = []
            s.showerFloorTile = nil
            s.ceilingTile = nil
            s.walls = []
        }
        s.area = area
        sec.wrappedValue = s
        if firstTime { go(1) }
    }

    // MARK: Step 2: tile

    private var tileStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Which tile?").font(.ndTitle(26))
            NDTileFields(
                type: sec.tileType,
                size: sec.tileSize,
                layout: sec.layout,
                width: sec.tileWidthIn,
                length: sec.tileLengthIn,
                rates: store.rates
            )
            if section.area == .shower || section.area == .tub {
                Text("Walls, the shower floor and the ceiling can each have their own tile on the Measure step.")
                    .font(.system(size: 13))
                    .foregroundStyle(ND.muted)
            }
        }
    }

    // MARK: Step 3: measure

    @ViewBuilder
    private var measureStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch section.area {
            case .shower:
                wallsBlock(title: "Walls", allSame: \.showerWallsSqft)
                floorBlock
                ceilingBlock
            case .tub:
                wallsBlock(title: "Tub surround walls", allSame: \.sqft)
                ceilingBlock
            case .some(let area):
                VStack(alignment: .leading, spacing: 10) {
                    Text(area == .floor ? "Floor area" : "\(area.rawValue) area").font(.ndTitle(22))
                    sqftField(sec.measurements.sqft, label: "Square feet")
                }
            case .none:
                Text("Choose the area first.").foregroundStyle(ND.muted)
            }
        }
    }

    private func wallsBlock(title: String, allSame: WritableKeyPath<Measurements, Double>) -> some View {
        let separate = Binding<Bool>(
            get: { !section.walls.isEmpty },
            set: { on in
                var s = section
                if on {
                    let tile = s.ndMainTile ?? TileChoice()
                    s.walls = ["Back wall", "Left wall", "Right wall"].map { TiledWall(name: $0, tile: tile) }
                } else {
                    let total = s.walls.reduce(0) { $0 + $1.sqft }
                    if total > 0 { s.measurements[keyPath: allSame] = total }
                    s.walls = []
                }
                sec.wrappedValue = s
            }
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.ndTitle(22))
                Spacer()
                if !section.walls.isEmpty {
                    Text("\(ND.number(section.walls.reduce(0) { $0 + $1.sqft })) sq ft total")
                        .font(.system(size: 14)).foregroundStyle(ND.muted)
                }
            }
            Picker("Wall tile", selection: separate) {
                Text("Same tile on all").tag(false)
                Text("Different per wall").tag(true)
            }
            .pickerStyle(.segmented)

            if section.walls.isEmpty {
                sqftField(sec.measurements[dynamicMember: allSame], label: "All walls, square feet")
            } else {
                NDCard {
                    ForEach(Array(section.walls.enumerated()), id: \.element.id) { i, wall in
                        if i > 0 { Divider().overlay(ND.border) }
                        wallRow(wall)
                    }
                }
                Button {
                    let tile = section.walls.last?.tile ?? section.ndMainTile ?? TileChoice()
                    sec.wrappedValue.walls.append(TiledWall(name: "Wall \(section.walls.count + 1)", tile: tile))
                } label: {
                    Label("Add wall", systemImage: "plus").font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(ND.link)
            }
        }
    }

    private func wallRow(_ wall: TiledWall) -> some View {
        let w = wallBinding(wall.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Wall name", text: w.name)
                    .font(.system(size: 16, weight: .semibold))
                Button { editing = .wall(wall.id) } label: {
                    Text(wall.tile.ndSummary).font(.system(size: 13)).multilineTextAlignment(.leading)
                }
                .foregroundStyle(ND.link)
                if isMissingTileDimensions(size: wall.tile.tileSize, lengthIn: wall.tile.tileLengthIn, widthIn: wall.tile.tileWidthIn) {
                    Text("Tile size missing").font(.system(size: 12)).foregroundStyle(ND.warning)
                }
            }
            Spacer(minLength: 4)
            NDNumberField(placeholder: "0", value: w.sqft, alignment: .trailing)
                .frame(width: 76)
            Text("sq ft").font(.system(size: 13)).foregroundStyle(ND.muted)
            Menu {
                Button { editing = .wall(wall.id) } label: { Label("Change tile", systemImage: "square.grid.2x2") }
                Button(role: .destructive) {
                    sec.wrappedValue.walls.removeAll { $0.id == wall.id }
                } label: { Label("Remove wall", systemImage: "trash") }
                .disabled(section.walls.count <= 1)
            } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 44)
            }
            .foregroundStyle(ND.muted)
            .accessibilityLabel("\(wall.name) options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var floorBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shower floor").font(.ndTitle(22))
            sqftField(sec.measurements.showerFloorSqft, label: "Square feet")
            if section.measurements.showerFloorSqft > 0 {
                separateTileRow(tile: section.showerFloorTile, target: .floor,
                                turnOn: { sec.wrappedValue.showerFloorTile = section.ndMainTile ?? TileChoice(); editing = .floor },
                                turnOff: { sec.wrappedValue.showerFloorTile = nil })
            }
        }
    }

    private var ceilingBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ceiling").font(.ndTitle(22))
                Spacer()
                if section.measurements.ceilingSqft > 0 {
                    Button("Remove") {
                        sec.wrappedValue.measurements.ceilingSqft = 0
                        sec.wrappedValue.ceilingTile = nil
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(ND.muted)
                }
            }
            if section.measurements.ceilingSqft > 0 {
                sqftField(sec.measurements.ceilingSqft, label: "Square feet")
                separateTileRow(tile: section.ceilingTile, target: .ceiling,
                                turnOn: { sec.wrappedValue.ceilingTile = section.ndMainTile ?? TileChoice(); editing = .ceiling },
                                turnOff: { sec.wrappedValue.ceilingTile = nil })
            } else {
                Button("Tile the ceiling") { sec.wrappedValue.measurements.ceilingSqft = 1 }
                    .buttonStyle(NDSecondaryButtonStyle())
            }
        }
    }

    private func separateTileRow(tile: TileChoice?, target: TileTarget,
                                 turnOn: @escaping () -> Void, turnOff: @escaping () -> Void) -> some View {
        NDCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tile == nil ? "Same tile as the walls" : "Its own tile")
                        .font(.system(size: 15, weight: .semibold))
                    if let tile {
                        Button { editing = target } label: { Text(tile.ndSummary).font(.system(size: 13)) }
                            .foregroundStyle(ND.link)
                    }
                }
                Spacer()
                Button(tile == nil ? "Use a different tile" : "Use wall tile") {
                    if tile == nil { turnOn() } else { turnOff() }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ND.link)
            }
            .padding(14)
        }
    }

    private func sqftField(_ value: Binding<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(ND.secondary)
            NDNumberField(placeholder: "0", value: value, font: .system(size: 22, weight: .semibold))
        }
    }

    private func wallBinding(_ id: UUID) -> Binding<TiledWall> {
        Binding(
            get: { section.walls.first { $0.id == id } ?? TiledWall() },
            set: { newValue in
                guard let i = section.walls.firstIndex(where: { $0.id == id }) else { return }
                sec.wrappedValue.walls[i] = newValue
            }
        )
    }

    @ViewBuilder
    private func tileSheet(_ target: TileTarget) -> some View {
        switch target {
        case .wall(let id):
            NDTileSheet(title: section.walls.first { $0.id == id }?.name ?? "Wall",
                        tile: wallBinding(id).tile, rates: store.rates)
        case .floor:
            NDTileSheet(title: "Shower floor tile",
                        tile: Binding(get: { section.showerFloorTile ?? TileChoice() },
                                      set: { sec.wrappedValue.showerFloorTile = $0 }),
                        rates: store.rates)
        case .ceiling:
            NDTileSheet(title: "Ceiling tile",
                        tile: Binding(get: { section.ceilingTile ?? TileChoice() },
                                      set: { sec.wrappedValue.ceilingTile = $0 }),
                        rates: store.rates)
        }
    }

    // MARK: Step 4: extras

    private var extrasStep: some View {
        let onFloor = section.area == .floor
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Built-ins").font(.ndTitle(22))
                NDCard {
                    NDCounter(title: "Niches", value: sec.features.niches, enabled: !onFloor)
                    Divider().overlay(ND.border)
                    NDCounter(title: "Shelves", value: sec.features.shelves, enabled: !onFloor)
                    Divider().overlay(ND.border)
                    NDCounter(title: "Benches", value: sec.features.benches, enabled: !onFloor)
                    Divider().overlay(ND.border)
                    NDCounter(title: "Footrests", value: sec.features.footrests, enabled: !onFloor)
                }
                if onFloor {
                    Text("Shelves, niches, footrests and benches aren't available for floors.")
                        .font(.system(size: 13)).foregroundStyle(ND.muted)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Decorative").font(.ndTitle(22))
                NDCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Mosaic band, border or inlay", isOn: sec.features.mosaicBand)
                            .font(.system(size: 16, weight: .medium))
                        if section.features.mosaicBand {
                            sqftField(sec.measurements.mosaicSqft, label: "Mosaic square feet")
                        }
                    }
                    .padding(14)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Other charges").font(.ndTitle(22))
                if !section.additionsLabor.isEmpty || !section.additionsMaterials.isEmpty {
                    NDCard {
                        ForEach(section.additionsLabor) { item in
                            lineRow(item, materials: false)
                            Divider().overlay(ND.border)
                        }
                        ForEach(section.additionsMaterials) { item in
                            lineRow(item, materials: true)
                            Divider().overlay(ND.border)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button { addLine(materials: false) } label: { Label("Labor", systemImage: "plus") }
                        .buttonStyle(NDSecondaryButtonStyle())
                    Button { addLine(materials: true) } label: { Label("Materials", systemImage: "plus") }
                        .buttonStyle(NDSecondaryButtonStyle())
                }
                Text("A price list for extras like demolition or waterproofing is planned.")
                    .font(.system(size: 13)).foregroundStyle(ND.muted)
            }
        }
    }

    private func lineRow(_ item: AdditionItem, materials: Bool) -> some View {
        Button { editingLine = LineTarget(id: item.id, materials: materials) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.activity.isEmpty ? (materials ? "Materials" : "Labor") : item.activity)
                        .font(.system(size: 16, weight: .medium))
                    Text("\(materials ? "Materials" : "Labor")\(materials && item.taxable ? ", taxable" : "") · \(ND.number(item.qty)) × \(ND.money(item.rate))")
                        .font(.system(size: 13)).foregroundStyle(ND.muted)
                }
                Spacer()
                Text(ND.money(item.amount)).font(.system(size: 16, weight: .semibold).monospacedDigit())
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ND.muted)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addLine(materials: Bool) {
        let item = AdditionItem()
        if materials { sec.wrappedValue.additionsMaterials.append(item) }
        else { sec.wrappedValue.additionsLabor.append(item) }
        editingLine = LineTarget(id: item.id, materials: materials)
    }

    private func lineBinding(_ target: LineTarget) -> Binding<AdditionItem> {
        let keyPath: WritableKeyPath<EstimateSection, [AdditionItem]> = target.materials ? \.additionsMaterials : \.additionsLabor
        return Binding(
            get: { section[keyPath: keyPath].first { $0.id == target.id } ?? AdditionItem() },
            set: { newValue in
                guard let i = section[keyPath: keyPath].firstIndex(where: { $0.id == target.id }) else { return }
                sec.wrappedValue[keyPath: keyPath][i] = newValue
            }
        )
    }

    // MARK: Step 5: review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review this area").font(.ndTitle(26))
            ForEach(NDAreaText.warnings(section), id: \.self) { w in
                NDWarning(title: section.area?.rawValue ?? "Area", message: w,
                          actionTitle: isSectionReady(section) ? "Go to tile sizes" : "Choose tile",
                          action: { go(section.area == nil ? 0 : (isSectionReady(section) ? 2 : 1)) })
            }
            NDCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(describeSection(section))
                        .font(.system(size: 14))
                        .foregroundStyle(ND.secondary)
                    Divider().overlay(ND.border)
                    ForEach(summary.lines) { line in
                        HStack(alignment: .top) {
                            Text(line.label).font(.system(size: 14)).foregroundStyle(ND.secondary)
                            Spacer(minLength: 12)
                            Text(ND.money(line.amount)).font(.system(size: 14).monospacedDigit())
                        }
                    }
                    ForEach(section.additionsLabor + section.additionsMaterials) { item in
                        HStack(alignment: .top) {
                            Text(item.activity.isEmpty ? "Other charge" : item.activity)
                                .font(.system(size: 14)).foregroundStyle(ND.secondary)
                            Spacer(minLength: 12)
                            Text(ND.money(item.amount)).font(.system(size: 14).monospacedDigit())
                        }
                    }
                    Divider().overlay(ND.border)
                    HStack {
                        Text("Area total").font(.system(size: 17, weight: .bold))
                        Spacer()
                        Text(ND.money(areaPrice)).font(.system(size: 22, weight: .bold).monospacedDigit())
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("This area").font(.system(size: 12)).foregroundStyle(ND.muted)
                Text(ND.money(areaPrice))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Button {
                if step < 4 { go(step + 1) } else { onFinish() }
            } label: {
                HStack(spacing: 6) {
                    Text(step < 4 ? "Next: \(NDProgress.steps[step + 1].lowercased())" : "Done")
                    if step < 4 { Image(systemName: "chevron.right") }
                }
            }
            .buttonStyle(NDPrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ND.footer.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(ND.border) }
    }
}

// MARK: - Tile fields (main tile and separate tiles)

/// Material, shape, size and layout, with the size-step readout.
struct NDTileFields: View {
    @Binding var type: TileType?
    @Binding var size: TileSize?
    @Binding var layout: Layout?
    @Binding var width: Double?
    @Binding var length: Double?
    let rates: Rates

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                NDLabel("Material")
                NDFlow {
                    ForEach(TileType.allCases) { t in
                        NDChip(title: t.rawValue, selected: type == t) { type = t }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                NDLabel("Shape")
                NDFlow {
                    ForEach(TileSize.allCases) { s in
                        NDChip(title: s.rawValue, selected: size == s) { size = s }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                NDLabel("Tile size (inches)")
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Width").font(.system(size: 13)).foregroundStyle(ND.secondary)
                        NDNumberField(placeholder: "0", value: $width.orZero, font: .system(size: 20, weight: .semibold))
                    }
                    Text("×").font(.system(size: 20)).foregroundStyle(ND.muted).frame(height: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Length").font(.system(size: 13)).foregroundStyle(ND.secondary)
                        NDNumberField(placeholder: "0", value: $length.orZero, font: .system(size: 20, weight: .semibold))
                    }
                }
                sizeReadout
            }
            VStack(alignment: .leading, spacing: 10) {
                NDLabel("Layout")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Layout.allCases) { l in
                        let selected = layout == l
                        Button { layout = l } label: {
                            VStack(spacing: 6) {
                                NDLayoutPattern(layout: l)
                                    .stroke(selected ? ND.link : ND.muted, lineWidth: 1.4)
                                    .frame(width: 52, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                Text(l.rawValue)
                                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundStyle(selected ? Color.white : ND.secondary)
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .background(selected ? ND.selectedBg : ND.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? ND.link : ND.border, lineWidth: selected ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sizeReadout: some View {
        if let size, size == .square || size == .rectangle {
            if isMissingTileDimensions(size: size, lengthIn: length, widthIn: width) {
                NDWarning(title: "Tile size needed",
                          message: "Enter the width and length. Without them no size adder is charged.")
            } else if let doublings = sizeDoublings(size: size, lengthIn: length, widthIn: width, rates: rates),
                      let note = sizeAdderNote(size: size, lengthIn: length, widthIn: width, rates: rates) {
                let amount = doublings * rates.sizeAdderPerDoubling
                HStack(spacing: 12) {
                    Text(rates.sizeAdderUnit == .percent ? "+\(ND.number(amount))%" : "+\(amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(ND.done)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rates.sizeAdderUnit == .percent ? "of the base rate, for size" : "per sq ft, for size")
                            .font(.system(size: 14, weight: .semibold))
                        Text(note.components(separatedBy: " · ").dropLast().joined(separator: " · "))
                            .font(.system(size: 13)).foregroundStyle(ND.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(ND.done.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

/// A small drawing of each tile layout.
struct NDLayoutPattern: Shape {
    let layout: Layout
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 2)
        let w = r.width, h = r.height
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            p.move(to: CGPoint(x: r.minX + x1 * w, y: r.minY + y1 * h))
            p.addLine(to: CGPoint(x: r.minX + x2 * w, y: r.minY + y2 * h))
        }
        switch layout {
        case .straightStacked:
            for i in 1...2 { line(0, CGFloat(i) / 3, 1, CGFloat(i) / 3) }
            for i in 1...3 { line(CGFloat(i) / 4, 0, CGFloat(i) / 4, 1) }
        case .runningBond:
            for i in 1...2 { line(0, CGFloat(i) / 3, 1, CGFloat(i) / 3) }
            for x in [0.33, 0.73] { line(x, 0, x, 1.0 / 3); line(x, 2.0 / 3, x, 1) }
            for x in [0.13, 0.53, 0.93] { line(x, 1.0 / 3, x, 2.0 / 3) }
        case .diagonal:
            for i in stride(from: -0.6, through: 1.0, by: 0.4) { line(i, 1, i + 0.65, 0) }
            for i in stride(from: 0.0, through: 1.6, by: 0.4) { line(i - 0.65, 0, i, 1) }
        case .herringbone:
            for row in [0.35, 0.8] {
                var x = 0.0
                var up = true
                while x < 1 {
                    let nx = min(x + 0.16, 1)
                    line(x, up ? row : row - 0.3, nx, up ? row - 0.3 : row)
                    x = nx; up.toggle()
                }
            }
        case .multiTile:
            line(0, 0.5, 1, 0.5)
            line(0.38, 0, 0.38, 1)
            line(0.38, 0.25, 1, 0.25)
            line(0.69, 0.25, 0.69, 1)
            line(0, 0.75, 0.38, 0.75)
            line(0.19, 0.5, 0.19, 1)
        }
        return p
    }
}

/// Edits a separate tile (a wall, the shower floor or the ceiling).
struct NDTileSheet: View {
    let title: String
    @Binding var tile: TileChoice
    let rates: Rates
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                NDTileFields(
                    type: Binding(get: { tile.tileType }, set: { if let v = $0 { tile.tileType = v } }),
                    size: Binding(get: { tile.tileSize }, set: { if let v = $0 { tile.tileSize = v } }),
                    layout: Binding(get: { tile.layout }, set: { if let v = $0 { tile.layout = v } }),
                    width: $tile.tileWidthIn,
                    length: $tile.tileLengthIn,
                    rates: rates
                )
                .padding(20)
            }
            .background(ND.ground.ignoresSafeArea())
            .foregroundStyle(ND.text)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .ndKeyboardDone()
        }
        .preferredColorScheme(.dark)
    }
}

/// Edits a labor or materials line.
struct NDLineItemSheet: View {
    @Binding var item: AdditionItem
    let materials: Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(materials ? "What is it? (e.g. Waterproofing)" : "What is it? (e.g. Demolition)", text: $item.activity)
                }
                Section {
                    LabeledContent("Quantity") {
                        NDNumberField(placeholder: "1", value: $item.qty, alignment: .trailing).frame(width: 120)
                    }
                    LabeledContent("Price each") {
                        NDNumberField(placeholder: "0", value: $item.rate, alignment: .trailing).frame(width: 120)
                    }
                    if materials {
                        Toggle("Taxable", isOn: $item.taxable)
                    }
                    LabeledContent("Amount", value: ND.money(item.amount))
                }
                Section {
                    Button("Remove this line", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle(materials ? "Materials" : "Labor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .ndKeyboardDone()
        }
        .preferredColorScheme(.dark)
    }
}
