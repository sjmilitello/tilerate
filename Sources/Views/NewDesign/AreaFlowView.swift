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
    @State private var scanning: ScanTarget? = nil
    @State private var measuringOnPlan = false

    /// Where a new scan is kept: on the room for all its areas, or on this
    /// area alone (e.g. scanned from inside a shower).
    private enum ScanTarget: String, Identifiable {
        case room, area
        var id: String { rawValue }
    }
    @State private var didStart = false
    @State private var visitedExtras = false
    @State private var editing: TileTarget? = nil
    @State private var editingLine: LineTarget? = nil

    /// Which separate tile the tile sheet is editing.
    private enum TileTarget: Identifiable {
        case wall(UUID), floor, ceiling, decorative(UUID)
        var id: String {
            switch self {
            case .wall(let id): "wall-\(id)"
            case .decorative(let id): "decorative-\(id)"
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
                var updated = newValue
                updated.syncAreaQuantities()
                store.doc.rooms[r].sections[s] = updated
            }
        )
    }

    private var section: EstimateSection { sec.wrappedValue }
    private var roomName: String { roomIndex.map { store.doc.rooms[$0].name } ?? "" }

    private var summary: Summary { computeSummary(state: EstimatorState(section: section), rates: store.pricingRates) }
    /// The area's full price: tile work, added lines and radiant heat.
    private var priced: SectionPrice {
        sectionPrice(room: EstimateRoom(name: roomName), section: section, rates: store.pricingRates)
    }
    private var areaPrice: Double { priced.subtotal }

    private var tileReady: Bool {
        isSectionReady(section)
            && (section.layout == .multiTile
                || !isMissingTileDimensions(size: section.tileSize, lengthIn: section.tileLengthIn, widthIn: section.tileWidthIn))
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
                                NDAreaIcon(area: area, size: 24)
                                    .foregroundStyle(selected ? Color.white : ND.link)
                                    .frame(height: 28)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(ND.link)
                                }
                            }
                            Spacer()
                            Text(area.rawValue).font(.system(size: 17, weight: .semibold))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
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
            s.decoratives = []
            s.radiantHeat = nil
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
                mosaicStyle: sec.mosaicStyle,
                pieces: sec.multiTilePieces,
                rates: store.pricingRates
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
            if section.area != nil {
                scanBlock
            }
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
                    if area == .floor, section.measurements.sqft > 0 {
                        radiantHeatBlock
                    }
                }
            case .none:
                Text("Choose the area first.").foregroundStyle(ND.muted)
            }
        }
    }

    /// The scan this area measures from: its own, else its room's.
    private var activeScan: ScannedRoom? {
        section.roomScan ?? roomIndex.flatMap { store.doc.rooms[$0].scan }
    }

    /// Other areas in the room measured from the same scan, shown faintly.
    private var otherScanAreas: [OtherAreaPieces] {
        guard section.roomScan == nil, let r = roomIndex else { return [] }
        return store.doc.rooms[r].sections.compactMap { other in
            guard other.id != section.id, other.roomScan == nil, let t = other.scanTakeoff, !t.pieces.isEmpty else { return nil }
            return OtherAreaPieces(name: other.area?.rawValue ?? "Area", pieces: t.pieces)
        }
    }

    /// This area's choices on the scan, or where it starts the first time.
    private func takeoffForEditor(_ scan: ScannedRoom) -> AreaTakeoff {
        if var t = section.scanTakeoff {
            let walls = Set(scan.walls.map(\.id))
            t.pieces.removeAll { !walls.contains($0.wallID) }      // from an earlier scan
            if !t.pieces.isEmpty || t.floor != .none { return t }
        }
        let others = roomIndex.map { store.doc.rooms[$0].sections.filter { $0.id != section.id } } ?? []
        return AreaTakeoff.starting(for: section.area, room: scan, otherAreas: others)
    }

    /// Scanning the room with the iPhone's LiDAR, and measuring this area on
    /// the plan it makes.
    @ViewBuilder
    private var scanBlock: some View {
        Group {
            if let scan = activeScan {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(section.roomScan != nil ? "This area's scan" : "Room scan", systemImage: "viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if RoomScanner.isAvailable {
                            Menu {
                                Button { scanning = .room } label: { Label("Scan the room again", systemImage: "viewfinder") }
                                Button { scanning = .area } label: { Label("Scan just this area", systemImage: "square.dashed") }
                            } label: {
                                Text("Rescan").font(.system(size: 14, weight: .medium))
                            }
                        }
                    }
                    Button { measuringOnPlan = true } label: {
                        PlanCanvas(room: scan, mine: section.scanTakeoff?.pieces ?? [], others: otherScanAreas, interactive: false)
                            .frame(height: 150)
                            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    if let t = section.scanTakeoff {
                        Text(scanSummary(t, scan)).font(.system(size: 14)).foregroundStyle(ND.secondary)
                    }
                    Button { measuringOnPlan = true } label: {
                        Label(section.scanTakeoff == nil ? "Measure on the plan" : "Adjust on the plan", systemImage: "ruler")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NDPrimaryButtonStyle())
                }
                .padding(14)
                .background(ND.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ND.border))
            } else if RoomScanner.isAvailable {
                Button { scanning = .room } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan the room").font(.system(size: 16, weight: .semibold))
                            Text("Walk round it with the camera; every area in \(roomName.isEmpty ? "the room" : roomName) can measure from it.")
                                .font(.system(size: 13)).foregroundStyle(ND.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(ND.muted)
                    }
                    .padding(14)
                    .background(ND.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ND.border))
                    .foregroundStyle(ND.text)
                }
                .buttonStyle(.plain)
            } else {
                sampleScanButton
            }
        }
        .fullScreenCover(item: $scanning) { target in
            RoomScanCover { room in finishScan(room, target: target) }
        }
        .fullScreenCover(isPresented: $measuringOnPlan) {
            if let scan = activeScan {
                ScanEditor(room: scan, area: section.area,
                           title: "\(roomName.isEmpty ? "" : roomName + " · ")\(section.area?.rawValue ?? "Area")",
                           takeoff: takeoffForEditor(scan), others: otherScanAreas,
                           onUse: { t in
                               var s = section
                               t.apply(scan, to: &s)
                               sec.wrappedValue = s
                           },
                           onRescan: {
                               measuringOnPlan = false
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                   scanning = section.roomScan != nil ? .area : .room
                               }
                           })
            }
        }
    }

    @ViewBuilder
    private var sampleScanButton: some View {
        #if DEBUG
        Button("Use a sample room (no LiDAR here)") { finishScan(.sample, target: .room) }
            .font(.system(size: 14))
        #else
        EmptyView()
        #endif
    }

    private func finishScan(_ room: ScannedRoom, target: ScanTarget) {
        switch target {
        case .room:
            if let r = roomIndex { store.doc.rooms[r].scan = room }
            sec.wrappedValue.roomScan = nil
        case .area:
            sec.wrappedValue.roomScan = room
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { measuringOnPlan = true }
    }

    private func scanSummary(_ t: AreaTakeoff, _ scan: ScannedRoom) -> String {
        var parts: [String] = []
        if !t.pieces.isEmpty {
            let walls = Set(t.pieces.map(\.wallID)).compactMap { scan.wall($0)?.label }.sorted()
            parts.append("Walls \(walls.joined(separator: ", ")): \(ND.number(t.wallsSqft(in: scan))) sq ft")
        }
        if t.floor != .none, section.area == .floor || section.area == .shower {
            parts.append("\(section.area == .shower ? "Shower floor" : "Floor"): \(ND.number(t.floorSqft(in: scan))) sq ft")
        }
        if t.tileCeiling { parts.append("Ceiling: \(ND.number(t.ceilingSqft(in: scan))) sq ft") }
        return parts.isEmpty ? "Nothing measured from the scan yet." : parts.joined(separator: " · ")
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
                radiantHeatBlock
            }
        }
    }

    /// Electric radiant heat under a floor or shower floor: on or off, which
    /// system, how much of the floor is heated, and what it comes to.
    @ViewBuilder
    private var radiantHeatBlock: some View {
        let systems = store.pricingRates.heatingSystems
        let floorSqft = radiantFloorSqft(area: section.area, measurements: section.measurements) ?? 0
        let isOn = Binding<Bool>(
            get: { section.radiantHeat != nil },
            set: { sec.wrappedValue.radiantHeat = $0 ? RadiantHeatChoice(systemID: systems.first?.id) : nil }
        )
        NDCard {
            VStack(alignment: .leading, spacing: 12) {
                if systems.isEmpty {
                    Text("Electric radiant heat").font(.system(size: 16, weight: .semibold))
                    Text("Set up a heating system in Admin to add radiant heat.")
                        .font(.system(size: 13)).foregroundStyle(ND.muted)
                } else {
                    Toggle("Electric radiant heat", isOn: isOn)
                        .font(.system(size: 16, weight: .semibold))
                    if let choice = section.radiantHeat {
                        if systems.count > 1 {
                            LabeledContent("System") {
                                Picker("System", selection: Binding(
                                    get: { choice.systemID ?? systems[0].id },
                                    set: { sec.wrappedValue.radiantHeat?.systemID = $0 })) {
                                    ForEach(systems) { Text($0.name).tag($0.id) }
                                }
                            }
                            .font(.system(size: 15))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Heated sq ft (whole floor: \(ND.number(floorSqft)))")
                                .font(.system(size: 13)).foregroundStyle(ND.secondary)
                            NDNumberField(placeholder: ND.number(floorSqft), value: Binding(
                                get: { section.radiantHeat?.heatedSqft ?? 0 },
                                set: { sec.wrappedValue.radiantHeat?.heatedSqft = $0 > 0 ? $0 : nil }))
                        }
                        if let r = priced.radiant {
                            radiantSummary(r)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func radiantSummary(_ r: RadiantHeatPrice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(r.parts.enumerated()), id: \.offset) { _, part in
                HStack {
                    Text("\(part.name): \(part.detail)").font(.system(size: 13)).foregroundStyle(ND.muted)
                    Spacer()
                    Text(ND.money(part.cost)).font(.system(size: 13).monospacedDigit()).foregroundStyle(ND.muted)
                }
            }
            Divider().overlay(ND.border).padding(.vertical, 2)
            HStack {
                Text("Kit, with \(ND.number(r.system.markupPercent))% markup").font(.system(size: 14))
                Spacer()
                Text(ND.money(r.materials)).font(.system(size: 14, weight: .semibold).monospacedDigit())
            }
            HStack {
                Text(r.laborMinimumApplied ? "Installation (minimum)" : "Installation").font(.system(size: 14))
                Spacer()
                Text(ND.money(r.labor)).font(.system(size: 14, weight: .semibold).monospacedDigit())
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
                        tile: wallBinding(id).tile, rates: store.pricingRates)
        case .floor:
            NDTileSheet(title: "Shower floor tile",
                        tile: Binding(get: { section.showerFloorTile ?? TileChoice() },
                                      set: { sec.wrappedValue.showerFloorTile = $0 }),
                        rates: store.pricingRates)
        case .decorative(let id):
            let item = decorativeBinding(id)
            NDTileSheet(title: "\(item.wrappedValue.kind.rawValue) tile", tile: item.tile, rates: store.pricingRates)
        case .ceiling:
            NDTileSheet(title: "Ceiling tile",
                        tile: Binding(get: { section.ceilingTile ?? TileChoice() },
                                      set: { sec.wrappedValue.ceilingTile = $0 }),
                        rates: store.pricingRates)
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
                Text("Bands, borders & inlays").font(.ndTitle(22))
                if !section.decoratives.isEmpty {
                    NDCard {
                        ForEach(Array(section.decoratives.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { Divider().overlay(ND.border) }
                            decorativeRow(item)
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(DecorativeKind.allCases) { kind in
                        Button { addDecorative(kind) } label: { Label(kind.rawValue, systemImage: "plus") }
                            .buttonStyle(NDSecondaryButtonStyle())
                    }
                }
                Text("Bands and borders are priced per linear foot, inlays per square foot.")
                    .font(.system(size: 13)).foregroundStyle(ND.muted)
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
                if !store.rates.priceList.isEmpty {
                    Menu {
                        PriceListMenuItems(items: store.rates.priceList) { sec.wrappedValue.add($0) }
                    } label: {
                        Label("From price list", systemImage: "list.bullet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(ND.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                HStack(spacing: 8) {
                    Button { addLine(materials: false) } label: { Label("Custom labor", systemImage: "plus") }
                        .buttonStyle(NDSecondaryButtonStyle())
                    Button { addLine(materials: true) } label: { Label("Custom materials", systemImage: "plus") }
                        .buttonStyle(NDSecondaryButtonStyle())
                }
            }
        }
    }

    private func decorativeRow(_ item: DecorativeItem) -> some View {
        let d = decorativeBinding(item.id)
        let options = decorativeLocationOptions(section)
        return VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(1)
                    .foregroundStyle(ND.muted)
                TextField("Name (optional)", text: d.name)
                    .font(.system(size: 16, weight: .semibold))
                Button { editing = .decorative(item.id) } label: {
                    Text(item.tile.ndSummary).font(.system(size: 13)).multilineTextAlignment(.leading)
                }
                .foregroundStyle(ND.link)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    NDNumberField(placeholder: "0", value: d.quantity, alignment: .trailing)
                        .frame(width: 76)
                    Text(item.kind.unit).font(.system(size: 13)).foregroundStyle(ND.muted)
                }
                let rate = decorativeRate(item.kind, rates: store.pricingRates)
                Text(rate == 0 ? "No rate set in Admin" : ND.money(item.quantity * rate))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(rate == 0 ? ND.warning : ND.secondary)
            }
            Menu {
                Button { editing = .decorative(item.id) } label: { Label("Change tile", systemImage: "square.grid.2x2") }
                Button(role: .destructive) {
                    sec.wrappedValue.decoratives.removeAll { $0.id == item.id }
                } label: { Label("Remove", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 44)
            }
            .foregroundStyle(ND.muted)
            .accessibilityLabel("\(item.kind.rawValue) options")
        }
            if !options.isEmpty {
                Text(item.kind == .inlay ? "LOCATION" : "LOCATIONS — CHOOSE ANY")
                    .font(.system(size: 11, weight: .semibold)).tracking(1)
                    .foregroundStyle(ND.muted)
                NDFlow(spacing: 6) {
                    ForEach(options, id: \.key) { opt in
                        NDChip(title: opt.label, selected: item.isAt(opt)) {
                            d.wrappedValue.toggleLocation(opt)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func addDecorative(_ kind: DecorativeKind) {
        sec.wrappedValue.decoratives.append(
            DecorativeItem(kind: kind, tile: defaultDecorativeTile(for: section)))
    }

    private func decorativeBinding(_ id: UUID) -> Binding<DecorativeItem> {
        Binding(
            get: { section.decoratives.first { $0.id == id } ?? DecorativeItem() },
            set: { newValue in
                guard let i = section.decoratives.firstIndex(where: { $0.id == id }) else { return }
                sec.wrappedValue.decoratives[i] = newValue
            }
        )
    }

    private func lineRow(_ item: AdditionItem, materials: Bool) -> some View {
        Button { editingLine = LineTarget(id: item.id, materials: materials) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.activity.isEmpty ? (materials ? "Materials" : "Labor") : item.activity)
                        .font(.system(size: 16, weight: .medium))
                    Text("\(materials ? "Materials" : "Labor")\(materials && item.taxable ? ", taxable" : "") · \(ND.number(item.qty))\(item.unit.isEmpty ? "" : " " + item.unit) × \(ND.money(item.rate))\(item.minimumApplied ? " · minimum" : "")")
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
                    Text(areaWording(section, wording: store.pricingRates.wording).text)
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
                    ForEach(priced.laborItems + priced.materialItems) { item in
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

/// Material, then layout (Mosaic is a layout choice here), then shape and
/// size: several shapes and sizes for Multi-Tile, a style and size for Mosaic.
struct NDTileFields: View {
    @Binding var type: TileType?
    @Binding var size: TileSize?
    @Binding var layout: Layout?
    @Binding var width: Double?
    @Binding var length: Double?
    @Binding var mosaicStyle: MosaicStyle?
    @Binding var pieces: [TilePiece]
    let rates: Rates

    private var isMosaic: Bool { size == .mosaic }
    private var isMultiTile: Bool { !isMosaic && layout == .multiTile }

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

            layoutGrid

            if isMosaic {
                VStack(alignment: .leading, spacing: 10) {
                    NDLabel("Mosaic style")
                    NDFlow {
                        ForEach(MosaicStyle.allCases) { m in
                            NDChip(title: m.rawValue, selected: mosaicStyle == m) { mosaicStyle = m }
                        }
                    }
                    if mosaicStyle == .square || mosaicStyle == .rectangular {
                        Text("Enter the piece size below. It shows on the estimate.")
                            .font(.system(size: 13)).foregroundStyle(ND.muted)
                    }
                }
                sizeFields
            } else if isMultiTile {
                piecesEditor
            } else if layout != nil {
                VStack(alignment: .leading, spacing: 10) {
                    NDLabel("Shape")
                    NDFlow {
                        ForEach(TileSize.allCases.filter { $0 != .mosaic }) { s in
                            NDChip(title: s.rawValue, selected: size == s) { size = s }
                        }
                    }
                }
                sizeFields
            }
        }
    }

    // MARK: Layout

    private var layoutGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Layout")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Layout.allCases) { l in
                    layoutButton(title: l.rawValue, selected: !isMosaic && layout == l,
                                 picture: AnyShape(NDLayoutPattern(layout: l))) { choose(l) }
                }
                layoutButton(title: "Mosaic", selected: isMosaic,
                             picture: AnyShape(NDTilePattern(kind: .randomLinear))) { chooseMosaic() }
            }
        }
    }

    private func layoutButton(title: String, selected: Bool, picture: AnyShape,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                picture
                    .stroke(selected ? ND.link : ND.muted, lineWidth: 1.4)
                    .frame(width: 52, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Text(title)
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

    private func choose(_ l: Layout) {
        layout = l
        if isMosaic { size = nil }              // back from Mosaic: choose a shape again
        if l == .multiTile {
            if size == nil { size = .rectangle }
            if pieces.isEmpty {
                // Start from the tile already entered, if any.
                pieces = [TilePiece(shape: size ?? .rectangle, widthIn: width, lengthIn: length)]
            }
        }
    }

    private func chooseMosaic() {
        size = .mosaic
        layout = nil                            // mosaics have no layout
    }

    // MARK: Size

    private var sizeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel(isMosaic ? "Piece size (inches)" : "Tile size (inches)")
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
    }

    // MARK: Multi-tile pieces

    private var piecesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Tiles in the pattern")
            NDCard {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { i, piece in
                    if i > 0 { Divider().overlay(ND.border) }
                    pieceRow(piece)
                }
            }
            Button {
                pieces.append(TilePiece(shape: pieces.last?.shape ?? .rectangle))
            } label: {
                Label("Add tile size", systemImage: "plus").font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(ND.link)
            Text("Multi-tile layouts have no size adder; the Multi-Tile layout adder applies.")
                .font(.system(size: 13)).foregroundStyle(ND.muted)
        }
    }

    private func pieceRow(_ piece: TilePiece) -> some View {
        let p = pieceBinding(piece.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(TileSize.allCases.filter { $0 != .mosaic }) { s in
                        Button(s.rawValue) { p.wrappedValue.shape = s }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(piece.shape.rawValue).font(.system(size: 16, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12))
                    }
                    .foregroundStyle(ND.link)
                    .frame(minHeight: 36)
                }
                Spacer()
                Button(role: .destructive) {
                    pieces.removeAll { $0.id == piece.id }
                } label: {
                    Image(systemName: "trash").frame(width: 36, height: 36)
                }
                .foregroundStyle(ND.muted)
                .disabled(pieces.count <= 1)
                .accessibilityLabel("Remove this tile size")
            }
            HStack(spacing: 10) {
                NDNumberField(placeholder: "Width", value: p.widthIn.orZero)
                Text("×").foregroundStyle(ND.muted)
                NDNumberField(placeholder: "Length", value: p.lengthIn.orZero)
                Text("in").font(.system(size: 13)).foregroundStyle(ND.muted)
            }
        }
        .padding(14)
    }

    private func pieceBinding(_ id: UUID) -> Binding<TilePiece> {
        Binding(
            get: { pieces.first { $0.id == id } ?? TilePiece() },
            set: { newValue in
                guard let i = pieces.firstIndex(where: { $0.id == id }) else { return }
                pieces[i] = newValue
            }
        )
    }

    @ViewBuilder
    private var sizeReadout: some View {
        if let size, size == .square || size == .rectangle {
            if isMissingTileDimensions(size: size, lengthIn: length, widthIn: width) {
                NDWarning(title: "Tile size needed",
                          message: "Enter the width and length. Without them no size adder is charged.")
            } else if let amount = sizeAdderAmount(size: size, lengthIn: length, widthIn: width, rates: rates),
                      let note = sizeAdderNote(size: size, lengthIn: length, widthIn: width, rates: rates) {
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
            // 3:1 planks in a herringbone: staircases of alternating
            // horizontal and vertical planks, repeated every (L, -L), then
            // turned 45° so the planks form V rows. Clipped to the frame.
            let pw: CGFloat = 1, pl: CGFloat = 3
            let unit = h / 5.5
            let turn = CGAffineTransform(translationX: r.midX, y: r.midY)
                .rotated(by: .pi / 4)
                .scaledBy(x: unit, y: unit)
            for m in -8...8 {
                for k in -12...12 {
                    let ox = CGFloat(k) * pw + CGFloat(m) * pl
                    let oy = CGFloat(k) * pw - CGFloat(m) * pl
                    p.addRect(CGRect(x: ox, y: oy, width: pl, height: pw), transform: turn)
                    p.addRect(CGRect(x: ox, y: oy + pw, width: pw, height: pl), transform: turn)
                }
            }
        case .multiTile:
            // A repeating pattern of large and small squares and rectangles.
            let module: [(CGFloat, CGFloat, CGFloat, CGFloat)] =
                [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 1, 1), (3, 1, 1, 2), (0, 2, 1, 2), (1, 2, 2, 2), (3, 3, 1, 1)]
            let size = h * 0.95
            let u = size / 4
            var row = 0
            var y = r.minY - u
            while y < r.maxY {
                var x = r.minX - (row.isMultiple(of: 2) ? 0 : size / 2) - u
                while x < r.maxX {
                    for (mx, my, mw, mh) in module {
                        p.addRect(CGRect(x: x + mx * u, y: y + my * u, width: mw * u, height: mh * u))
                    }
                    x += size
                }
                y += size
                row += 1
            }
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
                    size: Binding(get: { tile.tileSize }, set: { tile.tileSize = $0 ?? .rectangle }),
                    layout: Binding(get: { tile.layout }, set: { if let v = $0 { tile.layout = v } }),
                    width: $tile.tileWidthIn,
                    length: $tile.tileLengthIn,
                    mosaicStyle: $tile.mosaicStyle,
                    pieces: $tile.pieces,
                    rates: rates
                )
                .padding(20)
            }
            .background(ND.ground.ignoresSafeArea())
            .foregroundStyle(ND.text)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
                    LabeledContent(item.unit.isEmpty ? "Quantity" : "Quantity (\(item.unit))") {
                        NDNumberField(placeholder: "1", value: Binding(
                            get: { item.qty },
                            set: { v in
                                guard v != item.qty else { return }
                                item.qty = v
                                item.followsAreaSqft = false   // typed: stop following the area
                            }), alignment: .trailing).frame(width: 120)
                    }
                    if item.followsAreaSqft {
                        Text("Follows this area's square feet until you type a quantity.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Price each") {
                        NDNumberField(placeholder: "0", value: $item.rate, alignment: .trailing).frame(width: 120)
                    }
                    if materials {
                        Toggle("Taxable", isOn: $item.taxable)
                    }
                    if item.minimum > 0 {
                        LabeledContent("Minimum") {
                            NDNumberField(placeholder: "0", value: $item.minimum, alignment: .trailing).frame(width: 120)
                        }
                    }
                    LabeledContent(item.minimumApplied ? "Amount (minimum)" : "Amount", value: ND.money(item.amount))
                }
                Section {
                    Button("Remove this line", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle(materials ? "Materials" : "Labor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
