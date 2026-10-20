import PhotosUI
import SwiftUI

/// Setting up one area, one step at a time: Area, Tile, Measure, Extras,
/// Review. The price at the bottom updates as you go.
struct AreaFlowView: View {
    @ObservedObject var store: Store
    let roomID: UUID
    let sectionID: UUID
    let startStep: Int
    /// A new room's areas, to be guided through one at a time (owner,
    /// 2026-10-12): "Next: Floor" instead of Done until the last.
    var guide: [UUID] = []
    var onGuideEnd: () -> Void = {}
    let onFinish: () -> Void

    @State private var step = 0
    /// A scanned area's one screen (owner, 2026-10-12): its tab, and a count
    /// bumped when the area's model choices change outside it (calibrating,
    /// scanning again), so it opens afresh on them.
    @State private var workspaceTab: ScanEditor.Tab = .measure
    @State private var workspaceVersion = 0
    /// The area being worked on, once another of the room's areas has been
    /// tapped on the model or chosen from the chips (owner, 2026-10-12).
    @State private var activeID: UUID? = nil
    @State private var confirmDelete = false
    @State private var workspace3D = false
    @State private var addingAreas = false
    /// Guided showers already offered "tap where it goes".
    @State private var showersPlaced: Set<UUID> = []
    @State private var camera3D = Room3DCameraMemory()
    @State private var scanning: ScanTarget? = nil
    @State private var sketchingRoom = false
    /// The model open from the Measure or Extras step.
    @State private var editorMode: ScanEditor.Mode? = nil
    /// The model opened by itself on arriving at Measure (once).
    @State private var autoOpened = false
    @State private var calibrating = false

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
        /// The area's own tile; and, for walls sharing it, the scanned wall
        /// that was tapped (so it can be given its own).
        case main, allWalls(UUID)
        var id: String {
            switch self {
            case .main: "main"
            case .allWalls(let id): "allWalls-\(id)"
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

    private var sec: Binding<EstimateSection> { sectionBinding(currentID) }

    /// One of the room's areas; the model keeps its edits to the area it
    /// opened on, even when they arrive just after switching to another.
    private func sectionBinding(_ id: UUID) -> Binding<EstimateSection> {
        Binding(
            get: {
                guard let r = roomIndex else { return EstimateSection() }
                return store.doc.rooms[r].sections.first { $0.id == id } ?? EstimateSection()
            },
            set: { newValue in
                guard let r = roomIndex,
                      let s = store.doc.rooms[r].sections.firstIndex(where: { $0.id == id }) else { return }
                var updated = newValue
                updated.syncAreaQuantities()
                store.doc.rooms[r].sections[s] = updated
            }
        )
    }

    private var currentID: UUID { activeID ?? sectionID }
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

    /// A scanned area, once its kind is chosen, is one screen: the model on
    /// top, Tile · Measure · Extras · Price below.
    private var useWorkspace: Bool { fromModel && section.area != nil && step > 0 }

    var body: some View {
        Group {
            if useWorkspace, let scan = activeScan {
                workspace(scan)
            } else {
                steps
            }
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
            workspaceTab = Self.tab(for: startStep)
            if startStep >= 3 { visitedExtras = true }
            openModelIfNew()
        }
        .sheet(item: $editing) { target in
            tileSheet(target)
        }
        .sheet(isPresented: $calibrating) {
            if let scan = activeScan {
                CalibrateScanSheet(room: scan, onApply: { applyCalibration($0) },
                                   onUndo: scan.calibrations.isEmpty ? nil : { undoCalibration() })
            }
        }
        .modifier(ScanCoversModifier(apply: { scanCovers($0) }))
        .sheet(isPresented: $addingAreas) {
            NDNewRoomSheet(defaultName: roomName, addingTo: roomName) { _, areas, _ in addAreas(areas) }
        }
        .confirmationDialog("Delete \(section.area?.rawValue ?? "this area")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete this area", role: .destructive) { deleteArea() }
        } message: {
            Text("Its tile, measurements and lines come off the estimate.")
        }
        .sheet(item: $editingLine) { target in
            NDLineItemSheet(item: lineBinding(target), materials: target.materials) {
                if target.materials { sec.wrappedValue.additionsMaterials.removeAll { $0.id == target.id } }
                else { sec.wrappedValue.additionsLabor.removeAll { $0.id == target.id } }
                editingLine = nil
            }
        }
    }

    static func tab(for step: Int) -> ScanEditor.Tab {
        switch step { case 1: .tile; case 2: .measure; case 3: .extras; default: step >= 4 ? .price : .measure }
    }

    /// The model, embedded as this area's screen.
    private func workspace(_ scan: ScannedRoom) -> some View {
        modelEditor(scan, mode: workspaceTab == .extras ? .extras : .measure, embedding: ScanEditor.Embedding(
            tab: $workspaceTab,
            tileTab: AnyView(tileStep),
            measureExtra: AnyView(measureFields),
            extrasExtra: AnyView(extrasRest),
            priceTab: AnyView(reviewStep),
            price: areaPrice,
            menu: AnyView(workspaceMenu(scan)),
            onDone: { finishOrNext() },
            areaBar: AnyView(areaBar),
            onSwitchArea: { switchTo($0) },
            show3D: $workspace3D,
            onPickTile: { pickTile($0, $1) },
            camera3D: camera3D,
            doneTitle: nextArea.map { "Next: \(Self.areaName($0, in: roomSections))" } ?? "Done",
            startPlacingShower: guide.contains(currentID) && section.area == .shower
                && !showersPlaced.contains(currentID)))
            .id(workspaceVersion)
    }

    @ViewBuilder
    private func workspaceMenu(_ scan: ScannedRoom) -> some View {
        Button { step = 0 } label: { Label("Change the kind of area", systemImage: "square.grid.2x2") }
        if !scan.sketched {
            Button { calibrating = true } label: {
                Label(scan.calibrations.isEmpty ? "Calibrate with a tape measure" : "Check the calibration", systemImage: "ruler")
            }
        }
        if RoomScanner.isAvailable {
            Button { scanning = .room } label: { Label(scan.sketched ? "Scan the room" : "Scan the room again", systemImage: "viewfinder") }
            Button { scanning = .area } label: { Label("Scan just this area", systemImage: "square.dashed") }
        }
        Button { sec.wrappedValue.measuredByHand = true } label: { Label("Enter by hand instead", systemImage: "keyboard") }
        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete this area", systemImage: "trash") }
    }

    /// The room's areas as chips: tap one to work on it here, or add one.
    private var areaBar: some View {
        let areas = roomIndex.map { store.doc.rooms[$0].sections } ?? []
        let room = roomIndex.map { store.doc.rooms[$0] }
        return ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(areas) { a in
                        let on = a.id == currentID
                        Button { switchTo(a.id) } label: {
                            VStack(spacing: 0) {
                                Text(Self.areaName(a, in: areas)).font(.system(size: 13, weight: .semibold))
                                if let room, a.area != nil {
                                    Text(ND.money(sectionPrice(room: EstimateRoom(name: room.name), section: a, rates: store.pricingRates).subtotal))
                                        .font(.system(size: 11).monospacedDigit()).opacity(0.75)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(on ? Color.black : Color.white)
                            .background(on ? Color.white : Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Button { addingAreas = true } label: {
                        Label("Add area", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .foregroundStyle(.white)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
    }

    /// A surface tapped on the model on the Tile tab: its area comes up (if
    /// it's another) and its tile opens.
    private func pickTile(_ owner: UUID?, _ surface: ScanEditor.Surface) {
        let switching = owner.map { $0 != currentID } ?? false
        if let owner, switching { switchTo(owner) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (switching ? 0.3 : 0)) { openTile(surface) }
    }

    private func openTile(_ surface: ScanEditor.Surface) {
        switch surface {
        case .floor:
            editing = section.area == .shower ? .floor : .main
        case .wall(let id):
            guard let scan = activeScan, let w = scan.wall(id) else { editing = .main; return }
            let name = scan.name(of: w)
            if let tw = section.walls.first(where: { $0.name == name }) {
                editing = .wall(tw.id)
            } else if section.walls.isEmpty, section.area == .shower || section.area == .tub {
                editing = .allWalls(id)
            } else {
                editing = .main
            }
        }
    }

    /// Gives each wall its own tile, from the model (walls named by letter).
    private func separateWallsOnModel() {
        guard let scan = activeScan else { return }
        var s = section
        guard let t = s.scanTakeoff else { return }
        s.walls = [TiledWall(name: "", tile: s.fullMainTile ?? .usual)]
        t.apply(scan, to: &s, prices: StonePrices(rates: store.pricingRates))
        sec.wrappedValue = s
    }

    /// Every tile already used in this room, once each, for one-tap use.
    private var roomTiles: [NDTileSheet.Suggestion] {
        guard let r = roomIndex else { return [] }
        var out: [NDTileSheet.Suggestion] = []
        func add(_ label: String, _ tile: TileChoice?) {
            guard let tile, !out.contains(where: { $0.tile == tile }) else { return }
            out.append(.init(label: "Same as " + label, tile: tile))
        }
        for a in store.doc.rooms[r].sections {
            let name = a.area?.rawValue ?? "Area"
            let hasWalls = a.area == .shower || a.area == .tub
            if a.walls.isEmpty { add(hasWalls ? "\(name.lowercased()) walls" : name.lowercased(), a.fullMainTile) }
            for w in a.walls { add("\(name.lowercased()) · \(w.name)", w.tile) }
            add("\(name.lowercased()) floor", a.showerFloorTile)
            add("\(name.lowercased()) ceiling", a.ceilingTile)
        }
        return out
    }

    private var mainTileBinding: Binding<TileChoice> {
        Binding(get: { section.fullMainTile ?? .usual }, set: { sec.wrappedValue.setMainTile($0) })
    }

    private var roomSections: [EstimateSection] { roomIndex.map { store.doc.rooms[$0].sections } ?? [] }

    /// The next area to be guided to, after this one.
    private var nextArea: EstimateSection? {
        guard let i = guide.firstIndex(of: currentID) else { return nil }
        let rest = guide[(i + 1)...]
        return rest.lazy.compactMap { id in roomSections.first { $0.id == id } }.first
    }

    /// The bottom button: on to the next area while guided, else done.
    private func finishOrNext() {
        showersPlaced.insert(currentID)
        guard let next = nextArea else {
            if guide.contains(currentID) { onGuideEnd() }
            onFinish()
            return
        }
        let onModel = activeScan != nil && !next.measuredByHand
        activeID = next.id
        editing = nil
        editingLine = nil
        autoOpened = true
        visitedExtras = false
        step = onModel ? 2 : 1
        workspaceTab = onModel ? .measure : .tile
        workspaceVersion += 1
    }

    /// An area's name in its room: "Shower", or "Shower 2" for the second.
    static func areaName(_ a: EstimateSection, in areas: [EstimateSection]) -> String {
        // A vanity's own area (owner, 2026-10-19).
        if a.scanTakeoff?.vanityID != nil {
            let vanities = areas.filter { $0.scanTakeoff?.vanityID != nil }
            let n = vanities.firstIndex { $0.id == a.id } ?? 0
            return vanities.count > 1 && n > 0 ? "Vanity \(n + 1)" : "Vanity"
        }
        guard let kind = a.area else { return "New area" }
        let same = areas.filter { $0.area == kind && $0.scanTakeoff?.vanityID == nil }
        guard same.count > 1, let n = same.firstIndex(where: { $0.id == a.id }) else { return kind.rawValue }
        return n == 0 ? kind.rawValue : "\(kind.rawValue) \(n + 1)"
    }

    /// Work on another of the room's areas without leaving the screen; the
    /// tab stays where it was.
    private func switchTo(_ id: UUID) {
        guard id != currentID else { return }
        showersPlaced.insert(currentID)
        activeID = id
        editing = nil
        editingLine = nil
        autoOpened = true
        if section.area == nil { step = 0 } else if step == 0 { step = 2 }
        else { step = Self.step(for: workspaceTab) }
        workspaceVersion += 1
    }

    /// Several areas added at once, placed on the model; the first comes up.
    private func addAreas(_ areas: [Area]) {
        guard let r = roomIndex else { return }
        let ids = store.doc.rooms[r].addAreas(areas, prices: StonePrices(rates: store.pricingRates))
        guard let first = ids.first else { return }
        activeID = first
        editing = nil
        editingLine = nil
        autoOpened = true
        step = Self.step(for: workspaceTab)
        workspaceVersion += 1
    }

    /// Deletes the area on screen and moves to another of the room's areas,
    /// or leaves when it was the last.
    private func deleteArea() {
        guard let r = roomIndex else { return }
        let id = currentID
        let rest = store.doc.rooms[r].sections.filter { $0.id != id }
        store.doc.rooms[r].sections.removeAll { $0.id == id }
        store.doc.pictures.removeAll { $0.sectionID == id }
        store.doc.rooms[r].refreshFloorCutouts(prices: StonePrices(rates: store.pricingRates))
        if let next = rest.first {
            activeID = next.id
            step = next.area == nil ? 0 : Self.step(for: workspaceTab)
            workspaceVersion += 1
        } else {
            onFinish()
        }
    }

    static func step(for tab: ScanEditor.Tab) -> Int {
        switch tab { case .tile: 1; case .measure: 2; case .extras: 3; case .price: 4 }
    }

    /// The step pages: areas typed by hand, and choosing the kind of area.
    private var steps: some View {
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
    }

    private func go(_ newStep: Int) {
        if step == 3 || newStep > 3 { visitedExtras = true }
        withAnimation(.easeInOut(duration: 0.2)) { step = newStep }
        workspaceTab = Self.tab(for: newStep)
        openModelIfNew()
    }

    /// A scanned room's area opens its model the first time it reaches
    /// Measure with nothing measured yet (owner's call) — now its own screen
    /// for a scanned area, so only for one that isn't.
    private func openModelIfNew() {
        guard !useWorkspace, step == 2, !autoOpened, fromModel, section.area != nil, measuredSqft == 0 else { return }
        autoOpened = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editorMode = .measure }
    }

    // MARK: Step 1: area

    private var areaStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are we tiling?").font(.ndTitle(26))
            if let scan = activeScan, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PlanCanvas(room: scan, mine: [], others: otherScanAreas, interactive: false,
                               highlights: suggestions.map { ($0.title, $0.outline) })
                        .frame(height: 170)
                        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
                    Text("Found in the scan: " + suggestions.map(\.title).joined(separator: ", ")
                         + ". Choose one below, or anything else.")
                        .font(.system(size: 13)).foregroundStyle(ND.secondary)
                }
            }
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
                                } else if suggestions.contains(where: { $0.area == area }) {
                                    Text("In the scan")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Color(red: 1, green: 0.8, blue: 0.3), in: Capsule())
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

    /// What the room's scan seems to hold that the room doesn't have yet.
    private var suggestions: [ScanSuggestion] {
        guard let scan = activeScan, !handMeasured, let r = roomIndex else { return [] }
        let existing = Set(store.doc.rooms[r].sections.filter { $0.id != section.id }.compactMap(\.area))
        return scan.suggestions(skipping: existing)
    }

    private func choose(_ area: Area) {
        workspaceVersion += 1   // a different area: its screen opens afresh
        var s = section
        let firstTime = s.area == nil
        // A suggested area starts with what the scan found.
        if s.area != area, s.roomScan == nil, let found = suggestions.first(where: { $0.area == area }) {
            s.scanTakeoff = found.takeoff
        } else if s.area != area, !firstTime {
            s.scanTakeoff = nil
        }
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
                rates: store.pricingRates,
                vertical: sec.tileVertical,
                photoID: sec.tilePhotoID,
                turnedOver: sec.tileTurnedOver
            )
            // Its colour, look, grout, variation and finish (owner, 2026-10-18).
            if let t = section.fullMainTile {
                TileLookRow(title: "Tile", tile: t) { sec.wrappedValue.setMainTile($0) }
            }
            if section.area == .shower || section.area == .tub {
                Text("Walls, the shower floor and the ceiling can each have their own tile on the Measure step.")
                    .font(.system(size: 13))
                    .foregroundStyle(ND.muted)
            }
        }
        .onAppear { sec.wrappedValue.startWithUsualTile() }
    }

    // MARK: Step 3: measure

    @ViewBuilder
    private var measureStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            if section.area != nil {
                scanBlock
            }
            measureFields
        }
    }

    /// The Measure page's fields (without the scan's own card).
    @ViewBuilder
    private var measureFields: some View {
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
        return Room3DContent.otherAreas(in: store.doc.rooms[r], except: section.id)
    }

    /// This area's choices on the scan, or where it starts the first time.
    private func takeoffForEditor(_ scan: ScannedRoom) -> AreaTakeoff {
        let others = roomIndex.map { store.doc.rooms[$0].sections.filter { $0.id != section.id } } ?? []
        var t: AreaTakeoff
        if var saved = section.scanTakeoff {
            let walls = Set(scan.walls.map(\.id))
            saved.pieces.removeAll { !walls.contains($0.wallID) }      // from an earlier scan
            t = !saved.pieces.isEmpty || saved.floor != .none ? saved
                : AreaTakeoff.starting(for: section.area, room: scan, otherAreas: others)
        } else {
            t = AreaTakeoff.starting(for: section.area, room: scan, otherAreas: others)
        }
        // Wall tile out to the curb's outside edge, for showers placed before
        // that rule (owner, 2026-10-13).
        if section.area == .shower {
            let curb = StonePrices(rates: store.pricingRates).curbWidthFt
            t.fitCove(in: scan, curbWidthFt: curb)
            t.extendTileToCurb(in: scan, curbWidthFt: curb)
        }
        // A Floor area on the scanned floor: the other areas' floors as they
        // are now, and the cabinets the scanner found left untiled (once).
        if section.area == .floor, t.floor == .room, section.roomScan == nil {
            let curb = StonePrices(rates: store.pricingRates).curbWidthFt
            t.cutouts = others.filter { $0.roomScan == nil }.flatMap { $0.scanTakeoff?.floorFootprints(in: scan, curbWidthFt: curb) ?? [] }
            t.addScannedSkips(from: scan)
        }
        return t
    }

    /// The scan corrected to tape measurements, and every area measured from
    /// it moved to match and measured again.
    private func applyCalibration(_ c: ScanCalibration) {
        guard let before = activeScan else { return }
        recalibrate(before: before, after: before.calibrated(c), by: c)
    }

    private func undoCalibration() {
        guard let before = activeScan, let last = before.calibrations.last, let after = before.uncalibrated else { return }
        recalibrate(before: before, after: after, by: last.inverse)
    }

    private func recalibrate(before: ScannedRoom, after: ScannedRoom, by c: ScanCalibration) {
        let prices = StonePrices(rates: store.pricingRates)
        defer { workspaceVersion += 1 }
        if section.roomScan != nil {
            var s = section
            s.roomScan = after
            if let t = s.scanTakeoff { t.calibrated(c, before: before).apply(after, to: &s, prices: prices) }
            sec.wrappedValue = s
        } else if let r = roomIndex {
            store.doc.rooms[r].scan = after
            for i in store.doc.rooms[r].sections.indices {
                var s = store.doc.rooms[r].sections[i]
                // Only areas measured on the model; typed ones keep their numbers.
                guard s.roomScan == nil, !s.measuredByHand, let t = s.scanTakeoff,
                      !t.pieces.isEmpty || t.floor != .none else { continue }
                t.calibrated(c, before: before).apply(after, to: &s, prices: prices)
                store.doc.rooms[r].sections[i] = s
            }
            store.doc.rooms[r].refreshFloorCutouts(prices: prices)
        }
    }

    /// Scanning the room with the iPhone's LiDAR, and measuring this area on
    /// the plan it makes.
    /// The scanner and the room's model, open from Measure or Extras.
    private func scanCovers<V: View>(_ v: V) -> some View {
        v
        .fullScreenCover(item: $scanning) { target in
            RoomScanCover { room in finishScan(room, target: target) }
        }
        .fullScreenCover(item: $editorMode) { mode in
            if let scan = activeScan { modelEditor(scan, mode: mode, embedding: nil) }
        }
    }

    /// The model for this area: full screen from a step page, or embedded as
    /// the area's own screen.
    private func modelEditor(_ scan: ScannedRoom, mode: ScanEditor.Mode, embedding: ScanEditor.Embedding?) -> ScanEditor {
        ScanEditor(room: scan, area: section.area,
                           title: "\(roomName.isEmpty ? "" : roomName + " · ")\(section.area?.rawValue ?? "Area")",
                           takeoff: takeoffForEditor(scan), others: otherScanAreas, mode: mode,
                           kneeWallThicknessIn: store.rates.kneeWallThicknessIn,
                           stone: StonePrices(rates: store.pricingRates),
                           tile: section.mainTile, floorTile: section.showerFloorTile,
                           wallTiles: section.wallTiles(in: scan),
                           rates: store.pricingRates,
                           onAddPicture: { eye, target, fixtures in
                               let n = store.doc.pictures.filter { $0.sectionID == section.id }.count + 1
                               store.doc.pictures.append(EstimatePicture(sectionID: section.id, name: "View \(n)",
                                                                         eye: eye, target: target, fixtures: fixtures))
                           },
                           embedding: embedding,
                           onUse: { [areaID = currentID] t, room in
                               let sec = sectionBinding(areaID)
                               let section = sec.wrappedValue
                               guard store.doc.rooms.first(where: { $0.id == roomID })?.sections.contains(where: { $0.id == areaID }) == true else { return }
                               // Walls drawn in belong to the scan, for every area using it.
                               if room != scan {
                                   if section.roomScan != nil {
                                       sec.wrappedValue.roomScan = room
                                   } else if let r = roomIndex {
                                       store.doc.rooms[r].scan = room
                                       // Every other area measured on the model follows the room's
                                       // changes (walls moved, split or deleted) and is measured again.
                                       for i in store.doc.rooms[r].sections.indices where store.doc.rooms[r].sections[i].id != section.id {
                                           var other = store.doc.rooms[r].sections[i]
                                           guard other.roomScan == nil, !other.measuredByHand, let ot = other.scanTakeoff,
                                                 !ot.pieces.isEmpty || ot.floor != .none else { continue }
                                           ot.following(old: scan, new: room).apply(room, to: &other, prices: StonePrices(rates: store.pricingRates))
                                           store.doc.rooms[r].sections[i] = other
                                       }
                                   }
                               }
                               var s = section
                               var t = t
                               // On the model, what's placed is what's there (counts follow it).
                               t.itemsPlaced = true
                               t.apply(room, to: &s, prices: StonePrices(rates: store.pricingRates))
                               sec.wrappedValue = s
                               // A Floor area in the room leaves out every shower floor (and its curb).
                               if section.roomScan == nil, let r = roomIndex {
                                   store.doc.rooms[r].refreshFloorCutouts(prices: StonePrices(rates: store.pricingRates))
                               }
                           },
                           onRescan: {
                               editorMode = nil
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                   scanning = section.roomScan != nil ? .area : .room
                               }
                           })
    }

    @ViewBuilder
    private var scanBlock: some View {
        Group {
            if activeScan != nil, handMeasured {
                NDCard {
                    HStack(spacing: 12) {
                        Label("Measured by hand", systemImage: "keyboard").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button("Use the model instead") {
                            sec.wrappedValue.measuredByHand = false
                            editorMode = .measure
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ND.link)
                    }
                    .padding(14)
                }
            } else if let scan = activeScan {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(section.roomScan != nil ? "This area's scan" : "Room scan", systemImage: "viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Menu {
                            if RoomScanner.isAvailable {
                                Button { scanning = .room } label: { Label("Scan the room again", systemImage: "viewfinder") }
                                Button { scanning = .area } label: { Label("Scan just this area", systemImage: "square.dashed") }
                            }
                            Button { sec.wrappedValue.measuredByHand = true } label: {
                                Label("Enter by hand instead", systemImage: "keyboard")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 18))
                        }
                        #if DEBUG
                        if !RoomScanner.isAvailable {
                            Button("Sample room") { finishScan(ScannedRoom.sample.turned(by: 27), target: .room) }
                                .font(.system(size: 14, weight: .medium))
                        }
                        #endif
                    }
                    Button { editorMode = .measure } label: {
                        PlanCanvas(room: scan, mine: section.scanTakeoff?.pieces ?? [], others: otherScanAreas, interactive: false,
                                   floorRectShown: section.scanTakeoff?.floor == .drawn ? section.scanTakeoff?.floorRect : nil)
                            .frame(height: 150)
                            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    if let t = section.scanTakeoff {
                        Text(scanSummary(t, scan)).font(.system(size: 14)).foregroundStyle(ND.secondary)
                    }
                    if !scan.sketched { Button { calibrating = true } label: {
                        Label(scan.calibrations.isEmpty ? "Calibrate with a tape measure" : "Calibrated · check or calibrate again",
                              systemImage: scan.calibrations.isEmpty ? "ruler" : "checkmark.seal")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .sheet(isPresented: $calibrating) {
                        CalibrateScanSheet(room: scan, onApply: { applyCalibration($0) },
                                           onUndo: scan.calibrations.isEmpty ? nil : { undoCalibration() })
                    } }
                    Button { editorMode = .measure } label: {
                        Label(measuredSqft > 0 ? "Edit on the model" : "Choose on the model", systemImage: "cube")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NDPrimaryButtonStyle())
                }
                .padding(14)
                .background(ND.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ND.border))
            } else {
                // No model of the room yet (e.g. a sketch cancelled when the
                // room was added; owner, 2026-10-15): sketch or scan it from here.
                HStack(spacing: 10) {
                    Button { sketchingRoom = true } label: {
                        Label("Sketch this room", systemImage: "pencil.and.ruler").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NDSecondaryButtonStyle())
                    if RoomScanner.isAvailable {
                        Button { scanning = .room } label: {
                            Label("Scan this room", systemImage: "viewfinder").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NDSecondaryButtonStyle())
                    }
                }
                if !RoomScanner.isAvailable { sampleScanButton }
            }
        }
        .sheet(isPresented: $sketchingRoom) {
            NDSketchRoomSheet(roomName: roomIndex.map { store.doc.rooms[$0].name } ?? "Room") { sketch in
                guard let r = roomIndex else { return }
                store.doc.rooms[r].scan = sketch
                // The room's areas with nothing typed yet go on the model, this one too.
                let blank = store.doc.rooms[r].sections.filter {
                    $0.area != nil && ($0.id == section.id || ($0.measurements == Measurements() && $0.walls.isEmpty))
                }.map(\.id)
                store.doc.rooms[r].placeAreas(blank, prices: StonePrices(rates: store.pricingRates))
                sec.wrappedValue.measuredByHand = false
                finishScan(sketch, target: .room)
            }
        }
    }

    @ViewBuilder
    private var sampleScanButton: some View {
        #if DEBUG
        Button("Use a sample room (no LiDAR here)") { finishScan(ScannedRoom.sample.turned(by: 27), target: .room) }
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
        workspaceVersion += 1
        // A step page opens the model full screen; the area's own screen already shows it.
        if !useWorkspace { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { editorMode = .measure } }
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
                if on, fromModel, let scan = activeScan, let t = s.scanTakeoff {
                    // A wall each, from the model.
                    s.walls = [TiledWall(name: "", tile: s.ndMainTile ?? .usual)]
                    t.apply(scan, to: &s, prices: StonePrices(rates: store.pricingRates))
                } else if on {
                    let tile = s.ndMainTile ?? .usual
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
                if !fromModel {
                    Button {
                        let tile = section.walls.last?.tile ?? section.ndMainTile ?? .usual
                        sec.wrappedValue.walls.append(TiledWall(name: "Wall \(section.walls.count + 1)", tile: tile))
                    } label: {
                        Label("Add wall", systemImage: "plus").font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(ND.link)
                }
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
            if fromModel {
                Text(ND.number(wall.sqft)).font(.system(size: 16, weight: .semibold).monospacedDigit())
            } else {
                NDNumberField(placeholder: "0", value: w.sqft, alignment: .trailing)
                    .frame(width: 76)
            }
            Text("sq ft").font(.system(size: 13)).foregroundStyle(ND.muted)
            Menu {
                Button { editing = .wall(wall.id) } label: { Label("Change tile", systemImage: "square.grid.2x2") }
                Button(role: .destructive) {
                    sec.wrappedValue.walls.removeAll { $0.id == wall.id }
                } label: { Label("Remove wall", systemImage: "trash") }
                .disabled(section.walls.count <= 1 || fromModel)
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
                                turnOn: { sec.wrappedValue.showerFloorTile = section.ndMainTile ?? .usual; editing = .floor },
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
                        if fromModel { remeasure { $0.tileCeiling = false } }
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
                                turnOn: { sec.wrappedValue.ceilingTile = section.ndMainTile ?? .usual; editing = .ceiling },
                                turnOff: { sec.wrappedValue.ceilingTile = nil })
            } else {
                Button("Tile the ceiling") {
                    if fromModel { remeasure { $0.tileCeiling = true } } else { sec.wrappedValue.measurements.ceilingSqft = 1 }
                }
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

    /// Measured on the room's model rather than typed.
    private var fromModel: Bool { activeScan != nil && !handMeasured }

    /// Typed, not from the model: chosen so, or measured by hand before the
    /// room had a scan (it moves to the model only when asked).
    private var handMeasured: Bool {
        section.measuredByHand || (section.scanTakeoff == nil && measuredSqft > 0)
    }

    @ViewBuilder
    private func sqftField(_ value: Binding<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(ND.secondary)
            if fromModel {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ND.number(value.wrappedValue)).font(.system(size: 22, weight: .semibold).monospacedDigit())
                    Text("from the model").font(.system(size: 13)).foregroundStyle(ND.muted)
                }
            } else {
                NDNumberField(placeholder: "0", value: value, font: .system(size: 22, weight: .semibold))
            }
        }
    }

    /// A change to the model's choices for this area, measured again.
    private func remeasure(_ change: (inout AreaTakeoff) -> Void) {
        guard let scan = activeScan else { return }
        var t = takeoffForEditor(scan)
        change(&t)
        var s = section
        t.apply(scan, to: &s, prices: StonePrices(rates: store.pricingRates))
        sec.wrappedValue = s
        workspaceVersion += 1
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
        case .main:
            NDTileSheet(title: section.area == .floor ? "Floor tile"
                            : section.area == .shower || section.area == .tub ? "Wall tile" : "\(section.area?.rawValue ?? "Area") tile",
                        tile: mainTileBinding, rates: store.pricingRates, suggestions: roomTiles)
        case .allWalls(let wallID):
            let name = activeScan.flatMap { s in s.wall(wallID).map { s.name(of: $0) } } ?? "This wall"
            NDTileSheet(title: "All walls", tile: mainTileBinding, rates: store.pricingRates, suggestions: roomTiles,
                        note: "\(name) shares one tile with every wall of this \(section.area?.rawValue.lowercased() ?? "area").",
                        noteAction: ("Give \(name) its own tile", {
                            separateWallsOnModel()
                            editing = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                if let tw = section.walls.first(where: { $0.name == name }) { editing = .wall(tw.id) }
                            }
                        }))
        case .wall(let id):
            NDTileSheet(title: section.walls.first { $0.id == id }?.name ?? "Wall",
                        tile: wallBinding(id).tile, rates: store.pricingRates, suggestions: roomTiles)
        case .floor:
            NDTileSheet(title: "Shower floor tile",
                        tile: Binding(get: { section.showerFloorTile ?? section.fullMainTile ?? .usual },
                                      set: { sec.wrappedValue.showerFloorTile = $0 == section.fullMainTile ? nil : $0 }),
                        rates: store.pricingRates, suggestions: roomTiles)
        case .decorative(let id):
            let item = decorativeBinding(id)
            NDTileSheet(title: "\(item.wrappedValue.kind.rawValue) tile", tile: item.tile, rates: store.pricingRates)
        case .ceiling:
            NDTileSheet(title: "Ceiling tile",
                        tile: Binding(get: { section.ceilingTile ?? .usual },
                                      set: { sec.wrappedValue.ceilingTile = $0 }),
                        rates: store.pricingRates, suggestions: roomTiles)
        }
    }

    // MARK: Step 4: extras

    /// A scanned area's built-ins: what's on the model, and Add on the model.
    private var modelExtras: some View {
        let t = section.scanTakeoff
        let scan = activeScan
        let stone = scan.map { s in
            (t?.trimPieces(in: s, area: section.area, curbHeightIn: store.pricingRates.curbHeightIn) ?? []).filter(\.stone)
        } ?? []
        let counts: [(String, Int)] = [
            ("niche", t?.items.filter { $0.kind == .niche }.count ?? 0),
            ("window", t?.items.filter { $0.kind == .window }.count ?? 0),
            ("framed bench", t?.items.filter { $0.kind == .framedBench }.count ?? 0),
            ("floating bench", t?.items.filter { $0.kind == .floatingBench }.count ?? 0),
            ("corner shelf", t?.items.filter { $0.kind == .cornerShelf }.count ?? 0),
            ("corner seat", t?.items.filter { $0.kind == .cornerSeat }.count ?? 0),
            ("corner footrest", t?.items.filter { $0.kind == .cornerFootrest }.count ?? 0),
        ]
        let listed = counts.filter { $0.1 > 0 }.map { "\($0.1) \($0.0)\($0.1 == 1 ? "" : ($0.0.hasSuffix("h") ? "es" : "s"))" }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Built-ins").font(.ndTitle(22))
            NDCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(listed.isEmpty ? "Nothing added yet." : listed.joined(separator: " · "))
                        .font(.system(size: 15, weight: .semibold))
                    if !stone.isEmpty {
                        Text("Stone: " + stone.map { $0.name.lowercased() }.joined(separator: ", "))
                            .font(.system(size: 13)).foregroundStyle(ND.muted)
                    } else if section.area == .shower {
                        Text("No stone pieces; the curb, caps and jambs are tile.")
                            .font(.system(size: 13)).foregroundStyle(ND.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            Button { editorMode = .extras } label: {
                Label("Add on the model", systemImage: "cube")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NDPrimaryButtonStyle())
            Text("Niches, windows, benches, corner pieces and stone are placed on the model; their counts and prices follow it.")
                .font(.system(size: 13)).foregroundStyle(ND.muted)
        }
    }

    private var extrasStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            extrasBuiltIns
            extrasRest
        }
    }

    @ViewBuilder
    private var extrasBuiltIns: some View {
        let onFloor = section.area == .floor
        VStack(alignment: .leading, spacing: 20) {
            if fromModel && !onFloor {
                modelExtras
            } else {
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
            }
        }
    }

    /// Bands, borders, inlays and other charges.
    private var extrasRest: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                if step < 4 { go(step + 1) } else { finishOrNext() }
            } label: {
                HStack(spacing: 6) {
                    Text(step < 4 ? "Next: \(NDProgress.steps[step + 1].lowercased())"
                         : nextArea.map { "Next: \(Self.areaName($0, in: roomSections))" } ?? "Done")
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
    /// Long side up, and a photo of the real tile (owner, 2026-10-09); nil
    /// where a screen doesn't keep them.
    var vertical: Binding<Bool>? = nil
    var photoID: Binding<String?>? = nil
    /// Fishscale round side down.
    var turnedOver: Binding<Bool>? = nil

    private var isMosaic: Bool { size == .mosaic }
    private var isMultiTile: Bool { !isMosaic && layout == .multiTile }
    @State private var pickedPhoto: PhotosPickerItem? = nil
    @State private var takingPhoto = false

    /// The tile as chosen so far, for the 3-D swatch.
    private var choice: TileChoice? {
        guard let type, let size else { return nil }
        return TileChoice(tileType: type, tileSize: size, layout: layout ?? .straightStacked,
                          tileWidthIn: width, tileLengthIn: length, mosaicStyle: mosaicStyle, pieces: pieces,
                          vertical: vertical?.wrappedValue ?? false, photoID: photoID?.wrappedValue,
                          turnedOver: turnedOver?.wrappedValue ?? false)
    }
    /// Shapes with a long side, which can run across or up.
    private var hasLongSide: Bool {
        if isMosaic { return mosaicStyle == .pill || mosaicStyle == .picket || mosaicStyle == .diamond }
        guard !isMultiTile, let size else { return false }
        return [.rectangle, .picket, .pill, .trapezoid].contains(size)
            && ![.diagonal, .diagonalHerringbone, .herringbone, .doubleHerringbone, .basketweave, .versailles, .hopscotch]
                .contains(layout ?? .straightStacked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                NDLabel("Material")
                NDFlow {
                    ForEach(TileType.choices) { t in
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
                        ForEach(TileSize.choices.filter { $0 != .mosaic }) { s in
                            NDChip(title: s.rawValue, selected: size == s) { size = s }
                        }
                    }
                }
                sizeFields
            }
            if hasLongSide, let vertical {
                VStack(alignment: .leading, spacing: 10) {
                    NDLabel("Long side")
                    NDFlow {
                        NDChip(title: "Across (horizontal)", selected: !vertical.wrappedValue) { vertical.wrappedValue = false }
                        NDChip(title: "Up (vertical)", selected: vertical.wrappedValue) { vertical.wrappedValue = true }
                    }
                }
            }
            if let turnedOver, size == .fishscale || (isMosaic && mosaicStyle == .fishscale) {
                VStack(alignment: .leading, spacing: 10) {
                    NDLabel("Round side")
                    NDFlow {
                        NDChip(title: "Up", selected: !turnedOver.wrappedValue) { turnedOver.wrappedValue = false }
                        NDChip(title: "Down", selected: turnedOver.wrappedValue) { turnedOver.wrappedValue = true }
                    }
                }
            }
            if let choice { swatch(choice) }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   let id = TilePhotos.save(image) {
                    photoID?.wrappedValue = id
                }
                pickedPhoto = nil
            }
        }
        .sheet(isPresented: $takingPhoto) {
            CameraPicker { image in
                if let image, let id = TilePhotos.save(image) { photoID?.wrappedValue = id }
                takingPhoto = false
            }
            .ignoresSafeArea()
        }
    }

    /// How the tile looks in the 3-D view, about two feet of it, with the
    /// photo of the real tile when there is one.
    private func swatch(_ t: TileChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("In 3-D")
            HStack(alignment: .top, spacing: 14) {
                let made = TilePattern.make(t)
                let span = max(12, min(48, 4 * TilePattern.drawnSize(t).0))
                Canvas { ctx, size in
                    // `span` inches across the box, the repeat drawn at that scale.
                    let ptPerIn = size.width / span
                    let tw = made.periodIn.width * ptPerIn, th = made.periodIn.height * ptPerIn
                    let image = ctx.resolve(Image(uiImage: made.image))
                    var y = 0.0
                    while y < size.height {
                        var x = 0.0
                        while x < size.width { ctx.draw(image, in: CGRect(x: x, y: y, width: tw, height: th)); x += tw }
                        y += th
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ND.border))
                if let photoID {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(photoID.wrappedValue == nil ? "Add a photo of the real tile and the 3-D view uses it for each tile's face."
                                                         : "Using your photo of the tile.")
                            .font(.system(size: 13)).foregroundStyle(ND.secondary)
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Label(photoID.wrappedValue == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                        }
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { takingPhoto = true } label: { Label("Take photo", systemImage: "camera") }
                        }
                        if photoID.wrappedValue != nil {
                            Button(role: .destructive) { photoID.wrappedValue = nil } label: { Label("Remove photo", systemImage: "trash") }
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(ND.link)
                }
            }
        }
    }

    // MARK: Layout

    private var layoutGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            NDLabel("Layout")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Layout.choices) { l in
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
        case .checkerboard:
            // A grid, every other tile hatched: the second colour.
            for i in 1...2 { line(0, CGFloat(i) / 3, 1, CGFloat(i) / 3) }
            for i in 1...3 { line(CGFloat(i) / 4, 0, CGFloat(i) / 4, 1) }
            for cx in 0..<4 {
                for cy in 0..<3 where (cx + cy).isMultiple(of: 2) {
                    let x0 = CGFloat(cx) / 4, y0 = CGFloat(cy) / 3
                    for k in 1...3 {
                        let f = CGFloat(k) / 4
                        line(x0 + f / 4, y0, x0, y0 + f / 3)
                        line(x0 + 0.25, y0 + f / 3, x0 + f / 4, y0 + 1.0 / 3)
                    }
                }
            }
        case .randomOffset:
            // Rows of planks, their joints staggered at random.
            for i in 1...3 { line(0, CGFloat(i) / 4, 1, CGFloat(i) / 4) }
            for (row, xs) in [[0.55], [0.2, 0.85], [0.4], [0.1, 0.7]].enumerated() {
                for x in xs { line(x, CGFloat(row) / 4, x, CGFloat(row + 1) / 4) }
            }
        case .runningBond:
            for i in 1...2 { line(0, CGFloat(i) / 3, 1, CGFloat(i) / 3) }
            for x in [0.33, 0.73] { line(x, 0, x, 1.0 / 3); line(x, 2.0 / 3, x, 1) }
            for x in [0.13, 0.53, 0.93] { line(x, 1.0 / 3, x, 2.0 / 3) }
        case .diagonal:
            for i in stride(from: -0.6, through: 1.0, by: 0.4) { line(i, 1, i + 0.65, 0) }
            for i in stride(from: 0.0, through: 1.6, by: 0.4) { line(i - 0.65, 0, i, 1) }
        case .herringbone, .diagonalHerringbone, .doubleHerringbone:
            // 3:1 planks in a herringbone: staircases of alternating
            // horizontal and vertical planks, repeated every (L, -L) — as
            // the 3-D view draws Herringbone; Diagonal Herringbone turns it
            // 45° so the planks form V rows; Double pairs each plank.
            let pw: CGFloat = layout == .doubleHerringbone ? 2 : 1, pl: CGFloat = 3
            let unit = h / 5.5
            let turn = CGAffineTransform(translationX: r.midX, y: r.midY)
                .rotated(by: layout == .diagonalHerringbone ? .pi / 4 : 0)
                .scaledBy(x: unit, y: unit)
            for m in -8...8 {
                for k in -12...12 {
                    let ox = CGFloat(k) * pw + CGFloat(m) * pl
                    let oy = CGFloat(k) * pw - CGFloat(m) * pl
                    p.addRect(CGRect(x: ox, y: oy, width: pl, height: pw), transform: turn)
                    p.addRect(CGRect(x: ox, y: oy + pw, width: pw, height: pl), transform: turn)
                    if layout == .doubleHerringbone {
                        p.move(to: CGPoint(x: ox, y: oy + pw / 2).applying(turn))
                        p.addLine(to: CGPoint(x: ox + pl, y: oy + pw / 2).applying(turn))
                        p.move(to: CGPoint(x: ox + pw / 2, y: oy + pw).applying(turn))
                        p.addLine(to: CGPoint(x: ox + pw / 2, y: oy + pw + pl).applying(turn))
                    }
                }
            }
        case .oneThirdOffset:
            for i in 1...2 { line(0, CGFloat(i) / 3, 1, CGFloat(i) / 3) }
            for (row, xs) in [[0.2, 0.6], [0.33, 0.73], [0.47, 0.87]].enumerated() {
                for x in xs { line(x, CGFloat(row) / 3, x, CGFloat(row + 1) / 3) }
            }
        case .chevron:
            // Planks cut at 45°: zigzag rows.
            for row in stride(from: -1.0, through: 1.5, by: 0.34) {
                var x = 0.0
                while x < 1 {
                    line(x, row + 0.25, x + 0.25, row); line(x + 0.25, row, x + 0.5, row + 0.25)
                    x += 0.5
                }
            }
            for x in stride(from: 0.25, through: 1, by: 0.25) { line(x, 0, x, 1) }
        case .basketweave:
            for bx in 0..<4 {
                for by in 0..<2 {
                    let x0 = CGFloat(bx) / 4, y0 = CGFloat(by) / 2
                    if (bx + by).isMultiple(of: 2) { line(x0, y0 + 0.25, x0 + 0.25, y0 + 0.25) }
                    else { line(x0 + 0.125, y0, x0 + 0.125, y0 + 0.5) }
                }
            }
            for i in 1...3 { line(CGFloat(i) / 4, 0, CGFloat(i) / 4, 1) }
            line(0, 0.5, 1, 0.5)
        case .versailles:
            // Four sizes of square and rectangle in a block.
            let u = h / 6
            for (x, y, bw, bh) in [(0, 0, 3, 2), (3, 0, 2, 2), (5, 0, 1, 2), (0, 2, 2, 3), (2, 2, 1, 1), (3, 2, 2, 1), (5, 2, 1, 1),
                                   (2, 3, 1, 2), (3, 3, 3, 2), (0, 5, 2, 1), (2, 5, 2, 1), (4, 5, 2, 1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                for ox in [0, 6] as [CGFloat] {
                    p.addRect(CGRect(x: r.minX + (x + ox) * u, y: r.minY + y * u, width: bw * u, height: bh * u).intersection(r))
                }
            }
        case .hopscotch:
            // Big squares with a small square at each one's corner.
            let s = h / 2.5
            for i in -2...4 {
                for j in -2...3 {
                    let x = r.minX + CGFloat(i) * 2 * s - CGFloat(j) * s, y = r.minY + CGFloat(i) * s + CGFloat(j) * 2 * s
                    for box in [CGRect(x: x, y: y, width: 2 * s, height: 2 * s), CGRect(x: x + 2 * s, y: y, width: s, height: s)] {
                        let c = box.intersection(r)
                        if !c.isNull, c.width > 0.5, c.height > 0.5 { p.addRect(c) }
                    }
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
    /// Tiles already used in the room, one tap each (owner's pick, 2026-10-12).
    var suggestions: [Suggestion] = []
    var note: String? = nil
    var noteAction: (String, () -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    struct Suggestion: Identifiable {
        let label: String
        let tile: TileChoice
        var id: String { label }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 18) {
                if let note {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note).font(.system(size: 14)).foregroundStyle(ND.secondary)
                        if let noteAction {
                            Button(noteAction.0, action: noteAction.1)
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(ND.link)
                        }
                    }
                }
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        NDLabel("Use a tile from this room")
                        ForEach(suggestions) { s in
                            let on = s.tile == tile
                            Button { tile = s.tile } label: {
                                HStack(spacing: 12) {
                                    NDTileSwatch(tile: s.tile).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.label).font(.system(size: 15, weight: .semibold))
                                        Text(s.tile.ndSummary).font(.system(size: 13)).foregroundStyle(ND.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 4)
                                    if on { Image(systemName: "checkmark").foregroundStyle(ND.link) }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(on ? ND.link : ND.border, lineWidth: on ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                        NDLabel("Or choose").padding(.top, 6)
                    }
                }
                NDTileFields(
                    type: Binding(get: { tile.tileType }, set: { if let v = $0 { tile.tileType = v } }),
                    size: Binding(get: { tile.tileSize }, set: { tile.tileSize = $0 ?? .rectangle }),
                    layout: Binding(get: { tile.layout }, set: { if let v = $0 { tile.layout = v } }),
                    width: $tile.tileWidthIn,
                    length: $tile.tileLengthIn,
                    mosaicStyle: $tile.mosaicStyle,
                    pieces: $tile.pieces,
                    rates: rates,
                    vertical: $tile.vertical,
                    photoID: $tile.photoID,
                    turnedOver: $tile.turnedOver
                )
                TileLookRow(title: title, tile: tile) { tile = $0 }
              }
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


/// Puts the area's scanner and model covers on a view.
private struct ScanCoversModifier<Out: View>: ViewModifier {
    let apply: (AnyView) -> Out
    func body(content: Content) -> some View { apply(AnyView(content)) }
}

/// The camera, for a photo of a tile.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}


/// A patch of tile as the 3-D view draws it, `spanIn` inches across.
struct NDTileSwatch: View {
    let tile: TileChoice
    var spanIn: Double? = nil

    var body: some View {
        let made = TilePattern.make(tile)
        let span = spanIn ?? max(12, min(48, 4 * TilePattern.drawnSize(tile).0))
        Canvas { ctx, size in
            let ptPerIn = size.width / span
            let tw = made.periodIn.width * ptPerIn, th = made.periodIn.height * ptPerIn
            let image = ctx.resolve(Image(uiImage: made.image))
            var y = 0.0
            while y < size.height {
                var x = 0.0
                while x < size.width { ctx.draw(image, in: CGRect(x: x, y: y, width: tw, height: th)); x += tw }
                y += th
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ND.border))
    }
}

extension EstimateSection {
    /// The main tile with its orientation, photo and side, as one choice.
    var fullMainTile: TileChoice? {
        guard var t = ndMainTile else { return nil }
        t.vertical = tileVertical
        t.photoID = tilePhotoID
        t.turnedOver = tileTurnedOver
        t.appearance = tileAppearance
        return t
    }

    mutating func setMainTile(_ t: TileChoice) {
        tileType = t.tileType
        tileSize = t.tileSize
        layout = t.layout
        tileWidthIn = t.tileWidthIn
        tileLengthIn = t.tileLengthIn
        mosaicStyle = t.mosaicStyle
        multiTilePieces = t.pieces
        tileVertical = t.vertical
        tilePhotoID = t.photoID
        tileTurnedOver = t.turnedOver
        tileAppearance = t.appearance
    }
}
