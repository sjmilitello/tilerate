import SwiftUI

// Measuring an area from a room scan: the floor plan on top (pinch to zoom,
// drag to pan, double-tap to fit, tap a wall to tile it), the chosen wall
// face-on underneath (drag a piece's sides to where the tile starts and stops,
// drag its top to its height, tap a door or window to take it off), then the
// floor and ceiling. Everything snaps to the inch and to edges nearby.

/// Another area in the same room, shown faintly so walls aren't counted twice.
struct OtherAreaPieces: Equatable {
    let name: String
    let pieces: [AreaTakeoff.Piece]
    var floor: AreaTakeoff.FloorRect? = nil
    /// For the 3-D view: its tile, its floor's tile, and whether it tiles the room's floor.
    var tile: TileChoice? = nil
    var floorTile: TileChoice? = nil
    var roomFloor: Bool = false
}

struct ScanEditor: View {
    /// Which step it's opened from: Measure (walls, tile, floor, ceiling,
    /// walls drawn in, doors) or Extras (niches, windows, benches, corner
    /// pieces, stone).
    enum Mode: String, Identifiable { case measure, extras; var id: String { rawValue } }

    let area: Area?
    var mode: Mode = .measure
    let title: String
    let others: [OtherAreaPieces]
    /// A new knee wall's thickness, from Admin.
    let kneeWallThicknessIn: Double
    /// Stone prices and the curb height, from Admin.
    let stone: StonePrices
    /// This area's tile and floor tile, for the 3-D view.
    let tile: TileChoice?
    let floorTile: TileChoice?
    /// "Add to estimate" in 3-D: the camera (eye, target) and whether fixtures show.
    var onAddPicture: (([Double], [Double], Bool) -> Void)? = nil
    /// The area's choices, and the room with any walls drawn in.
    let onUse: (AreaTakeoff, ScannedRoom) -> Void
    let onRescan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var room: ScannedRoom
    @State private var takeoff: AreaTakeoff
    @State private var selectedWall: UUID? = nil
    @State private var selectedPiece: UUID? = nil
    @State private var face = 0
    @State private var addingWall = false
    /// The wall being placed is a full wall (else a half wall).
    @State private var addingFullWall = false
    /// Waiting for a tap on the corner the shower goes in.
    @State private var placingShower = false
    /// Tapping a wall chooses it to change its shape (any wall, scanned or
    /// drawn in), rather than tiling it.
    @State private var editingWalls = false
    /// The room and this area as a drag began: each step of the drag is
    /// worked out from them.
    @State private var dragBase: (room: ScannedRoom, takeoff: AreaTakeoff)? = nil
    @State private var splitAtIn: Double = 0
    @State private var confirmDeleteScanned = false
    /// Waiting for a tap on the wall a framed bench goes against.
    @State private var placingBench = false
    /// The chosen bench, niche, window or corner piece.
    @State private var selectedItem: UUID? = nil
    /// A message about something that couldn't be placed.
    @State private var placeNote: String? = nil
    /// The room in 3-D instead of the plan.
    @State private var show3D = false
    /// Wall lengths round the outside of the 2-D plan.
    @State private var showDimensions = true
    /// Waiting for a tap in 3-D on the wall where this goes.
    @State private var placing3D: Place3D? = nil

    enum Place3D: String, CaseIterable, Identifiable {
        case door, window, niche, cornerShelf, cornerSeat, cornerFootrest, floatingBench, framedBench
        var id: String { rawValue }
        var title: String {
            switch self {
            case .door: "Door"
            case .window: "Window"
            case .niche: "Niche"
            case .cornerShelf: "Corner shelf"
            case .cornerSeat: "Corner seat"
            case .cornerFootrest: "Corner footrest"
            case .floatingBench: "Floating bench"
            case .framedBench: "Framed bench"
            }
        }
        var symbol: String {
            switch self {
            case .door: "door.left.hand.open"
            case .window: "window.horizontal"
            case .niche: "square.split.1x2"
            case .cornerShelf, .cornerSeat, .cornerFootrest: "triangle"
            case .floatingBench: "rectangle.split.1x2"
            case .framedBench: "square.bottomhalf.filled"
            }
        }
    }
    @State private var showFixtures = true
    /// An open side of the shower floor tapped on the plan: offer to close it.
    @State private var closingSide: AreaTakeoff.OpenSide? = nil
    @State private var askClose = false
    /// As the editor opened: Cancel asks before throwing changes away.
    private let openedRoom: ScannedRoom
    private let openedTakeoff: AreaTakeoff
    @State private var askDiscard = false
    @State private var confirmDeleteWall = false

    init(room: ScannedRoom, area: Area?, title: String, takeoff: AreaTakeoff, others: [OtherAreaPieces],
         mode: Mode = .measure,
         kneeWallThicknessIn: Double = 4.5, stone: StonePrices = .init(),
         tile: TileChoice? = nil, floorTile: TileChoice? = nil,
         onAddPicture: (([Double], [Double], Bool) -> Void)? = nil,
         onUse: @escaping (AreaTakeoff, ScannedRoom) -> Void, onRescan: @escaping () -> Void) {
        _room = State(initialValue: room)
        openedRoom = room
        openedTakeoff = takeoff
        self.kneeWallThicknessIn = kneeWallThicknessIn
        self.stone = stone
        self.tile = tile
        self.floorTile = floorTile
        self.onAddPicture = onAddPicture
        self.area = area
        self.mode = mode
        self.title = title
        self.others = others
        self.onUse = onUse
        self.onRescan = onRescan
        _takeoff = State(initialValue: takeoff)
        _selectedWall = State(initialValue: takeoff.pieces.first?.wallID)
        _selectedPiece = State(initialValue: takeoff.pieces.first?.id)
    }

    private var usesWalls: Bool { area != .floor }
    private var openSides: [AreaTakeoff.OpenSide] { area == .shower ? takeoff.openSides(in: room) : [] }

    private var content3D: Room3DContent {
        let stoneParts = Set(takeoff.trimPieces(in: room, area: area, curbHeightIn: stone.curbHeightIn).filter(\.stone).map(\.key))
        return Room3DContent(room: room, takeoff: takeoff, area: area, tile: tile, floorTile: floorTile, others: others,
                             curbHeightIn: takeoff.curbHeightIn ?? stone.curbHeightIn, stoneParts: stoneParts,
                             showFixtures: showFixtures, selectedItem: selectedItem)
    }
    private var otherPieces: [AreaTakeoff.Piece] { others.flatMap(\.pieces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                if show3D {
                    Room3DView(content: content3D, showFixtures: $showFixtures, onTap: { tap3D($0) },
                               onCapture: onAddPicture.map { add in { eye, target in add(eye, target, showFixtures) } })
                        .frame(height: 250)
                        .overlay(alignment: .topTrailing) {
                            if area == .shower || (mode == .extras && usesWalls) {
                                Menu {
                                    ForEach(Place3D.allCases.filter { mode == .measure ? $0 == .door : $0 != .door }) { p in
                                        Button { placing3D = p } label: { Label(p.title, systemImage: p.symbol) }
                                    }
                                } label: {
                                    Label("Place", systemImage: "plus")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                                .padding(8)
                            }
                        }
                } else {
                PlanCanvas(room: room, mine: takeoff.pieces, others: others, selectedWall: selectedWall,
                           floorRect: takeoff.floor == .drawn ? $takeoff.floorRect : nil,
                           onTapPoint: placingShower ? { p in
                               placingShower = false
                               if !takeoff.placeShower(near: p, in: room) {
                                   placeNote = "There's no corner there. Tap near the corner where the shower goes."
                               }
                           } : nil,
                           onResetFloor: placeShowerFloor,
                           onFloorChanged: area == .shower ? { takeoff.tileWallsAroundFloor(in: room) } : nil,
                           curbEdges: area == .shower ? takeoff.curbEdges(in: room) : [],
                           items: takeoff.items,
                           showDimensions: showDimensions,
                           hint: addingWall ? nil : (editingWalls && mode == .measure ? "Tap a wall to change it · pinch to zoom"
                                : !usesWalls ? "Pinch to zoom"
                                : mode == .extras ? "Tap a wall to add to it · pinch to zoom" : "Tap a wall to tile it · pinch to zoom"),
                           addingWall: addingWall,
                           onAddWall: { a, b in addDrawnWall(from: a, to: b) },
                           onMovePlannedEnd: { id, start, p in
                               room.movePlannedEnd(id, start: start, to: p)
                               clampPieces(on: id)
                           },
                           onMovePlannedWall: { original, d in
                               let guides = takeoff.newWallLines(in: room, thicknessIn: original.thicknessIn).flatMap { [$0.0, $0.1] }
                               room.movePlannedWall(original, by: d, guides: guides)
                           },
                           editAnyWall: editingWalls && mode == .measure,
                           onMoveWall: { id, d in editRoom { $0.moveWall(id, by: d) } },
                           onMoveWallEnd: { id, start, p in editRoom { $0.moveWallEnd(id, start: start, to: p) } },
                           onWallDragEnded: { dragBase = nil },
                           openSides: openSides.map { ($0.a, $0.b) },
                           onTapOpenSide: { i in
                               if addingWall {
                                   addingWall = false
                                   closeSide(openSides[i], door: addingFullWall)
                               } else {
                                   closingSide = openSides[i]
                                   askClose = true
                               }
                           },
                           snapNewWall: { a, b in
                               area == .shower ? takeoff.snappedNewWall(a, b, in: room, thicknessIn: kneeWallThicknessIn) : (a, b)
                           }) { wallID in
                    tapWall(wallID)
                }
                .frame(height: 250)
                }
                HStack(spacing: 8) {
                    if !show3D {
                        Toggle(isOn: $showDimensions) { Image(systemName: "ruler") }
                            .toggleStyle(.button)
                            .font(.caption)
                            .accessibilityLabel("Dimensions")
                    }
                    Picker("View", selection: $show3D) {
                        Text("2D").tag(false)
                        Text("3D").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .disabled(addingWall || placingBench || placing3D != nil)
                }
                .padding(8)
                }
                .background(Color(white: 0.09))
                .overlay(alignment: .top) {
                    if placingShower {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.tap")
                            Text("Tap the corner where the shower goes.").font(.caption)
                            Button("Cancel") { placingShower = false }.font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                    } else if let p = placing3D {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.tap")
                            Text("Tap the wall where the \(p.title.lowercased()) goes.").font(.caption)
                            Button("Cancel") { placing3D = nil }.font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                    } else if placingBench {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.tap")
                            Text("Tap the wall the bench goes against.").font(.caption)
                            Button("Cancel") { placingBench = false }.font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                    } else if let note = placeNote {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(note).font(.caption).fixedSize(horizontal: false, vertical: true)
                            Button("OK") { placeNote = nil }.font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                    }
                    if addingWall {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.draw")
                            Text((openSides.isEmpty ? "" : "Tap the curb to put the \(addingFullWall ? "full" : "half") wall on the shower opening, or ")
                                 + (openSides.isEmpty ? "Drag" : "drag") + " on the plan from where it starts to where it ends.")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                            Button("Cancel") { addingWall = false }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                    }
                }

                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(mode == .measure
                                 ? "Choose the walls, floor and ceiling being tiled. Add walls and doors that aren't built yet."
                                 : "Add niches, windows, benches and corner pieces on the walls, and choose tile or stone for each piece.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if mode == .measure {
                                Picker("Walls", selection: $editingWalls) {
                                    Text(usesWalls ? "Tile walls" : "Floor").tag(false)
                                    Text("Edit walls").tag(true)
                                }
                                .pickerStyle(.segmented)
                            }
                            if editingWalls && mode == .measure {
                                addWallMenu
                                wallPanel.id("wall")
                            } else if usesWalls {
                                if mode == .measure { addWallMenu }
                                wallPanel.id("wall")
                            } else if let id = selectedWall, let w = room.wall(id), w.planned {
                                // A floor: walls aren't tiled here, but one drawn in can be changed or deleted.
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(room.name(of: w)).font(.ndTitle(20))
                                    plannedWallControls(w)
                                }
                                .id("wall")
                            }
                            if mode == .measure, !editingWalls || area == .shower, area == .floor || area == .shower || area == .tub { floorPanel }
                            if mode == .extras { trimPanel }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: selectedWall) { _, _ in
                        withAnimation { scroller.scrollTo("wall", anchor: .top) }
                    }
                }

                totalsBar
            }
            .background(ND.ground.ignoresSafeArea())
            .confirmationDialog("Add a wall on the curb", isPresented: $askClose, titleVisibility: .visible,
                                presenting: closingSide) { side in
                Button("Full wall (with a door)") { closeSide(side, door: true) }
                Button("Half wall") { closeSide(side, door: false) }
            } message: { side in
                Text("Along the open side of the shower, \(feetAndInches(side.lengthFt)). Move or resize it after.")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if room != openedRoom || takeoff != openedTakeoff { askDiscard = true } else { dismiss() }
                    }
                    .confirmationDialog("Apply your changes?", isPresented: $askDiscard, titleVisibility: .visible) {
                        Button("Apply changes") {
                            onUse(takeoff, room)
                            dismiss()
                        }
                        Button("Discard changes", role: .destructive) { dismiss() }
                        Button("Keep editing", role: .cancel) {}
                    } message: {
                        Text("Apply keeps what you changed here, everywhere it's used. Discard goes back to how it was.")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { onRescan() } label: { Label("Scan again", systemImage: "viewfinder") }
                        if !takeoff.pieces.isEmpty {
                            Button(role: .destructive) {
                                takeoff.pieces = []
                                takeoff.subtracted = []
                                selectedPiece = nil
                            } label: { Label("Clear this area's walls", systemImage: "eraser") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Walls

    private func tapWall(_ id: UUID) {
        guard let wall = room.wall(id) else { return }
        if editingWalls && mode == .measure {
            if selectedWall != id { face = 0 }
            selectedWall = id
            splitAtIn = (wall.lengthFt * 12 / 2).rounded()
            return
        }
        if placingBench {
            placingBench = false
            addBench(on: wall, floating: false)
            return
        }
        guard usesWalls else {
            if wall.planned { selectedWall = id }
            return
        }
        // Adding extras doesn't tile walls: just choose it.
        if mode == .extras {
            if selectedWall != id { face = 0 }
            selectedWall = id
            return
        }
        if selectedWall != id { face = 0 }
        selectedWall = id
        if let mine = takeoff.pieces.first(where: { $0.wallID == id && $0.face == face })
            ?? takeoff.pieces.first(where: { $0.wallID == id }) {
            face = mine.face
            selectedPiece = mine.id
        } else if let new = takeoff.addPiece(on: wall, area: area, others: otherPieces, face: face) {
            selectedPiece = new.id
            fillShowerFloorIfBlank()
        }
    }

    /// A wall drawn on the plan: added to the room, chosen, and tiled on
    /// its first side. A full wall drawn onto the shower opening gets a door.
    private func addDrawnWall(from a: ScannedRoom.Point, to b: ScannedRoom.Point) {
        addingWall = false
        let ceiling = room.ceilingFt * 12
        let height = addingFullWall ? ceiling : min(42, ceiling)
        let onOpening = openSides.contains { s in
            let d1 = hypot(s.a.x - a.x, s.a.y - a.y) + hypot(s.b.x - b.x, s.b.y - b.y)
            let d2 = hypot(s.a.x - b.x, s.a.y - b.y) + hypot(s.b.x - a.x, s.b.y - a.y)
            return min(d1, d2) < 0.05
        }
        let w = placeWall(from: a, to: b, heightIn: height, door: addingFullWall && onOpening && area == .shower)
        if usesWalls { tapWall(w.id) } else { selectedWall = w.id }
    }

    /// Add a Wall: full or half, then tap the curb or drag on the plan.
    private var addWallMenu: some View {
        Menu {
            Button { show3D = false; addingFullWall = true; addingWall = true } label: { Label("Full Wall", systemImage: "rectangle.portrait") }
            Button { show3D = false; addingFullWall = false; addingWall = true } label: { Label("Half Wall", systemImage: "rectangle.bottomhalf.filled") }

        } label: {
            Label("Add a Wall", systemImage: "plus.rectangle.on.rectangle")
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
    }

    /// A new planned wall, with a door in its middle if asked. Where a wall
    /// drawn in already lies, that one is used instead (given a door if it
    /// has none), so two never sit one on top of the other.
    private func placeWall(from a: ScannedRoom.Point, to b: ScannedRoom.Point, heightIn: Double, door: Bool) -> ScannedRoom.Wall {
        let w = room.plannedWall(along: a, b)
            ?? room.addPlannedWall(from: a, to: b, heightIn: heightIn, thicknessIn: kneeWallThicknessIn)
        if door, !room.isKneeWall(w), !room.openings.contains(where: { $0.wallID == w.id && $0.kind == .showerDoor }) {
            _ = room.addShowerDoor(on: w, along: w.lengthFt / 2, widthIn: stone.doorWidthIn, heightIn: stone.doorHeightIn)
        }
        return w
    }

    /// A wall added on an open side of the shower floor, on the curb: a
    /// full wall with a door in its middle, or a knee wall leaving room for
    /// a door beside it (from the side's end against a wall). Its first
    /// face looks into the shower and is tiled.
    private func closeSide(_ side: AreaTakeoff.OpenSide, door: Bool) {
        var a = side.a, b = side.b
        if !door {
            let length = side.lengthFt
            let doorFt = stone.doorWidthIn / 12
            let knee = length > doorFt + 1 ? length - doorFt : length / 2
            // From the end against a wall.
            if side.startWall == nil, side.endWall != nil { swap(&a, &b) }
            let t = knee / max(length, 1e-9)
            b = .init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        // Its first face toward the shower.
        if let r = takeoff.floorRect {
            let c = r.corners
            let center = ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
            let n = ScannedRoom.Point(x: -(b.y - a.y), y: b.x - a.x)
            if (center.x - a.x) * n.x + (center.y - a.y) * n.y < 0 { swap(&a, &b) }
        }
        let ceiling = room.ceilingFt * 12
        let w = placeWall(from: a, to: b, heightIn: door ? ceiling : min(42, ceiling), door: door)
        face = 0
        tapWall(w.id)
    }

    // MARK: Benches, niches, windows and corner pieces

    private var defaults: ScanItemDefaults { stone.defaults }

    /// A bench along a wall: the shower floor's side against it, wall to
    /// wall (a framed bench may stop flush with the outside of the curb).
    private func addBench(on wall: ScannedRoom.Wall, floating: Bool) {
        let curbWidth = stone.rate(.curb).widthIn / 12
        guard let span = takeoff.benchSpan(on: wall, in: room, floating: floating, curbWidthFt: curbWidth) else {
            placeNote = floating ? "A floating bench needs a wall at each end. Choose the wall it runs along, between two walls."
                                 : "There's no room for a bench along \(room.name(of: wall).lowercased())."
            return
        }
        let item = AreaTakeoff.Item(kind: floating ? .floatingBench : .framedBench, wallID: wall.id, face: face,
                                    fromFt: span.lowerBound, toFt: span.upperBound,
                                    heightIn: floating ? defaults.floatingBenchHeightIn : defaults.framedBenchHeightIn,
                                    depthIn: floating ? defaults.floatingBenchDepthIn : defaults.framedBenchDepthIn)
        place(item, on: wall)
    }

    /// A niche or window: in the middle of this area's tile on the wall, or
    /// centred where it was tapped in 3-D.
    private func addOpening(_ kind: AreaTakeoff.Item.Kind, on wall: ScannedRoom.Wall,
                            at along: Double? = nil, centreUpIn: Double? = nil) {
        let w = (kind == .niche ? defaults.nicheWidthIn : defaults.windowWidthIn) / 12
        let h = kind == .niche ? defaults.nicheHeightIn : defaults.windowHeightIn
        let mid = along ?? takeoff.middle(of: wall, face: face)
        let from = min(max(0, mid - w / 2), max(0, wall.lengthFt - w))
        let bottom = centreUpIn.map { min(max(0, ($0 - h / 2).rounded()), wall.heightFt * 12 - h) }
            ?? (kind == .niche ? defaults.nicheBottomIn : defaults.windowBottomIn)
        let item = AreaTakeoff.Item(kind: kind, wallID: wall.id, face: face, fromFt: from, toFt: from + w,
                                    bottomIn: bottom, heightIn: h)
        place(item, on: wall)
    }

    /// A tap in the 3-D view: an item chooses it; a wall places what was
    /// picked from Place there, or else chooses the wall (and its side).
    private func tap3D(_ hit: Room3DHit) {
        switch hit.target {
        case .item(let id):
            guard let item = takeoff.items.first(where: { $0.id == id }) else { return }
            placing3D = nil
            selectedWall = item.wallID
            face = item.face
            selectedItem = id
        case .wall(let id):
            guard let wall = room.wall(id) else { return }
            let along = room.along(.init(x: Double(hit.point.x), y: Double(hit.point.z)), on: wall)
            let upIn = (Double(hit.point.y) * 12).rounded()
            // A wall drawn in has two sides: the one tapped.
            var side = 0
            if wall.planned {
                let n0 = (x: -(wall.end.y - wall.start.y), y: wall.end.x - wall.start.x)
                side = Double(hit.normal.x) * n0.x + Double(hit.normal.z) * n0.y >= 0 ? 0 : 1
            }
            guard let p = placing3D else {
                tapWall(id)
                if wall.planned {
                    face = side
                    selectedPiece = takeoff.pieces.first { $0.wallID == id && $0.face == side }?.id
                }
                return
            }
            placing3D = nil
            selectedWall = id
            face = side
            switch p {
            case .door:
                if room.isKneeWall(wall) {
                    placeNote = "A door goes in a full wall, not a half wall."
                } else if let i = room.openings.firstIndex(where: { $0.wallID == id && $0.kind == .showerDoor }) {
                    let width = room.openings[i].widthFt
                    room.openings[i].alongFt = min(max(along, width / 2), wall.lengthFt - width / 2)
                } else {
                    _ = room.addShowerDoor(on: wall, along: along, widthIn: stone.doorWidthIn, heightIn: stone.doorHeightIn)
                }
            case .window: addOpening(.window, on: wall, at: along, centreUpIn: upIn)
            case .niche: addOpening(.niche, on: wall, at: along, centreUpIn: upIn)
            case .cornerShelf: addCorner(.cornerShelf, on: wall, atStart: along < wall.lengthFt / 2, heightIn: upIn)
            case .cornerSeat: addCorner(.cornerSeat, on: wall, atStart: along < wall.lengthFt / 2, heightIn: upIn)
            case .cornerFootrest: addCorner(.cornerFootrest, on: wall, atStart: along < wall.lengthFt / 2, heightIn: upIn)
            case .floatingBench: addBench(on: wall, floating: true)
            case .framedBench: addBench(on: wall, floating: false)
            }
        }
    }

    /// A corner shelf, footrest or seat in a corner of the wall; another
    /// shelf in the same corner goes 12″ above the last.
    private func addCorner(_ kind: AreaTakeoff.Item.Kind, on wall: ScannedRoom.Wall, atStart: Bool, heightIn: Double? = nil) {
        let (size, height): (Double, Double) = switch kind {
        case .cornerShelf: (defaults.cornerShelfIn, defaults.cornerShelfHeightIn)
        case .cornerFootrest: (defaults.cornerFootrestIn, defaults.cornerFootrestHeightIn)
        default: (defaults.cornerSeatIn, defaults.cornerSeatHeightIn)
        }
        let same = takeoff.items.filter { $0.kind == kind && $0.wallID == wall.id && $0.atStart == atStart }
        let bottom = heightIn ?? (kind == .cornerShelf ? (same.map(\.bottomIn).max().map { $0 + 12 } ?? height) : height)
        let item = AreaTakeoff.Item(kind: kind, wallID: wall.id, face: face, bottomIn: min(bottom, wall.heightFt * 12),
                                    sizeIn: size, atStart: atStart)
        place(item, on: wall)
    }

    private func place(_ item: AreaTakeoff.Item, on wall: ScannedRoom.Wall) {
        takeoff.items.append(item)
        takeoff.itemsPlaced = true
        placeNote = nil
        if selectedWall != wall.id { selectedWall = wall.id }
        selectedItem = item.id
    }

    /// Add door, window, niche, corner piece or floating bench to a wall.
    @ViewBuilder
    private func wallItemButtons(_ wall: ScannedRoom.Wall) -> some View {
        if mode == .measure {
            if area == .shower, !room.isKneeWall(wall),
               !room.openings.contains(where: { $0.wallID == wall.id && $0.kind == .showerDoor }) {
                Button { addShowerDoor(on: wall) } label: { Label("Add door", systemImage: "door.left.hand.open") }
            }
        } else {
            extraButtons(wall)
        }
    }

    @ViewBuilder
    private func extraButtons(_ wall: ScannedRoom.Wall) -> some View {
        Button { addOpening(.window, on: wall) } label: { Label("Add window", systemImage: "window.horizontal") }
        Button { addOpening(.niche, on: wall) } label: { Label("Add niche", systemImage: "square.split.1x2") }
        Menu {
            // One section per corner of this wall (an end that meets another wall).
            let ends = [true, false].filter { !room.isFreeEnd(of: wall, start: $0) }
            ForEach(ends.isEmpty ? [true, false] : ends, id: \.self) { atStart in
                Section("In the \(cornerName(wall, atStart: atStart)) corner") {
                    Button("Corner shelf") { addCorner(.cornerShelf, on: wall, atStart: atStart) }
                    Button("Corner seat") { addCorner(.cornerSeat, on: wall, atStart: atStart) }
                    Button("Corner footrest") { addCorner(.cornerFootrest, on: wall, atStart: atStart) }
                }
            }
        } label: { Label("Add corner shelf / seat / footrest", systemImage: "triangle") }
        if area == .shower {
            Button { addBench(on: wall, floating: false) } label: { Label("Add framed bench", systemImage: "square.bottomhalf.filled") }
            Button { addBench(on: wall, floating: true) } label: { Label("Add floating bench", systemImage: "rectangle.split.1x2") }
        }
    }

    /// The chosen item's sizes, stone and Delete; chips to choose the others on this wall.
    @ViewBuilder
    private func itemPanel(on wall: ScannedRoom.Wall) -> some View {
        let here = takeoff.items.filter { $0.wallID == wall.id }
        if !here.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(here) { item in
                            let on = item.id == selectedItem
                            Button { selectedItem = on ? nil : item.id } label: {
                                Text(item.kind.name)
                                    .font(.caption.weight(on ? .semibold : .regular))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(on ? Color.mint.opacity(0.3) : Color.white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let id = selectedItem, let i = takeoff.items.firstIndex(where: { $0.id == id }), takeoff.items[i].wallID == wall.id {
                    itemControls(i, wall: wall)
                } else {
                    Text("Tap one to change it; drag it on the wall above.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func itemControls(_ i: Int, wall: ScannedRoom.Wall) -> some View {
        let item = takeoff.items[i]
        let width = Binding(get: { takeoff.items[i].widthFt * 12 }, set: { v in
            takeoff.items[i].toFt = min(wall.lengthFt, takeoff.items[i].fromFt + max(4, v) / 12)
        })
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.kind.name).font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    takeoff.items.remove(at: i)
                    selectedItem = nil
                } label: { Label("Delete", systemImage: "trash") }
                .font(.caption)
            }
            switch item.kind {
            case .niche, .window:
                HStack(spacing: 12) {
                    InchField(title: "Width", inches: width)
                    InchField(title: "Height", inches: $takeoff.items[i].heightIn)
                    InchField(title: "Off the floor", inches: $takeoff.items[i].bottomIn)
                }
                InchField(title: "From the \(cornerName(wall, atStart: true)) end", inches: Binding(
                    get: { takeoff.items[i].fromFt * 12 },
                    set: { v in
                        let w = takeoff.items[i].widthFt
                        let from = min(max(0, v / 12), wall.lengthFt - w)
                        takeoff.items[i].fromFt = from
                        takeoff.items[i].toFt = from + w
                    }))
                .frame(maxWidth: 160, alignment: .leading)
                if item.kind == .niche {
                    Stepper("Divider shelves: \(item.dividers)", value: $takeoff.items[i].dividers, in: 0...6)
                        .font(.subheadline)
                    Picker("Stone", selection: $takeoff.items[i].stone) {
                        Text("Tile").tag(AreaTakeoff.Item.Stone.tile)
                        Text("Stone all around").tag(AreaTakeoff.Item.Stone.all)
                        Text("Stone shelves").tag(AreaTakeoff.Item.Stone.shelves)
                    }
                    .pickerStyle(.segmented)
                    let ft = AreaTakeoff.nicheStoneFt(takeoff.items[i])
                    if ft > 0 {
                        Text("Stone: \(feetAndInches(ft)) (\(item.stone == .all ? "top, sides, base shelf and dividers" : "base shelf and dividers"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Stone", selection: $takeoff.items[i].stone) {
                        Text("Tile").tag(AreaTakeoff.Item.Stone.tile)
                        Text("Stone all around").tag(AreaTakeoff.Item.Stone.all)
                    }
                    .pickerStyle(.segmented)
                    Text("The window isn't tiled; it comes off the wall.").font(.caption).foregroundStyle(.secondary)
                }
            case .framedBench, .floatingBench:
                HStack(spacing: 12) {
                    InchField(title: "Length", inches: width)
                    InchField(title: "Height", inches: $takeoff.items[i].heightIn)
                    InchField(title: "Depth", inches: $takeoff.items[i].depthIn)
                }
                Text(item.kind == .framedBench
                     ? "Top and front are tile (counted with the walls) unless switched to stone under Stone pieces."
                     : "Supported at both ends; no front, the wall below is tile. Its top can be stone under Stone pieces.")
                    .font(.caption).foregroundStyle(.secondary)
            case .cornerShelf, .cornerFootrest, .cornerSeat:
                Picker("Corner", selection: $takeoff.items[i].atStart) {
                    Text("\(cornerName(wall, atStart: true).capitalized) corner").tag(true)
                    Text("\(cornerName(wall, atStart: false).capitalized) corner").tag(false)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 12) {
                    InchField(title: "Size", inches: $takeoff.items[i].sizeIn)
                    InchField(title: "Height", inches: $takeoff.items[i].bottomIn)
                }
                Text("Stone, charged per piece.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// A shower door opening on a wall: in the middle of this area's tile on it.
    private func addShowerDoor(on wall: ScannedRoom.Wall) {
        let mine = takeoff.pieces.filter { $0.wallID == wall.id }
        let along = mine.isEmpty ? wall.lengthFt / 2
            : (mine.map(\.fromFt).min()! + mine.map(\.toFt).max()!) / 2
        _ = room.addShowerDoor(on: wall, along: along, widthIn: stone.doorWidthIn, heightIn: stone.doorHeightIn)
    }

    /// A wall drawn in, gone: its door, and this area's tile on it.
    private func deleteWall(_ id: UUID) {
        room.walls.removeAll { $0.id == id }
        room.openings.removeAll { $0.wallID == id }
        takeoff.pieces.removeAll { $0.wallID == id }
        takeoff.items.removeAll { $0.wallID == id }
        if selectedWall == id {
            selectedWall = nil
            selectedPiece = nil
        }
    }

    /// Pieces on a wall that changed size stay inside it.
    private func clampPieces(on id: UUID) {
        guard let w = room.wall(id) else { return }
        for i in takeoff.pieces.indices where takeoff.pieces[i].wallID == id {
            takeoff.pieces[i].toFt = min(takeoff.pieces[i].toFt, w.lengthFt)
            takeoff.pieces[i].fromFt = min(takeoff.pieces[i].fromFt, takeoff.pieces[i].toFt)
            takeoff.pieces[i].heightIn = min(takeoff.pieces[i].heightIn, (w.heightFt * 12).rounded())
        }
        for i in room.openings.indices where room.openings[i].wallID == id && room.openings[i].kind == .showerDoor {
            let width = min(room.openings[i].widthFt, w.lengthFt)
            room.openings[i].widthFt = width
            room.openings[i].alongFt = min(max(room.openings[i].alongFt ?? w.lengthFt / 2, width / 2), w.lengthFt - width / 2)
            room.openings[i].heightFt = min(room.openings[i].heightFt, w.heightFt)
        }
    }

    /// Puts the shower floor in the corner of the shower's walls, or in
    /// the middle of the room when no walls are chosen yet.
    private func placeShowerFloor() {
        if let r = takeoff.suggestedFloorRect(in: room) {
            takeoff.floorRect = r
        } else {
            let pts = room.floorOutline
            let cx = pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1))
            let cy = pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1))
            takeoff.floorRect = AreaTakeoff.FloorRect(origin: .init(x: cx - 1.5, y: cy - 1.5))
        }
    }

    /// A shower floor still at 0 × 0 takes its size from the shower's walls.
    private func fillShowerFloorIfBlank() {
        if area == .shower, takeoff.floor == .drawn, takeoff.floorRect == nil || takeoff.pieces.count <= 2 {
            placeShowerFloor()
            return
        }
        guard area == .shower, takeoff.floor == .size, takeoff.floorWidthFt == 0, takeoff.floorDepthFt == 0,
              let s = takeoff.suggestedFloorSize(in: room) else { return }
        takeoff.floorWidthFt = s.width
        takeoff.floorDepthFt = s.depth
    }

    @ViewBuilder
    private var wallPanel: some View {
        if editingWalls && mode == .measure {
            if let wallID = selectedWall, let wall = room.wall(wallID) {
                wallShapePanel(wall)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit walls").font(.ndTitle(20))
                    Text("Tap any wall on the plan (or in 3-D) to move it, change its length or height, split it in two or delete it. Walls joined to it follow.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } else if let wallID = selectedWall, let wall = room.wall(wallID) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room.name(of: wall)).font(.ndTitle(20))
                    Text("\(feetAndInches(wall.lengthFt)) long · \(feetAndInches(wall.heightFt)) high")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                if wall.planned {
                    if mode == .measure { plannedWallControls(wall) }
                    Picker("Side", selection: Binding(get: { face }, set: { new in
                        face = new
                        selectedPiece = takeoff.pieces.first { $0.wallID == wallID && $0.face == new }?.id
                    })) {
                        Text(room.faceName(of: wall, face: 0)).tag(0)
                        Text(room.faceName(of: wall, face: 1)).tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                Text(wall.planned ? "Seen from the \(room.faceName(of: wall, face: face).replacingOccurrences(of: "Side", with: "side"))"
                                  : (area == .shower ? "Seen from inside the shower" : "Seen from inside the room"))
                    .font(.caption).foregroundStyle(.secondary)
                WallElevation(room: room, wall: wall, face: face, takeoff: $takeoff, selectedPiece: $selectedPiece,
                              endNames: (cornerName(wall, atStart: true), cornerName(wall, atStart: false)),
                              others: others, snaps: room.snapPoints(on: wall, others: otherPieces.filter { $0.face == face }),
                              onDoor: { d in
                                  if let i = room.openings.firstIndex(where: { $0.id == d.id }) { room.openings[i] = d }
                              },
                              selectedItem: $selectedItem)
                    .frame(height: 210)

                if mode == .measure {
                if let pieceIndex = takeoff.pieces.firstIndex(where: { $0.id == selectedPiece && $0.wallID == wallID && $0.face == face }) {
                    pieceControls(pieceIndex, wall: wall)
                } else {
                    Text("Tap the blue tile on the wall to adjust it, or add tile.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                // The tile on this wall.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button {
                            if let p = takeoff.addPiece(on: wall, area: area, others: otherPieces, face: face) { selectedPiece = p.id }
                        } label: { Label("Add tile", systemImage: "plus") }
                        if let id = selectedPiece, let p = takeoff.pieces.first(where: { $0.id == id }), p.toFt - p.fromFt > 1 {
                            Button { split(id) } label: { Label("Split", systemImage: "scissors") }
                        }
                        if let id = selectedPiece, takeoff.pieces.contains(where: { $0.id == id }) {
                            Button(role: .destructive) {
                                takeoff.pieces.removeAll { $0.id == id }
                                selectedPiece = takeoff.pieces.first { $0.wallID == wallID && $0.face == face }?.id
                            } label: { Label("Remove tile", systemImage: "trash") }
                        }
                    }
                    .fixedSize()
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
                }

                // What goes in this wall.
                if area == .shower || mode == .extras {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) { wallItemButtons(wall) }
                            .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(red: 0.85, green: 0.78, blue: 0.62))
                    .font(.subheadline)
                }

                if mode == .extras {
                    itemPanel(on: wall)
                } else {
                    doorControls(on: wall)
                    openingsList(on: wall)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode == .measure ? "Choose the walls" : "Choose a wall").font(.ndTitle(20))
                Text(mode == .measure
                     ? "Tap each wall on the plan that gets tile for this \(area?.rawValue.lowercased() ?? "area"). Then drag the tile on the wall to where it starts and stops, and up to its height."
                     : "Tap a wall on the plan (or in 3-D) to add a niche, window, bench or corner piece to it.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// A room change worked out from the room as the drag began (so each
    /// step is from the start, not added up), with this area following.
    private func editRoom(_ change: (inout ScannedRoom) -> Void) {
        if dragBase == nil { dragBase = (room, takeoff) }
        guard let base = dragBase else { return }
        var r = base.room
        change(&r)
        takeoff = base.takeoff.following(old: base.room, new: r)
        room = r
    }

    /// A one-off room change (typed, split, delete), this area following.
    private func editRoomOnce(_ change: (inout ScannedRoom) -> Void) {
        dragBase = nil
        editRoom(change)
        dragBase = nil
    }

    /// Any wall's shape: for one drawn in, its usual controls; for a scanned
    /// wall, length, height, split and delete. Dragging is on the plan.
    @ViewBuilder
    private func wallShapePanel(_ wall: ScannedRoom.Wall) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(room.name(of: wall)).font(.ndTitle(20))
                Text("\(dimensionText(wall.lengthFt)) long · \(dimensionText(wall.heightFt)) high")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            if wall.planned {
                plannedWallControls(wall)
            } else {
                Text("On the plan, drag the handle in its middle to slide it, or its ends to lengthen it. Walls joined at its corners stretch to follow; an end meeting another wall slides along it.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    InchField(title: "Length", inches: Binding(get: { wall.lengthFt * 12 }, set: { v in
                        let l = max(6, v) / 12
                        editRoomOnce { r in
                            guard let w = r.wall(wall.id) else { return }
                            let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y, cur = max(hypot(dx, dy), 1e-9)
                            r.moveWallEnd(w.id, start: false, to: .init(x: w.start.x + dx / cur * l, y: w.start.y + dy / cur * l))
                        }
                    }))
                    InchField(title: "Height", inches: Binding(get: { wall.heightFt * 12 }, set: { v in
                        editRoomOnce { r in
                            if let i = r.walls.firstIndex(where: { $0.id == wall.id }) { r.walls[i].heightFt = max(12, v) / 12 }
                        }
                    }))
                }
                HStack(spacing: 10) {
                    InchField(title: "Split at (from the \(cornerName(wall, atStart: true)) end)", inches: $splitAtIn)
                        .frame(maxWidth: 200)
                    Button {
                        editRoomOnce { _ = $0.splitWall(wall.id, atFt: splitAtIn / 12) }
                    } label: { Label("Split", systemImage: "scissors") }
                    .buttonStyle(.bordered)
                    .disabled(splitAtIn / 12 < 0.25 || splitAtIn / 12 > wall.lengthFt - 0.25)
                }
                Text("Split a wall the scanner drew as one into two, e.g. where a divider meets it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) { confirmDeleteScanned = true } label: {
                    Label("Delete this wall", systemImage: "trash")
                }
                .font(.subheadline)
                .confirmationDialog("Delete wall \(wall.label)?", isPresented: $confirmDeleteScanned, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { deleteWall(wall.id) }
                } message: {
                    Text("For a wall the scanner found that isn't there. Its doors, windows and any tile on it go too.")
                }
            }
        }
    }

    /// A wall drawn in: its height, thickness and length, and deleting it.
    private func plannedWallControls(_ wall: ScannedRoom.Wall) -> some View {
        let index = room.walls.firstIndex { $0.id == wall.id }!
        let roomHeight = room.ceilingFt * 12
        return VStack(alignment: .leading, spacing: 10) {
            Text("Not built yet: drawn on the plan. Drag the handle in its middle to move it, or its ends to change its length.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([36.0, 42, 48, 54, 60, roomHeight], id: \.self) { h in
                        let on = abs(wall.heightFt * 12 - h) < 0.5
                        Button {
                            room.walls[index].heightFt = h / 12
                            for i in takeoff.pieces.indices where takeoff.pieces[i].wallID == wall.id {
                                takeoff.pieces[i].heightIn = h
                            }
                        } label: {
                            Text(h == roomHeight ? "Full \(feetAndInches(h / 12))" : "\(Int(h))″ high")
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? Color.green.opacity(0.3) : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 12) {
                InchField(title: "Height", inches: Binding(get: { room.walls[index].heightFt * 12 }, set: { v in
                    room.walls[index].heightFt = max(1, v) / 12
                    clampPieces(on: wall.id)
                }))
                InchField(title: "Thickness", inches: $room.walls[index].thicknessIn)
                InchField(title: "Length", inches: Binding(get: { room.walls[index].lengthFt * 12 }, set: { v in
                    let w = room.walls[index]
                    let l = max(v, 6) / 12
                    let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
                    let cur = max((dx * dx + dy * dy).squareRoot(), 1e-9)
                    room.movePlannedEnd(w.id, start: false, to: .init(x: w.start.x + dx / cur * l, y: w.start.y + dy / cur * l))
                    clampPieces(on: w.id)
                }))
            }
            Button(role: .destructive) { confirmDeleteWall = true } label: {
                Label("Delete this wall", systemImage: "trash")
            }
            .font(.subheadline)
            .confirmationDialog("Delete \(room.name(of: wall))?", isPresented: $confirmDeleteWall, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteWall(wall.id) }
            } message: {
                Text("Its door and any tile on it go too, in every area.")
            }
        }
    }

    /// The shower's curb, wall caps and jambs (or a knee wall's cap and end
    /// jambs elsewhere): tile by default, or stone per linear foot.
    @ViewBuilder
    private var trimPanel: some View {
        let pieces = takeoff.trimPieces(in: room, area: area, curbHeightIn: stone.curbHeightIn)
        if area == .shower || !pieces.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(area == .shower ? "Stone pieces" : "Wall cap & jambs").font(.ndTitle(20))
                if area == .shower {
                    InchField(title: "Curb height", inches: Binding(
                        get: { takeoff.curbHeightIn ?? stone.curbHeightIn },
                        set: { takeoff.curbHeightIn = $0 }))
                        .frame(maxWidth: 140, alignment: .leading)
                }
                ForEach(Array(openSides.enumerated()), id: \.offset) { _, side in
                    Menu {
                        Button { closeSide(side, door: true) } label: {
                            Label("Full Wall (with a door)", systemImage: "rectangle.portrait")
                        }
                        Button { closeSide(side, door: false) } label: {
                            Label("Half Wall", systemImage: "rectangle.bottomhalf.filled")
                        }
                    } label: {
                        Label("Add a wall on the curb (\(feetAndInches(side.lengthFt)) open)", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                }
                if pieces.isEmpty {
                    Text("Draw the shower floor on the plan and choose its walls; the curb and jambs are measured from them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(pieces) { piece in trimRow(piece) }
                Text("Tile is part of the wall square feet. Stone goes on its own line per linear foot (prices in Admin).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func trimRow(_ piece: TrimPiece) -> some View {
        func update(_ change: (inout AreaTakeoff.TrimChoice) -> Void) {
            if let i = takeoff.trim.firstIndex(where: { $0.key == piece.key }) {
                change(&takeoff.trim[i])
            } else {
                var c = AreaTakeoff.TrimChoice(key: piece.key)
                change(&c)
                takeoff.trim.append(c)
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.name).font(.subheadline.weight(.semibold))
                    Text(feetAndInches(piece.lengthFt) + (abs(piece.lengthFt - piece.measuredFt) > 0.01 ? " (measured \(feetAndInches(piece.measuredFt)))" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { piece.stone }, set: { v in update { $0.stone = v } })) {
                    Text("Tile").tag(false)
                    Text("Stone").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            if piece.stone {
                HStack(spacing: 10) {
                    InchField(title: "Length", inches: Binding(get: { piece.lengthFt * 12 },
                                                               set: { v in update { $0.lengthFt = v / 12 } }))
                        .frame(maxWidth: 140)
                    if abs(piece.lengthFt - piece.measuredFt) > 0.01 {
                        Button("Use measured") { update { $0.lengthFt = nil } }.font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .background(piece.stone ? Color(red: 0.55, green: 0.5, blue: 0.42).opacity(0.18) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func pieceControls(_ i: Int, wall: ScannedRoom.Wall) -> some View {
        let piece = $takeoff.pieces[i]
        let full = (wall.heightFt * 12).rounded(.down)
        let presets = [full, 96, 84, 72, 60, 48, 36, 18, 4].filter { $0 <= full }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Set(presets)).sorted(by: >), id: \.self) { h in
                        let on = abs(piece.wrappedValue.heightIn - h) < 0.5
                        Button {
                            piece.wrappedValue.heightIn = h
                        } label: {
                            Text(h == full ? "Full \(feetAndInches(h / 12))" : "\(Int(h))″")
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? ND.link.opacity(0.3) : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 12) {
                InchField(title: "From", inches: Binding(get: { piece.wrappedValue.fromFt * 12 },
                                                          set: { piece.wrappedValue.fromFt = min(max(0, $0 / 12), piece.wrappedValue.toFt) }))
                InchField(title: "To", inches: Binding(get: { piece.wrappedValue.toFt * 12 },
                                                        set: { piece.wrappedValue.toFt = max(min(wall.lengthFt, $0 / 12), piece.wrappedValue.fromFt) }))
                InchField(title: "Height", inches: piece.heightIn)
            }
            Text("From and To are inches from the \(cornerName(wall, atStart: true)) end of the wall. This piece: \(ND.number(takeoff.sqft(of: piece.wrappedValue, in: room))) sq ft.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func split(_ id: UUID) {
        guard let i = takeoff.pieces.firstIndex(where: { $0.id == id }) else { return }
        let p = takeoff.pieces[i]
        let mid = ((p.fromFt + p.toFt) / 2 * 12).rounded() / 12
        takeoff.pieces[i].toFt = mid
        var second = p
        second.id = UUID()
        second.fromFt = mid
        takeoff.pieces.insert(second, at: i + 1)
        selectedPiece = second.id
    }

    /// "wall D corner" for the end of a wall that meets another.
    private func cornerName(_ wall: ScannedRoom.Wall, atStart: Bool) -> String {
        let end = atStart ? wall.start : wall.end
        // The wall this end touches (anywhere along it), else the nearest corner.
        let touching = room.walls.filter { $0.id != wall.id }.min { room.distanceToWall(end, $0) < room.distanceToWall(end, $1) }
        if let touching, room.distanceToWall(end, touching) < 0.6 { return "wall \(touching.label)" }
        let near = room.walls.filter { $0.id != wall.id }.min { a, b in
            min(dist(a.start, end), dist(a.end, end)) < min(dist(b.start, end), dist(b.end, end))
        }
        if let near, min(dist(near.start, end), dist(near.end, end)) < 1.5 { return "wall \(near.label)" }
        return atStart ? "left end" : "right end"
    }

    private func dist(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// A shower door's width and height (the header's underside), typed;
    /// on the wall above they're dragged.
    @ViewBuilder
    private func doorControls(on wall: ScannedRoom.Wall) -> some View {
        ForEach(room.openings.filter { $0.wallID == wall.id && $0.kind == .showerDoor }) { d in
            let i = room.openings.firstIndex { $0.id == d.id }!
            let header = room.hasHeader(d)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Shower door", systemImage: "door.left.hand.open").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(role: .destructive) { room.openings.removeAll { $0.id == d.id } } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .font(.caption)
                }
                HStack(spacing: 12) {
                    InchField(title: "Width", inches: Binding(get: { room.openings[i].widthFt * 12 }, set: { v in
                        let width = min(max(12, v) / 12, wall.lengthFt)
                        room.openings[i].widthFt = width
                        let mid = room.openings[i].alongFt ?? wall.lengthFt / 2
                        room.openings[i].alongFt = min(max(mid, width / 2), wall.lengthFt - width / 2)
                    }))
                    InchField(title: header ? "Height to header" : "Height (no header)", inches: Binding(
                        get: { room.openings[i].heightFt * 12 },
                        set: { room.openings[i].heightFt = min(max(36, $0) / 12, wall.heightFt) }))
                }
                HStack(spacing: 12) {
                    InchField(title: "To \(cornerName(wall, atStart: true))", inches: Binding(
                        get: { room.span(of: room.openings[i]).lowerBound * 12 },
                        set: { v in
                            let width = room.openings[i].widthFt
                            let left = min(max(0, v / 12), wall.lengthFt - width)
                            room.openings[i].alongFt = left + width / 2
                        }))
                    InchField(title: "To \(cornerName(wall, atStart: false))", inches: Binding(
                        get: { (wall.lengthFt - room.span(of: room.openings[i]).upperBound) * 12 },
                        set: { v in
                            let width = room.openings[i].widthFt
                            let right = min(max(0, v / 12), wall.lengthFt - width)
                            room.openings[i].alongFt = wall.lengthFt - right - width / 2
                        }))
                }
                Text("From the door's edge to each end of the wall.")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(takeoff.doorClashes(d, in: room).enumerated()), id: \.offset) { _, clash in
                    Label("\(clash.name) reaches \(Int(clash.inches))″ into the doorway.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Button {
                    room.openings[i].heightFt = header ? wall.heightFt : min(stone.doorHeightIn / 12, wall.heightFt)
                } label: {
                    Label(header ? "No header (open to the ceiling)" : "Add a header at \(feetAndInches(min(stone.doorHeightIn / 12, wall.heightFt)))",
                          systemImage: header ? "arrow.up.to.line" : "rectangle.tophalf.inset.filled")
                }
                .buttonStyle(.bordered)
                .font(.caption)
                Text("Drag the door's sides or top on the wall, or drag it along. Drag its top to the ceiling for no header. The door isn't tiled; its curb, jambs and header are listed under Shower entry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(red: 0.55, green: 0.5, blue: 0.42).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func openingsList(on wall: ScannedRoom.Wall) -> some View {
        let list = takeoff.openingsInPieces(of: room).filter { $0.wallID == wall.id }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("In the tiled area").font(.subheadline.weight(.semibold))
                ForEach(list) { o in
                    Toggle(isOn: Binding(
                        get: { takeoff.subtracted.contains(o.id) },
                        set: { on in
                            if on { takeoff.subtracted.append(o.id) } else { takeoff.subtracted.removeAll { $0 == o.id } }
                        })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Take off the \(o.kind.rawValue.lowercased())")
                            Text("\(feetAndInches(o.widthFt)) × \(feetAndInches(o.heightFt))"
                                 + (o.bottomFt > 0.1 ? ", \(feetAndInches(o.bottomFt)) off the floor" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Floor and ceiling

    @ViewBuilder
    private var floorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch area {
            case .floor:
                Text("Floor").font(.ndTitle(20))
                Picker("Floor", selection: $takeoff.floor) {
                    Text("Scanned floor").tag(AreaTakeoff.FloorSource.room)
                    Text("Width × depth").tag(AreaTakeoff.FloorSource.size)
                }
                .pickerStyle(.segmented)
                if takeoff.floor == .room {
                    LabeledContent("Scanned floor", value: "\(ND.number(room.floorSqft)) sq ft")
                    if room.tubSqft > 0 {
                        Toggle("Leave out the bathtub (\(ND.number(room.tubSqft)) sq ft)", isOn: $takeoff.excludeTub)
                    }
                    HStack {
                        Text("Also leave out")
                        Spacer()
                        SqftField(value: $takeoff.excludeSqft)
                        Text("sq ft").foregroundStyle(.secondary)
                    }
                    Text("For a shower floor or anything else on the floor that isn't tiled with it.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    sizeFields
                }
            case .shower:
                Text("Shower floor").font(.ndTitle(20))
                Picker("Shower floor", selection: $takeoff.floor) {
                    Text("On the plan").tag(AreaTakeoff.FloorSource.drawn)
                    Text("Width × depth").tag(AreaTakeoff.FloorSource.size)
                    Text("None").tag(AreaTakeoff.FloorSource.none)
                }
                .pickerStyle(.segmented)
                .onChange(of: takeoff.floor) { _, new in
                    if new == .drawn, takeoff.floorRect == nil { placeShowerFloor() }
                }
                if takeoff.floor == .drawn {
                    if let r = takeoff.floorRect {
                        HStack(spacing: 10) {
                            Button {
                                show3D = false
                                placingShower = true
                            } label: {
                                Label("Put the shower here", systemImage: "hand.tap")
                            }
                            Button {
                                takeoff.floorRect = r.turned
                                takeoff.tileWallsAroundFloor(in: room)
                            } label: {
                                Label("Rotate", systemImage: "rotate.right")
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                        Text("Put the shower here: tap the corner it goes in and its floor, walls and curb move there. Rotate turns it in its corner. Drag the green handle to move it, tap it to drag an edge. The curb is always on the open sides.")
                            .font(.caption).foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            InchField(title: "Width", inches: Binding(get: { r.widthFt * 12 }, set: { takeoff.floorRect?.widthFt = max(1, $0) / 12 }))
                            InchField(title: "Depth", inches: Binding(get: { r.depthFt * 12 }, set: { takeoff.floorRect?.depthFt = max(1, $0) / 12 }))
                        }
                    } else {
                        Button {
                            show3D = false
                            placingShower = true
                        } label: {
                            Label("Put the shower here", systemImage: "hand.tap")
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                        Text("Tap the corner the shower goes in, or choose its walls on the plan and the floor goes in their corner.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if takeoff.floor == .size {
                    sizeFields
                    if let s = takeoff.suggestedFloorSize(in: room) {
                        let current = abs(takeoff.floorWidthFt - s.width) < 0.01 && abs(takeoff.floorDepthFt - s.depth) < 0.01
                        if !current {
                            Button {
                                takeoff.floorWidthFt = s.width
                                takeoff.floorDepthFt = s.depth
                            } label: {
                                Label("Size from the shower walls: \(feetAndInches(s.width)) × \(feetAndInches(s.depth))",
                                      systemImage: "arrow.down.right.and.arrow.up.left")
                            }
                            .buttonStyle(.bordered)
                            .font(.subheadline)
                        }
                    }
                }
                Toggle("Tile the ceiling (the floor's size)", isOn: $takeoff.tileCeiling)
            case .tub:
                Text("Ceiling").font(.ndTitle(20))
                Toggle("Tile the ceiling over the tub", isOn: $takeoff.tileCeiling)
                if takeoff.tileCeiling { sizeFields }
            default:
                EmptyView()
            }
        }
    }

    private var sizeFields: some View {
        HStack(spacing: 12) {
            InchField(title: "Width", inches: Binding(get: { takeoff.floorWidthFt * 12 }, set: { takeoff.floorWidthFt = $0 / 12 }))
            InchField(title: "Depth", inches: Binding(get: { takeoff.floorDepthFt * 12 }, set: { takeoff.floorDepthFt = $0 / 12 }))
        }
    }

    // MARK: Totals

    private var totalsBar: some View {
        let walls = takeoff.wallsSqft(in: room)
        let floor = takeoff.floorSqft(in: room)
        let ceiling = takeoff.ceilingSqft(in: room)
        var parts: [String] = []
        if usesWalls { parts.append("Walls \(ND.number(walls))") }
        if area == .floor || area == .shower { parts.append("\(area == .shower ? "Shower floor" : "Floor") \(ND.number(floor))") }
        if (area == .shower || area == .tub) && takeoff.tileCeiling { parts.append("Ceiling \(ND.number(ceiling))") }
        let stoneFt = TrimKind.allCases.reduce(0) { $0 + takeoff.stoneFt($1, in: room, area: area, curbHeightIn: stone.curbHeightIn) }
        return VStack(spacing: 10) {
            Text(parts.joined(separator: " · ") + " sq ft" + (stoneFt > 0 ? " · Stone \(ND.number(stoneFt)) lin ft" : ""))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Button {
                onUse(takeoff, room)
                dismiss()
            } label: {
                Text("Use these measurements").frame(maxWidth: .infinity)
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

// MARK: - The floor plan

/// The room from above. Pinch to zoom, drag to pan, double-tap to fit, tap
/// a wall to choose it.
struct PlanCanvas: View {
    let room: ScannedRoom
    let mine: [AreaTakeoff.Piece]
    var others: [OtherAreaPieces] = []
    var selectedWall: UUID? = nil
    var interactive = true
    /// A floor rectangle shown on the plan, and dragged when editable.
    var floorRect: Binding<AreaTakeoff.FloorRect?>? = nil
    var floorRectShown: AreaTakeoff.FloorRect? = nil
    /// Waiting for a tap on the plan (e.g. the corner the shower goes in).
    var onTapPoint: ((ScannedRoom.Point) -> Void)? = nil
    /// Areas suggested from the scan, outlined and named on the plan.
    var highlights: [(name: String, outline: [ScannedRoom.Point])] = []
    /// Puts the floor back where it started (Reset while editing it).
    var onResetFloor: (() -> Void)? = nil
    /// The floor moved, resized or turned: its walls follow.
    var onFloorChanged: (() -> Void)? = nil
    /// The shower's curb: open sides of its floor.
    var curbEdges: [(ScannedRoom.Point, ScannedRoom.Point)] = []
    /// Benches, niches, windows and corner pieces placed on the walls.
    var items: [AreaTakeoff.Item] = []
    /// Dimension lines outside each wall with its length.
    var showDimensions = false
    var hint: String? = nil
    /// Drawing a new wall: a drag on the plan from its start to its end.
    var addingWall = false
    var onAddWall: (ScannedRoom.Point, ScannedRoom.Point) -> Void = { _, _ in }
    /// Dragging an end of a planned wall (its id, which end, where to).
    var onMovePlannedEnd: (UUID, Bool, ScannedRoom.Point) -> Void = { _, _, _ in }
    /// Dragging a whole planned wall: where it started, and how far, in plan feet.
    var onMovePlannedWall: (ScannedRoom.Wall, ScannedRoom.Point) -> Void = { _, _ in }
    /// Any wall's handles show (not only walls drawn in): dragging a scanned
    /// wall's middle slides it, its ends lengthen it.
    var editAnyWall = false
    var onMoveWall: (UUID, ScannedRoom.Point) -> Void = { _, _ in }
    var onMoveWallEnd: (UUID, Bool, ScannedRoom.Point) -> Void = { _, _, _ in }
    var onWallDragEnded: () -> Void = {}
    /// The shower floor's open sides; tapping one offers to add a wall there.
    var openSides: [(ScannedRoom.Point, ScannedRoom.Point)] = []
    var onTapOpenSide: (Int) -> Void = { _ in }
    /// Where a wall being drawn lands (e.g. on the shower's curb).
    var snapNewWall: (ScannedRoom.Point, ScannedRoom.Point) -> (ScannedRoom.Point, ScannedRoom.Point) = { ($0, $1) }
    var onTapWall: (UUID) -> Void = { _ in }

    @State private var zoom: CGFloat = 1
    @State private var dragStart: AreaTakeoff.FloorRect? = nil
    /// The planned wall being dragged whole, as it was when the drag began.
    @State private var wallDragStart: ScannedRoom.Wall? = nil
    /// The shower floor's edges are being resized.
    @State private var editingFloor = false
    /// The wall being drawn, start and end, while dragging.
    @State private var drawing: (ScannedRoom.Point, ScannedRoom.Point)? = nil
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    /// Plan feet → screen points. The plan is turned by `angle` so the
    /// room's walls run straight across and up the screen (the scanner's
    /// north is wherever the phone pointed when the scan began).
    private struct Frame {
        let size: CGSize
        let scale: CGFloat
        let cx: Double, cy: Double
        let pan: CGSize
        var cosA: Double = 1
        var sinA: Double = 0
        /// A point turned to line up with the screen, still in feet.
        func turned(_ p: ScannedRoom.Point) -> (Double, Double) {
            let dx = p.x - cx, dy = p.y - cy
            return (dx * cosA - dy * sinA, dx * sinA + dy * cosA)
        }
        func at(_ p: ScannedRoom.Point) -> CGPoint {
            let (x, y) = turned(p)
            return CGPoint(x: size.width / 2 + x * scale + pan.width,
                           y: size.height / 2 + y * scale + pan.height)
        }
        /// The plan point under a screen point.
        func point(at s: CGPoint) -> ScannedRoom.Point {
            let x = Double((s.x - size.width / 2 - pan.width) / scale)
            let y = Double((s.y - size.height / 2 - pan.height) / scale)
            return ScannedRoom.Point(x: cx + x * cosA + y * sinA, y: cy - x * sinA + y * cosA)
        }
        /// A drag on screen, in plan feet.
        func feet(_ t: CGSize) -> (Double, Double) {
            let x = Double(t.width / scale), y = Double(t.height / scale)
            return (x * cosA + y * sinA, -x * sinA + y * cosA)
        }
    }

    private func frame(_ size: CGSize) -> Frame {
        let pts = room.floorOutline + room.walls.flatMap { [$0.start, $0.end] }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let a = -room.squaringAngle
        var f = Frame(size: size, scale: 1, cx: ((xs.min() ?? 0) + (xs.max() ?? 1)) / 2,
                      cy: ((ys.min() ?? 0) + (ys.max() ?? 1)) / 2, pan: pan, cosA: cos(a), sinA: sin(a))
        // Fit the turned room.
        let t = pts.map { f.turned($0) }
        let tx = t.map(\.0), ty = t.map(\.1)
        let minX = tx.min() ?? -1, maxX = tx.max() ?? 1, minY = ty.min() ?? -1, maxY = ty.max() ?? 1
        // Room round the edge for the dimension lines.
        let margin: CGFloat = interactive && showDimensions ? 110 : 60
        let fit = min((size.width - margin) / max(maxX - minX, 1), (size.height - margin) / max(maxY - minY, 1))
        // Centre the turned room.
        let ox = (minX + maxX) / 2, oy = (minY + maxY) / 2
        f = Frame(size: size, scale: fit * zoom,
                  cx: f.cx + (ox * f.cosA + oy * f.sinA), cy: f.cy + (-ox * f.sinA + oy * f.cosA),
                  pan: pan, cosA: f.cosA, sinA: f.sinA)
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            plan
                .overlay(alignment: .bottomLeading) {
                    if let hint, !editingFloor {
                        Text(hint).font(.caption2).foregroundStyle(.secondary).padding(8)
                            .allowsHitTesting(false)
                    }
                }
            floorBar
        }
    }

    private var plan: some View {
        GeometryReader { geo in
            let f = frame(geo.size)
            if interactive {
                Canvas { ctx, _ in draw(ctx, f) }
                    .contentShape(Rectangle())
                    .gesture(addingWall ? nil : zoomAndPan(geo.size))
                    .overlay {
                        if addingWall {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                                    let a = room.snappedToWall(f.point(at: v.startLocation))
                                    drawing = snapNewWall(a, room.plannedEnd(from: a, toward: f.point(at: v.location)))
                                }.onEnded { _ in
                                    if let (a, b) = drawing,
                                       ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() >= 1 {
                                        onAddWall(a, b)
                                    }
                                    drawing = nil
                                })
                        }
                    }
                    .overlay { plannedEndHandles(f) }
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.25)) { zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero }
                    }
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        if let onTapPoint { onTapPoint(f.point(at: location)); return }
                        if editingFloor { withAnimation(.easeOut(duration: 0.15)) { editingFloor = false }; return }
                        if let side = openSide(at: location, f) { onTapOpenSide(side); return }
                        if let id = wall(at: location, f) { onTapWall(id) }
                    }
                    .clipped()
                    .overlay { if let floorRect { floorHandles(floorRect, f) } }
                    .overlay(alignment: .topTrailing) {
                        if zoom != 1 || pan != .zero {
                            Button {
                                withAnimation(.easeOut(duration: 0.25)) { zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero }
                            } label: {
                                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(10)
                        }
                    }
            } else {
                Canvas { ctx, _ in draw(ctx, f) }.clipped()
            }
        }
    }

    /// While resizing the floor: its size, Reset and Done, in a strip
    /// under the plan.
    @ViewBuilder
    private var floorBar: some View {
        if editingFloor, let r = floorRect?.wrappedValue {
            HStack(spacing: 10) {
                Text("Shower floor \(feetAndInches(r.widthFt)) × \(feetAndInches(r.depthFt))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)
                Spacer(minLength: 4)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        floorRect?.wrappedValue = r.turned
                        onFloorChanged?()
                    }
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                if let onResetFloor {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { onResetFloor() }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { editingFloor = false }
                } label: {
                    Text("Done").fontWeight(.semibold)
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.green)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(white: 0.09))
        }
    }

    /// The shower floor on the plan: one handle in its middle. Tap it to
    /// resize — the outline lights up and each edge can be dragged; drag it
    /// to move the whole floor. Sizes snap to the inch, and an edge snaps to
    /// a wall within 3″.
    @ViewBuilder
    private func floorHandles(_ binding: Binding<AreaTakeoff.FloorRect?>, _ f: Frame) -> some View {
        if let r = binding.wrappedValue {
            let c = r.corners
            ZStack {
                if editingFloor {
                    // Each edge: a thick invisible strip along it, with a grip at its middle.
                    edge(binding, r, f, from: c[0], to: c[1], axis: .v, near: true)
                    edge(binding, r, f, from: c[1], to: c[2], axis: .u, near: false)
                    edge(binding, r, f, from: c[2], to: c[3], axis: .v, near: false)
                    edge(binding, r, f, from: c[3], to: c[0], axis: .u, near: true)
                }
                FloorHandle(symbol: "arrow.up.and.down.and.arrow.left.and.right", active: editingFloor)
                    .position(midpoint(c[0], c[2], f))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 4).onChanged { v in
                            let start = dragStart ?? r
                            if dragStart == nil { dragStart = r }
                            // Move in whole inches along the floor's own sides.
                            let a = (along(v.translation, start.u, f) * 12).rounded() / 12
                            let b = (along(v.translation, start.v, f) * 12).rounded() / 12
                            binding.wrappedValue?.origin = .init(x: start.origin.x + start.u.x * a + start.v.x * b,
                                                                 y: start.origin.y + start.u.y * a + start.v.y * b)
                        }.onEnded { _ in dragStart = nil; onFloorChanged?() }
                        .exclusively(before: TapGesture().onEnded {
                            withAnimation(.easeOut(duration: 0.15)) { editingFloor.toggle() }
                        })
                    )
            }
        }
    }

    private enum Axis { case u, v }

    /// One edge of the floor while resizing: dragging it moves only that
    /// edge, the opposite one stays put.
    private func edge(_ binding: Binding<AreaTakeoff.FloorRect?>, _ r: AreaTakeoff.FloorRect, _ f: Frame,
                      from a: ScannedRoom.Point, to b: ScannedRoom.Point, axis: Axis, near: Bool) -> some View {
        let p = f.at(a), q = f.at(b)
        let length = max(hypot(q.x - p.x, q.y - p.y), 1)
        let angle = Angle(radians: atan2(q.y - p.y, q.x - p.x))
        return ZStack {
            Color.clear.frame(width: length, height: 48).contentShape(Rectangle())
            Capsule().fill(Color.white).overlay(Capsule().stroke(Color.green, lineWidth: 2))
                .frame(width: 26, height: 9)
        }
        .rotationEffect(angle)
        .position(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
            let start = dragStart ?? r
            if dragStart == nil { dragStart = r }
            let dir = axis == .u ? start.u : start.v
            let out = near ? ScannedRoom.Point(x: -dir.x, y: -dir.y) : dir
            let old = axis == .u ? start.widthFt : start.depthFt
            // The opposite edge stays put: measure from its middle.
            let side = axis == .u ? start.v : start.u
            let sideLen = axis == .u ? start.depthFt : start.widthFt
            var anchor = ScannedRoom.Point(x: start.origin.x + side.x * sideLen / 2, y: start.origin.y + side.y * sideLen / 2)
            if near { anchor = .init(x: anchor.x + dir.x * old, y: anchor.y + dir.y * old) }
            let length = snapLength(old + along(v.translation, out, f), from: anchor, toward: out)
            var updated = start
            if axis == .u { updated.widthFt = length } else { updated.depthFt = length }
            if near {
                updated.origin = .init(x: start.origin.x - dir.x * (length - old), y: start.origin.y - dir.y * (length - old))
            }
            binding.wrappedValue = updated
        }.onEnded { _ in dragStart = nil; onFloorChanged?() })
    }

    /// A length rounded to the inch, or to where it would meet a wall when
    /// within 3″, measured from `from` toward `dir`.
    private func snapLength(_ length: Double, from o: ScannedRoom.Point, toward dir: ScannedRoom.Point) -> Double {
        var best = max(6.0 / 12, (length * 12).rounded() / 12)
        var bestGap = 0.25
        for w in room.walls {
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = dir.x * ey - dir.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - o.x) * ey - (w.start.y - o.y) * ex) / den
            let s = ((w.start.x - o.x) * dir.y - (w.start.y - o.y) * dir.x) / den
            guard t > 0.5, s >= -0.05, s <= 1.05, abs(t - length) < bestGap else { continue }
            best = t
            bestGap = abs(t - length)
        }
        return best
    }

    private func midpoint(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point, _ f: Frame) -> CGPoint {
        let p = f.at(a), q = f.at(b)
        return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
    }

    /// How far a drag on screen goes along a direction on the plan, in feet.
    private func along(_ t: CGSize, _ dir: ScannedRoom.Point, _ f: Frame) -> Double {
        let (x, y) = f.feet(t)
        return x * dir.x + y * dir.y
    }

    /// Pinch zooms round the point between the fingers; drag pans.
    private func zoomAndPan(_ size: CGSize) -> some Gesture {
        let magnify = MagnifyGesture()
            .onChanged { v in
                let newZoom = min(6, max(0.6, lastZoom * v.magnification))
                // Keep the plan under the pinch where it was.
                let anchor = CGSize(width: v.startLocation.x - size.width / 2, height: v.startLocation.y - size.height / 2)
                let k = newZoom / lastZoom
                pan = CGSize(width: anchor.width - (anchor.width - lastPan.width) * k,
                             height: anchor.height - (anchor.height - lastPan.height) * k)
                zoom = newZoom
            }
            .onEnded { _ in lastZoom = zoom; lastPan = pan }
        let drag = DragGesture(minimumDistance: 10)
            .onChanged { pan = CGSize(width: lastPan.width + $0.translation.width, height: lastPan.height + $0.translation.height) }
            .onEnded { _ in lastPan = pan }
        return magnify.simultaneously(with: drag)
    }

    /// An open side of the shower floor under a tap, when it's nearer than any wall.
    private func openSide(at point: CGPoint, _ f: Frame) -> Int? {
        var best: (Int, CGFloat)? = nil
        for (i, (a, b)) in openSides.enumerated() {
            let d = distance(point, f.at(a), f.at(b))
            if d < 22, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        guard let best else { return nil }
        let nearestWall = room.walls.map { distance(point, f.at($0.start), f.at($0.end)) }.min() ?? .infinity
        return best.1 <= nearestWall ? best.0 : nil
    }

    private func wall(at point: CGPoint, _ f: Frame) -> UUID? {
        var best: (UUID, CGFloat)? = nil
        for w in room.walls {
            let a = f.at(w.start), b = f.at(w.end)
            let d = distance(point, a, b)
            if d < 28, d < (best?.1 ?? .infinity) { best = (w.id, d) }
        }
        return best?.0
    }

    private func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let len2 = max(ab.x * ab.x + ab.y * ab.y, 1e-6)
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / len2, 0), 1)
        let q = CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y)
        return hypot(p.x - q.x, p.y - q.y)
    }

    /// A strip along a wall, from/to feet along it, `offset` feet to its
    /// left (its first face), `width` feet wide.
    private func band(_ w: ScannedRoom.Wall, from: Double, to: Double, offset: Double, width: Double, _ f: Frame) -> Path {
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let n = ScannedRoom.Point(x: -dy / l, y: dx / l)
        func at(_ along: Double, _ side: Double) -> CGPoint {
            let p = room.point(on: w, along: along)
            return f.at(.init(x: p.x + n.x * side, y: p.y + n.y * side))
        }
        var path = Path()
        path.addLines([at(from, offset - width / 2), at(to, offset - width / 2), at(to, offset + width / 2), at(from, offset + width / 2)])
        path.closeSubpath()
        return path
    }

    /// A tiled piece as a line on the plan; on a planned wall, along the face it's on.
    private func pieceLine(_ p: AreaTakeoff.Piece, _ f: Frame) -> Path? {
        guard let w = room.wall(p.wallID) else { return nil }
        guard w.planned else { return segment(p.wallID, from: p.fromFt, to: p.toFt, f) }
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let side = (p.face == 0 ? 1.0 : -1.0) * w.thicknessIn / 24
        let n = ScannedRoom.Point(x: -dy / l * side, y: dx / l * side)
        let a = room.point(on: w, along: p.fromFt), b = room.point(on: w, along: p.toFt)
        var path = Path()
        path.move(to: f.at(.init(x: a.x + n.x, y: a.y + n.y)))
        path.addLine(to: f.at(.init(x: b.x + n.x, y: b.y + n.y)))
        return path
    }

    /// The unit vector from a wall toward the shower (its floor's middle),
    /// else into the room; a planned wall's from the face given.
    private func inward(_ w: ScannedRoom.Wall, face: Int) -> ScannedRoom.Point {
        let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
        let l = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        var n = ScannedRoom.Point(x: -dy / l, y: dx / l)
        if w.planned { return face == 0 ? n : .init(x: -n.x, y: -n.y) }
        let target: ScannedRoom.Point
        if let r = floorRect?.wrappedValue ?? floorRectShown {
            let c = r.corners
            target = .init(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        } else {
            let pts = room.floorOutline.isEmpty ? room.walls.flatMap { [$0.start, $0.end] } : room.floorOutline
            target = .init(x: pts.map(\.x).reduce(0, +) / Double(max(pts.count, 1)), y: pts.map(\.y).reduce(0, +) / Double(max(pts.count, 1)))
        }
        let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
        if (target.x - mid.x) * n.x + (target.y - mid.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
        return n
    }

    /// Grab handles on the ends of the chosen planned wall, and one in its
    /// middle to move it whole.
    @ViewBuilder
    private func plannedEndHandles(_ f: Frame) -> some View {
        if !addingWall, let id = selectedWall, let w = room.wall(id), w.planned || editAnyWall {
            ZStack {
                FloorHandle(symbol: w.planned ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.left.and.right")
                    .scaleEffect(0.85)
                    .rotationEffect(w.planned ? .zero : .radians(atan2(Double(f.at(w.end).y - f.at(w.start).y),
                                                                       Double(f.at(w.end).x - f.at(w.start).x)) + .pi / 2))
                    .position(midpoint(w.start, w.end, f))
                    .highPriorityGesture(DragGesture(minimumDistance: 2).onChanged { v in
                        let start = wallDragStart ?? w
                        if wallDragStart == nil { wallDragStart = w }
                        let (x, y) = f.feet(v.translation)
                        if w.planned { onMovePlannedWall(start, .init(x: x, y: y)) } else { onMoveWall(id, .init(x: x, y: y)) }
                    }.onEnded { _ in wallDragStart = nil; onWallDragEnded() })
                ForEach([true, false], id: \.self) { isStart in
                    let p = isStart ? w.start : w.end
                    Circle().fill(Color.white).overlay(Circle().stroke(Color.green, lineWidth: 3))
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .position(f.at(p))
                        .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let base = wallDragStart ?? w
                            if wallDragStart == nil { wallDragStart = w }
                            let other = isStart ? base.end : base.start
                            let target = f.point(at: v.location)
                            let p = room.plannedEnd(from: other, toward: target, except: id)
                            if w.planned { onMovePlannedEnd(id, isStart, p) } else { onMoveWallEnd(id, isStart, p) }
                        }.onEnded { _ in wallDragStart = nil; onWallDragEnded() })
                }
            }
        }
    }

    private func segment(_ wallID: UUID, from: Double, to: Double, _ f: Frame) -> Path? {
        guard let w = room.wall(wallID) else { return nil }
        var path = Path()
        path.move(to: f.at(room.point(on: w, along: from)))
        path.addLine(to: f.at(room.point(on: w, along: to)))
        return path
    }

    private func draw(_ ctx: GraphicsContext, _ f: Frame) {
        // Floor and bathtub.
        if room.floorOutline.count > 2 {
            var floor = Path()
            floor.addLines(room.floorOutline.map(f.at))
            floor.closeSubpath()
            ctx.fill(floor, with: .color(Color(white: 0.17)))
        }
        if room.tubOutline.count > 2 {
            var tub = Path()
            tub.addLines(room.tubOutline.map(f.at))
            tub.closeSubpath()
            ctx.fill(tub, with: .color(Color(white: 0.26)))
            ctx.stroke(tub, with: .color(Color(white: 0.45)), lineWidth: 1)
            let c = f.at(ScannedRoom.Point(x: room.tubOutline.map(\.x).reduce(0, +) / Double(room.tubOutline.count),
                                           y: room.tubOutline.map(\.y).reduce(0, +) / Double(room.tubOutline.count)))
            ctx.draw(Text("Tub").font(.caption2).foregroundColor(Color(white: 0.6)), at: c)
        }
        // Walls not built yet: dashed, as thick as they'll be.
        for w in room.walls where w.planned {
            let path = band(w, from: 0, to: w.lengthFt, offset: 0, width: w.thicknessIn / 12, f)
            ctx.fill(path, with: .color(Color(white: w.id == selectedWall ? 0.32 : 0.24)))
            ctx.stroke(path, with: .color(Color(white: w.id == selectedWall ? 0.85 : 0.6)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        if let (a, b) = drawing {
            var line = Path()
            line.move(to: f.at(a))
            line.addLine(to: f.at(b))
            ctx.stroke(line, with: .color(.green), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
            let len = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            ctx.draw(Text(feetAndInches(len)).font(.caption.weight(.semibold)).foregroundColor(.green),
                     at: CGPoint(x: (f.at(a).x + f.at(b).x) / 2, y: (f.at(a).y + f.at(b).y) / 2 - 14))
        }
        // Walls.
        for w in room.walls where !w.planned {
            var line = Path()
            line.move(to: f.at(w.start))
            line.addLine(to: f.at(w.end))
            ctx.stroke(line, with: .color(Color(white: w.id == selectedWall ? 0.75 : 0.5)),
                       style: StrokeStyle(lineWidth: w.id == selectedWall ? 7 : 5, lineCap: .round))
        }
        // Doors and windows: a light gap in the wall.
        for o in room.openings {
            guard let wallID = o.wallID else { continue }
            let s = room.span(of: o)
            if let gap = segment(wallID, from: s.lowerBound, to: s.upperBound, f) {
                ctx.stroke(gap, with: .color(o.kind == .window ? Color.cyan.opacity(0.8) : Color(white: 0.17)),
                           style: StrokeStyle(lineWidth: o.kind == .window ? 3 : 6))
            }
        }
        // Other areas' tile, then this area's.
        for other in others {
            if let r = other.floor {
                var path = Path()
                path.addLines(r.corners.map(f.at))
                path.closeSubpath()
                ctx.fill(path, with: .color(Color.orange.opacity(0.15)))
                ctx.stroke(path, with: .color(Color.orange.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            for p in other.pieces {
                if let s = pieceLine(p, f) {
                    ctx.stroke(s, with: .color(Color.orange.opacity(0.55)), style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                }
            }
        }
        for p in mine {
            if let s = pieceLine(p, f) {
                ctx.stroke(s, with: .color(Color.blue), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
            }
        }
        // The shower floor.
        if let r = floorRect?.wrappedValue ?? floorRectShown {
            var path = Path()
            path.addLines(r.corners.map(f.at))
            path.closeSubpath()
            ctx.fill(path, with: .color(Color.green.opacity(editingFloor ? 0.3 : 0.18)))
            if editingFloor {
                ctx.stroke(path, with: .color(Color.green), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            } else {
                ctx.stroke(path, with: .color(Color.green.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            let c = r.corners
            let center = f.at(ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2))
            let p0 = f.at(c[0]), p2 = f.at(c[2])
            if interactive, !editingFloor, abs(p2.x - p0.x) > 90, abs(p2.y - p0.y) > 80 {
                ctx.draw(Text("\(feetAndInches(r.widthFt)) × \(feetAndInches(r.depthFt))")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.green),
                         at: CGPoint(x: center.x, y: center.y + 24))
            }
        }
        // Benches and corner pieces, out from their wall; windows and niches on it.
        let stoneColor = Color(red: 0.85, green: 0.78, blue: 0.62)
        for item in items {
            guard let w = room.wall(item.wallID) else { continue }
            let n = inward(w, face: item.face)
            func pt(_ along: Double, _ out: Double) -> CGPoint {
                let p = room.point(on: w, along: along)
                return f.at(.init(x: p.x + n.x * out, y: p.y + n.y * out))
            }
            let skin = w.planned ? w.thicknessIn / 24 : 0
            var path = Path()
            switch item.kind {
            case .framedBench, .floatingBench:
                let d = skin + item.depthIn / 12
                path.addLines([pt(item.fromFt, skin), pt(item.toFt, skin), pt(item.toFt, d), pt(item.fromFt, d)])
                path.closeSubpath()
                ctx.fill(path, with: .color(Color.mint.opacity(0.3)))
                ctx.stroke(path, with: .color(Color.mint), style: StrokeStyle(lineWidth: 1.5, dash: item.kind == .floatingBench ? [4, 3] : []))
                if interactive {
                    let c = pt((item.fromFt + item.toFt) / 2, d / 2 + skin / 2)
                    ctx.draw(Text("Bench").font(.system(size: 9, weight: .semibold)).foregroundColor(.mint), at: c)
                }
            case .cornerShelf, .cornerFootrest, .cornerSeat:
                let size = item.sizeIn / 12
                let corner = item.atStart ? 0.0 : w.lengthFt
                let along = item.atStart ? size : w.lengthFt - size
                path.addLines([pt(corner, skin), pt(along, skin), pt(corner, skin + size)])
                path.closeSubpath()
                ctx.fill(path, with: .color(stoneColor.opacity(0.5)))
                ctx.stroke(path, with: .color(stoneColor), lineWidth: 1)
            case .window:
                path.move(to: pt(item.fromFt, 0)); path.addLine(to: pt(item.toFt, 0))
                ctx.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 4))
            case .niche:
                path.addLines([pt(item.fromFt, skin), pt(item.fromFt, skin - 0.3), pt(item.toFt, skin - 0.3), pt(item.toFt, skin)])
                ctx.stroke(path, with: .color(item.stone == .tile ? Color.white.opacity(0.7) : stoneColor), lineWidth: 1.5)
            }
        }

        // Suggested areas.
        let hi = Color(red: 1, green: 0.8, blue: 0.3)
        for h in highlights where h.outline.count > 2 {
            var path = Path()
            path.addLines(h.outline.map(f.at))
            path.closeSubpath()
            ctx.fill(path, with: .color(hi.opacity(0.18)))
            ctx.stroke(path, with: .color(hi), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            let c = ScannedRoom.Point(x: h.outline.map(\.x).reduce(0, +) / Double(h.outline.count),
                                      y: h.outline.map(\.y).reduce(0, +) / Double(h.outline.count))
            let text = ctx.resolve(Text(h.name).font(.system(size: 11, weight: .bold)).foregroundColor(.black))
            let size = text.measure(in: CGSize(width: 200, height: 40))
            let at = f.at(c)
            ctx.fill(Path(roundedRect: CGRect(x: at.x - size.width / 2 - 5, y: at.y - size.height / 2 - 2,
                                              width: size.width + 10, height: size.height + 4), cornerRadius: 5),
                     with: .color(hi))
            ctx.draw(text, at: at)
        }

        // The curb.
        for (a, b) in curbEdges {
            var line = Path()
            line.move(to: f.at(a))
            line.addLine(to: f.at(b))
            ctx.stroke(line, with: .color(Color(red: 0.85, green: 0.78, blue: 0.62)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .butt))
            let m = CGPoint(x: (f.at(a).x + f.at(b).x) / 2, y: (f.at(a).y + f.at(b).y) / 2)
            if interactive {
                ctx.draw(Text("Curb").font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 0.85, green: 0.78, blue: 0.62)), at: CGPoint(x: m.x, y: m.y + 11))
            }
        }
        // Wall labels, just inside the room.
        let cx = room.walls.map { ($0.start.x + $0.end.x) / 2 }.reduce(0, +) / Double(max(room.walls.count, 1))
        let cy = room.walls.map { ($0.start.y + $0.end.y) / 2 }.reduce(0, +) / Double(max(room.walls.count, 1))
        for w in room.walls {
            let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
            // Just inside the wall: a fixed distance on screen, whatever the zoom.
            let dx = cx - mid.x, dy = cy - mid.y
            let len = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            let inward = Double(interactive ? 16 : 9) / Double(f.scale)
            let toward = ScannedRoom.Point(x: mid.x + dx / len * inward, y: mid.y + dy / len * inward)
            let label = Text(interactive && !showDimensions ? "\(w.label)  \(feetAndInches(w.lengthFt))" : w.label)
                .font(.system(size: interactive ? 11 : 10, weight: .semibold))
                .foregroundColor(mine.contains { $0.wallID == w.id } ? .blue : Color(white: 0.75))
            ctx.draw(label, at: f.at(toward))
        }
        if interactive && showDimensions { drawDimensions(ctx, f, center: .init(x: cx, y: cy)) }
    }

    /// Architectural dimension lines round the room's perimeter: outside each
    /// scanned wall, with extension lines, slash ticks, and the length to the
    /// quarter inch (walls drawn in aren't dimensioned).
    private func drawDimensions(_ ctx: GraphicsContext, _ f: Frame, center: ScannedRoom.Point) {
        let ink = Color(red: 1, green: 0.8, blue: 0.3)
        let floorMid: ScannedRoom.Point? = (floorRect?.wrappedValue ?? floorRectShown).map { r in
            let c = r.corners
            return .init(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        }
        for w in room.walls where !w.planned && w.lengthFt > 0.05 {
            let dx = w.end.x - w.start.x, dy = w.end.y - w.start.y
            var n = ScannedRoom.Point(x: -dy / w.lengthFt, y: dx / w.lengthFt)
            let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
            // Away from the room (a scanned wall), or from the shower (one drawn in).
            let from = w.planned ? (floorMid ?? center) : center
            if (from.x - mid.x) * n.x + (from.y - mid.y) * n.y > 0 { n = .init(x: -n.x, y: -n.y) }
            let pa = f.at(w.start), pb = f.at(w.end)
            let q = f.at(.init(x: w.start.x + n.x, y: w.start.y + n.y))
            let ln = max(hypot(q.x - pa.x, q.y - pa.y), 1e-6)
            let ns = CGPoint(x: (q.x - pa.x) / ln, y: (q.y - pa.y) / ln)
            let gap: CGFloat = w.planned ? 6 + w.thicknessIn / 24 * f.scale : 6
            let off: CGFloat = w.planned ? gap + 14 : 24
            func shifted(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + ns.x * d, y: p.y + ns.y * d) }
            var lines = Path()
            // Extension lines.
            lines.move(to: shifted(pa, gap)); lines.addLine(to: shifted(pa, off + 5))
            lines.move(to: shifted(pb, gap)); lines.addLine(to: shifted(pb, off + 5))
            // The dimension line.
            let a = shifted(pa, off), b = shifted(pb, off)
            lines.move(to: a); lines.addLine(to: b)
            ctx.stroke(lines, with: .color(ink.opacity(0.85)), lineWidth: 1)
            // Slash ticks.
            let ux = (b.x - a.x) / max(hypot(b.x - a.x, b.y - a.y), 1e-6), uy = (b.y - a.y) / max(hypot(b.x - a.x, b.y - a.y), 1e-6)
            var ticks = Path()
            for p in [a, b] {
                let tx = (ux + ns.x) * 4, ty = (uy + ns.y) * 4
                ticks.move(to: CGPoint(x: p.x - tx, y: p.y - ty)); ticks.addLine(to: CGPoint(x: p.x + tx, y: p.y + ty))
            }
            ctx.stroke(ticks, with: .color(ink), lineWidth: 1.8)
            // The length, upright along the line, on a dark patch.
            var angle = atan2(b.y - a.y, b.x - a.x)
            if angle > .pi / 2 { angle -= .pi } else if angle < -.pi / 2 { angle += .pi }
            let text = ctx.resolve(Text(dimensionText(w.lengthFt)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(ink))
            let size = text.measure(in: CGSize(width: 200, height: 40))
            var c = ctx
            c.translateBy(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            c.rotate(by: .radians(angle))
            c.fill(Path(roundedRect: CGRect(x: -size.width / 2 - 4, y: -size.height / 2 - 1, width: size.width + 8, height: size.height + 2),
                        cornerRadius: 4), with: .color(Color(white: 0.09)))
            c.draw(text, at: .zero)
        }
    }
}

// MARK: - One wall, face-on

/// A wall as you'd see it standing in the room: its tile pieces in blue
/// (drag the sides and the top), other areas' tile in orange, doors and
/// windows (tap to take one off).
struct WallElevation: View {
    let room: ScannedRoom
    let wall: ScannedRoom.Wall
    /// Which face of a planned wall is shown.
    var face: Int = 0
    @Binding var takeoff: AreaTakeoff
    @Binding var selectedPiece: UUID?
    /// What each end of the wall meets ("wall B"), shown under it.
    var endNames: (String, String) = ("", "")
    let others: [OtherAreaPieces]
    let snaps: [Double]
    /// A shower door moved or resized.
    var onDoor: (ScannedRoom.Opening) -> Void = { _ in }
    /// The chosen bench, niche, window or corner piece (its handles show
    /// instead of the tile's).
    var selectedItem: Binding<UUID?> = .constant(nil)

    private let inset: CGFloat = 14
    @State private var itemDragStart: AreaTakeoff.Item? = nil
    private static let stone = Color(red: 0.85, green: 0.78, blue: 0.62)
    @State private var doorDragStart: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 2 * inset, h = geo.size.height - 2 * inset - 30
            let scale = min(w / max(wall.lengthFt, 0.5), h / max(wall.heightFt, 0.5))
            let width = wall.lengthFt * scale, height = wall.heightFt * scale
            let origin = CGPoint(x: (geo.size.width - width) / 2, y: inset + (h - height) / 2 + height)
            // Wall coordinates (feet along, feet up) → points on screen.
            let at = { (along: Double, up: Double) -> CGPoint in
                CGPoint(x: origin.x + along * scale, y: origin.y - up * scale)
            }

            ZStack(alignment: .topLeading) {
                // The wall.
                Rectangle()
                    .fill(Color(white: 0.16))
                    .overlay(Rectangle().stroke(Color(white: 0.45), lineWidth: 1))
                    .frame(width: width, height: height)
                    .position(x: origin.x + width / 2, y: origin.y - height / 2)

                // Other areas' tile.
                ForEach(others.indices, id: \.self) { i in
                    ForEach(others[i].pieces.filter { $0.wallID == wall.id && $0.face == face }) { p in
                        let r = rect(p, at)
                        Rectangle().fill(Color.orange.opacity(0.22))
                            .overlay(Rectangle().stroke(Color.orange.opacity(0.6), lineWidth: 1))
                            .overlay(Text(others[i].name).font(.caption2).foregroundStyle(.orange).padding(3), alignment: .topLeading)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }

                // This area's tile.
                ForEach(takeoff.pieces.filter { $0.wallID == wall.id && $0.face == face }) { p in
                    let r = rect(p, at)
                    let selected = p.id == selectedPiece
                    Rectangle().fill(Color.blue.opacity(selected ? 0.42 : 0.28))
                        .overlay(Rectangle().stroke(Color.blue, lineWidth: selected ? 2 : 1))
                        .overlay(alignment: .bottom) {
                            Text("\(feetAndInches(p.toFt - p.fromFt)) × \(feetAndInches(p.heightIn / 12))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.85), in: Capsule())
                                .padding(.bottom, 4)
                                .fixedSize()
                                .opacity(r.width > 40 && r.height > 22 ? 1 : 0)
                        }
                        .frame(width: max(r.width, 1), height: max(r.height, 1))
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture { selectedPiece = p.id; selectedItem.wrappedValue = nil }
                }

                // Doors and windows.
                ForEach(room.openings.filter { $0.wallID == wall.id && $0.kind != .showerDoor }) { o in
                    let s = room.span(of: o)
                    let r = CGRect(x: at(s.lowerBound, 0).x, y: at(0, o.bottomFt + o.heightFt).y,
                                   width: (s.upperBound - s.lowerBound) * scale, height: o.heightFt * scale)
                    let off = takeoff.subtracted.contains(o.id)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(off ? Color(white: 0.08) : Color.cyan.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(off ? Color.red.opacity(0.8) : Color.cyan.opacity(0.8),
                                                                          style: StrokeStyle(lineWidth: 1.5, dash: off ? [] : [4, 3])))
                        .overlay(
                            VStack(spacing: 0) {
                                Image(systemName: o.kind == .window ? "window.horizontal" : "door.left.hand.closed").font(.caption)
                                Text(off ? "off" : "tap").font(.system(size: 9))
                            }
                            .foregroundStyle(off ? .red : .cyan)
                        )
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture {
                            if off { takeoff.subtracted.removeAll { $0 == o.id } } else { takeoff.subtracted.append(o.id) }
                        }
                }

                // Shower doors: drag along, drag the sides and the top.
                ForEach(room.openings.filter { $0.wallID == wall.id && $0.kind == .showerDoor }) { d in
                    showerDoor(d, scale: scale, at: at)
                }

                // Benches, niches, windows and corner pieces.
                ForEach(itemsHere) { item in
                    itemView(item, scale: scale, at: at)
                }

                // Handles on the chosen item, else on the chosen piece.
                if let id = selectedItem.wrappedValue, let i = takeoff.items.firstIndex(where: { $0.id == id }),
                   itemsHere.contains(where: { $0.id == id }) {
                    itemHandles(i, scale: scale, at: at)
                } else if let i = takeoff.pieces.firstIndex(where: { $0.id == selectedPiece && $0.wallID == wall.id && $0.face == face }) {
                    handles(i, scale: scale, at: at)
                }

                // The floor line, the wall's length, and what each end meets.
                Text(feetAndInches(wall.lengthFt))
                    .font(.caption2).foregroundStyle(.secondary)
                    .position(x: origin.x + width / 2, y: origin.y + 10)
                // What each end meets, on a line of its own, spread at least
                // far enough to read under a narrow wall.
                HStack {
                    Label(endNames.0, systemImage: "arrow.left").labelStyle(.titleAndIcon)
                    Spacer(minLength: 8)
                    Label(endNames.1, systemImage: "arrow.right").labelStyle(.titleAndIcon)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: max(width, 170))
                .position(x: origin.x + width / 2, y: origin.y + 25)
            }
            .coordinateSpace(name: "wall")
        }
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func showerDoor(_ d: ScannedRoom.Opening, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let s = room.span(of: d)
        let top = d.bottomFt + d.heightFt
        let r = CGRect(x: at(s.lowerBound, 0).x, y: at(0, top).y, width: (s.upperBound - s.lowerBound) * scale, height: d.heightFt * scale)
        let origin = at(0, 0)
        let header = room.hasHeader(d)
        let width = s.upperBound - s.lowerBound
        // The opening, with the curb along its bottom and the header over it.
        Rectangle().fill(Color(white: 0.05))
            .overlay(Rectangle().stroke(Self.stone, style: StrokeStyle(lineWidth: 1.5)))
            .overlay(alignment: .bottom) { Rectangle().fill(Self.stone).frame(height: 4) }
            .overlay(
                VStack(spacing: 1) {
                    Image(systemName: "door.left.hand.open").font(.caption)
                    Text("\(feetAndInches(width)) × \(feetAndInches(d.heightFt))").font(.system(size: 9, weight: .semibold))
                    if !header { Text("no header").font(.system(size: 9)) }
                }
                .foregroundStyle(Self.stone).fixedSize()
            )
            .frame(width: max(r.width, 1), height: max(r.height, 1))
            .position(x: r.midX, y: r.midY)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("wall")).onChanged { v in
                let start = doorDragStart ?? s.lowerBound
                if doorDragStart == nil { doorDragStart = s.lowerBound }
                let left = min(max(0, snapped(start + v.translation.width / scale, to: [0, wall.lengthFt - width])), wall.lengthFt - width)
                onDoor(moved(d, left: left, right: left + width))
            }.onEnded { _ in doorDragStart = nil })
        // How far the opening is from each end of the wall.
        let dimY = origin.y - 14
        ForEach([(0.0, s.lowerBound), (s.upperBound, wall.lengthFt)], id: \.0) { from, to in
            if to - from > 0.01 {
                let a = at(from, 0).x, b = at(to, 0).x
                Path { p in
                    p.move(to: CGPoint(x: a + 2, y: dimY)); p.addLine(to: CGPoint(x: b - 2, y: dimY))
                    p.move(to: CGPoint(x: a + 2, y: dimY - 5)); p.addLine(to: CGPoint(x: a + 2, y: dimY + 5))
                    p.move(to: CGPoint(x: b - 2, y: dimY - 5)); p.addLine(to: CGPoint(x: b - 2, y: dimY + 5))
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                .allowsHitTesting(false)
                Text(feetAndInches(to - from))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .fixedSize()
                    .position(x: (a + b) / 2, y: dimY - 12)
                    .allowsHitTesting(false)
            }
        }
        if header {
            Rectangle().fill(Self.stone).frame(width: max(r.width, 1), height: 4)
                .position(x: r.midX, y: r.minY - 2)
                .allowsHitTesting(false)
        }
        // Left and right sides.
        DoorHandle(vertical: true)
            .position(x: r.minX, y: r.minY + r.height * 0.3)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                let left = snapped((v.location.x - origin.x) / scale, to: [0])
                onDoor(moved(d, left: min(max(0, left), s.upperBound - 1), right: s.upperBound))
            })
        DoorHandle(vertical: true)
            .position(x: r.maxX, y: r.minY + r.height * 0.3)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                let right = snapped((v.location.x - origin.x) / scale, to: [wall.lengthFt])
                onDoor(moved(d, left: s.lowerBound, right: max(min(wall.lengthFt, right), s.lowerBound + 1)))
            })
        // Top: the header's underside; to the ceiling, no header.
        DoorHandle(vertical: false)
            .position(x: r.midX, y: r.minY)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                let upFt = (origin.y - v.location.y) / scale
                let inches = (snapped(upFt, to: [wall.heightFt], pull: 3.0 / 12) * 12).rounded()
                var n = d
                n.heightFt = min(max(36, inches) / 12, wall.heightFt) - d.bottomFt
                onDoor(n)
            })
    }

    /// What's placed on this wall and seen from this side: a niche only on
    /// its face; windows, benches and corner pieces from either.
    private var itemsHere: [AreaTakeoff.Item] {
        takeoff.items.filter { $0.wallID == wall.id && ($0.kind != .niche || $0.face == face) }
    }

    /// An item's rectangle on the wall, in feet: along and up.
    private func itemRect(_ item: AreaTakeoff.Item) -> (from: Double, to: Double, bottom: Double, top: Double) {
        switch item.kind {
        case .niche, .window:
            return (item.fromFt, item.toFt, item.bottomIn / 12, (item.bottomIn + item.heightIn) / 12)
        case .framedBench, .floatingBench:
            let bottom = item.kind == .floatingBench ? max(0, item.heightIn - 3) / 12 : 0
            return (item.fromFt, item.toFt, bottom, item.heightIn / 12)
        case .cornerShelf, .cornerFootrest, .cornerSeat:
            let size = item.sizeIn / 12
            let from = item.atStart ? 0 : wall.lengthFt - size
            return (from, from + size, max(0, item.bottomIn - 1.5) / 12, item.bottomIn / 12)
        }
    }

    @ViewBuilder
    private func itemView(_ item: AreaTakeoff.Item, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let r = itemRect(item)
        let a = at(r.from, r.top), b = at(r.to, r.bottom)
        let rect = CGRect(x: a.x, y: a.y, width: max(b.x - a.x, 2), height: max(b.y - a.y, 3))
        let selected = selectedItem.wrappedValue == item.id
        let stoneColor = Color(red: 0.85, green: 0.78, blue: 0.62)
        let color: Color = item.kind == .window ? .cyan : item.kind.isCorner || item.stone != .tile ? stoneColor : .mint
        ZStack {
            Rectangle().fill(item.kind == .window ? Color.cyan.opacity(0.15) : item.kind == .niche ? Color(white: 0.05) : color.opacity(0.35))
            Rectangle().stroke(color, lineWidth: selected ? 2.5 : 1.5)
            if item.kind == .niche, item.dividers > 0 {
                Path { p in
                    for k in 1...item.dividers {
                        let y = rect.height * Double(k) / Double(item.dividers + 1)
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y))
                    }
                }
                .stroke(item.stone == .tile ? Color.white.opacity(0.6) : stoneColor, lineWidth: 2)
            }
            if !item.kind.isCorner, rect.width > 34, rect.height > 16 {
                Text(item.kind.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(color).fixedSize()
            }
        }
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .top) {
            if item.kind.isCorner {
                Text(item.kind.name.replacingOccurrences(of: "Corner ", with: "").capitalized)
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(stoneColor).fixedSize()
                    .offset(y: -12)
            }
        }
        .position(x: rect.midX, y: rect.midY)
        .onTapGesture { selectedItem.wrappedValue = item.id }
    }

    /// Drag handles on the chosen item: a niche or window moves whole and
    /// takes its sides and top; a bench its ends and top; a corner piece moves up and down.
    @ViewBuilder
    private func itemHandles(_ i: Int, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let item = takeoff.items[i]
        let r = itemRect(item)
        let a = at(r.from, r.top), b = at(r.to, r.bottom)
        let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        let origin = at(0, 0)
        let inch = { (v: Double) in (v * 12).rounded() / 12 }
        if item.kind == .niche || item.kind == .window || item.kind.isCorner {
            // Move it.
            Color.clear.contentShape(Rectangle())
                .frame(width: max(rect.width, 30), height: max(rect.height, 30))
                .position(x: rect.midX, y: rect.midY)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("wall")).onChanged { v in
                    let start = itemDragStart ?? item
                    if itemDragStart == nil { itemDragStart = item }
                    let up = (-v.translation.height / scale * 12).rounded()
                    takeoff.items[i].bottomIn = min(max(0, start.bottomIn + up), wall.heightFt * 12 - (item.kind.isCorner ? 0 : start.heightIn))
                    if !item.kind.isCorner {
                        let w = start.widthFt
                        let from = min(max(0, inch(start.fromFt + v.translation.width / scale)), wall.lengthFt - w)
                        takeoff.items[i].fromFt = from
                        takeoff.items[i].toFt = from + w
                    }
                }.onEnded { _ in itemDragStart = nil })
        }
        if !item.kind.isCorner {
            // Just outside the edges, so a small niche stays visible.
            ItemHandle(vertical: true)
                .position(x: rect.minX - 9, y: rect.midY)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                    let ft = inch((v.location.x - origin.x) / scale)
                    takeoff.items[i].fromFt = min(max(0, ft), takeoff.items[i].toFt - 4.0 / 12)
                })
            ItemHandle(vertical: true)
                .position(x: rect.maxX + 9, y: rect.midY)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                    let ft = inch((v.location.x - origin.x) / scale)
                    takeoff.items[i].toFt = max(min(wall.lengthFt, ft), takeoff.items[i].fromFt + 4.0 / 12)
                })
            ItemHandle(vertical: false)
                .position(x: rect.midX, y: rect.minY - 9)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                    let up = ((origin.y - v.location.y) / scale * 12).rounded()
                    if item.kind.isBench {
                        takeoff.items[i].heightIn = min(max(6, up), wall.heightFt * 12)
                    } else {
                        takeoff.items[i].heightIn = min(max(4, up - item.bottomIn), wall.heightFt * 12 - item.bottomIn)
                    }
                })
        }
    }

    /// A door with new sides, in feet along the wall.
    private func moved(_ d: ScannedRoom.Opening, left: Double, right: Double) -> ScannedRoom.Opening {
        var n = d
        n.widthFt = right - left
        n.alongFt = (left + right) / 2
        return n
    }

    private func rect(_ p: AreaTakeoff.Piece, _ at: (Double, Double) -> CGPoint) -> CGRect {
        let a = at(p.fromFt, p.heightIn / 12), b = at(p.toFt, 0)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    @ViewBuilder
    private func handles(_ i: Int, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let p = takeoff.pieces[i]
        let r = rect(p, at)
        let origin = at(0, 0)
        // Left side.
        Handle(vertical: true)
            .position(x: r.minX, y: r.midY)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                let ft = snapped((v.location.x - origin.x) / scale, to: snaps)
                takeoff.pieces[i].fromFt = min(max(0, ft), takeoff.pieces[i].toFt - 1.0 / 12)
            })
        // Right side.
        Handle(vertical: true)
            .position(x: r.maxX, y: r.midY)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                let ft = snapped((v.location.x - origin.x) / scale, to: snaps)
                takeoff.pieces[i].toFt = max(min(wall.lengthFt, ft), takeoff.pieces[i].fromFt + 1.0 / 12)
            })
        // Top.
        Handle(vertical: false)
            .position(x: r.midX, y: r.minY)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wall")).onChanged { v in
                let upFt = (origin.y - v.location.y) / scale
                let tops = [wall.heightFt] + room.openings.filter { $0.wallID == wall.id }.flatMap { [$0.bottomFt, $0.bottomFt + $0.heightFt] }
                let inches = (snapped(upFt, to: tops, pull: 2.0 / 12) * 12).rounded()
                takeoff.pieces[i].heightIn = min(max(1, inches), (wall.heightFt * 12).rounded())
            })
    }
}

/// A bench's, niche's or window's grab handle: a white pill with a green edge.
private struct ItemHandle: View {
    let vertical: Bool
    var body: some View {
        Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Color.mint, lineWidth: 2.5))
            .frame(width: vertical ? 8 : 28, height: vertical ? 28 : 8)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
    }
}

/// A shower door's grab handle: a white pill with a stone-coloured edge.
private struct DoorHandle: View {
    let vertical: Bool
    var body: some View {
        Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Color(red: 0.75, green: 0.62, blue: 0.4), lineWidth: 2.5))
            .frame(width: vertical ? 12 : 34, height: vertical ? 34 : 12)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// A grab handle: a white pill with a blue edge, big enough for a thumb.
private struct Handle: View {
    let vertical: Bool
    var body: some View {
        Capsule()
            .fill(Color.white)
            .overlay(Capsule().stroke(Color.blue, lineWidth: 2))
            .frame(width: vertical ? 12 : 34, height: vertical ? 34 : 12)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Number fields

/// Inches, typed, with feet and inches shown under it.
struct InchField: View {
    let title: String
    @Binding var inches: Double
    /// Empty, not "0", until something's typed (a tape measurement not taken yet).
    var blankWhenZero = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField(blankWhenZero ? "" : "0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.body.monospacedDigit())
                Text("in").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            // Feet and inches, once it's a foot or more.
            Text(inches >= 12 ? feetAndInches(inches / 12) : " ").font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { text = shown(inches) }
        .onChange(of: inches) { _, v in if !focused { text = shown(v) } }
        .onChange(of: text) { _, t in
            if focused {
                if let v = Double(t.replacingOccurrences(of: ",", with: ".")), abs(v - inches) > 0.001 { inches = v }
                else if t.isEmpty, blankWhenZero { inches = 0 }
            }
        }
        .onChange(of: focused) { _, f in if !f { text = shown(inches) } }
    }

    private func shown(_ v: Double) -> String { blankWhenZero && v == 0 ? "" : Self.format(v) }

    static func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}

/// Square feet, typed.
private struct SqftField: View {
    @Binding var value: Double
    @State private var text = ""
    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 70)
            .onAppear { text = value == 0 ? "" : InchField.format(value) }
            .onChange(of: text) { _, t in
                let v = Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0
                if v != value { value = v }
            }
    }
}

/// The shower floor's handle: tap to resize its edges, drag to move it.
private struct FloorHandle: View {
    let symbol: String
    var active = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(active ? .white : .black)
            .frame(width: 32, height: 32)
            .background(Circle().fill(active ? Color(red: 0.1, green: 0.55, blue: 0.25) : Color.green))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.4), radius: 3)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}
