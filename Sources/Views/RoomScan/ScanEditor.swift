import SwiftUI

// Measuring an area from a room scan: the floor plan on top (pinch to zoom,
// drag to pan, double-tap to fit, tap a wall to tile it), the chosen wall
// face-on underneath (drag a piece's sides to where the tile starts and stops,
// drag its top to its height, tap a door or window to take it off), then the
// floor and ceiling. Everything moves to the sixteenth and catches on edges within 1½″.

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
    /// Measure or Extras: opened from that step, switchable inside the model.
    @State private var mode: Mode
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
    /// The door, window or opening chosen in Edit walls.
    @State private var selectedOpening: UUID? = nil
    /// Undo and redo: the room and this area's choices together.
    @State private var history: EditHistory<EditSnapshot>
    /// Changes waiting to settle into one undo step.
    @State private var settleToken = UUID()
    /// Set while undo/redo itself changes the model.
    @State private var restoring = false

    struct EditSnapshot: Equatable {
        var room: ScannedRoom
        var takeoff: AreaTakeoff
    }

    private var snapshot: EditSnapshot { EditSnapshot(room: room, takeoff: takeoff) }
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
        _mode = State(initialValue: mode)
        self.title = title
        self.others = others
        self.onUse = onUse
        self.onRescan = onRescan
        _takeoff = State(initialValue: takeoff)
        _history = State(initialValue: EditHistory(EditSnapshot(room: room, takeoff: takeoff)))
        _selectedWall = State(initialValue: takeoff.pieces.first?.wallID)
        _selectedPiece = State(initialValue: takeoff.pieces.first?.id)
    }

    private var usesWalls: Bool { area != .floor }
    /// A shower with its floor drawn on the plan: it has a curb and a drain there.
    private var showerDrawn: Bool { area == .shower && takeoff.floor == .drawn && takeoff.floorRect != nil }
    private var openSides: [AreaTakeoff.OpenSide] { area == .shower ? takeoff.openSides(in: room) : [] }

    private var content3D: Room3DContent {
        let stoneParts = Set(takeoff.trimPieces(in: room, area: area, curbHeightIn: stone.curbHeightIn).filter(\.stone).map(\.key))
        return Room3DContent(room: room, takeoff: takeoff, area: area, tile: tile, floorTile: floorTile, others: others,
                             curbHeightIn: takeoff.curbHeightIn ?? stone.curbHeightIn, stoneParts: stoneParts,
                             showFixtures: showFixtures, selectedItem: selectedItem, curbWidthFt: stone.curbWidthFt)
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
                               if !takeoff.placeShower(near: p, in: room, curbWidthFt: stone.curbWidthFt) {
                                   placeNote = "There's no cove or corner there. Tap inside the cove, or near the corner where the shower goes."
                               }
                           } : nil,
                           onResetFloor: placeShowerFloor,
                           onFloorChanged: area == .shower ? { takeoff.tileWallsAroundFloor(in: room) } : nil,
                           onFloorMoved: { takeoff.coveDepthFt = nil },
                           curbEdges: area == .shower ? takeoff.curbEdges(in: room) : [],
                           curbWidthFt: takeoff.curbless ? 0 : stone.curbWidthFt,
                           drain: showerDrawn ? $takeoff.drain : nil,
                           drainShown: showerDrawn ? takeoff.drainShown() : nil,
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
                           onMovePlannedWall: { original, d, reach in
                               let guides = takeoff.newWallLines(in: room, thicknessIn: original.thicknessIn).flatMap { [$0.0, $0.1] }
                               // Where it would be without catching, to tell whether it caught.
                               var free = room
                               free.movePlannedWall(original, by: d, guides: guides, reach: 0)
                               room.movePlannedWall(original, by: d, guides: guides, reach: reach)
                               return free.wall(original.id) != room.wall(original.id)
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
                // Taller with dimensions on: at 250 pt many numbers outgrow their walls.
                .frame(height: showDimensions ? 340 : 250)
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
                            Picker("Step", selection: Binding(get: { mode }, set: { new in
                                mode = new
                                editingWalls = false
                                addingWall = false
                                placingBench = false
                                placingShower = false
                                placing3D = nil
                                selectedItem = nil
                                selectedOpening = nil
                            })) {
                                Text("Measure").tag(Mode.measure)
                                Text("Extras").tag(Mode.extras)
                            }
                            .pickerStyle(.segmented)
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
                Text("Along the open side of the shower, \(inchText(side.lengthFt)). Move or resize it after.")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!history.canUndo && snapshot == history.current)
                        .accessibilityLabel("Undo")
                    Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!history.canRedo)
                        .accessibilityLabel("Redo")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
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
        .onChange(of: snapshot) { _, now in
            // A drag sends many changes: they settle into one step once it's still.
            if restoring { restoring = false; return }
            let token = UUID()
            settleToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if settleToken == token { history.settle(now) }
            }
        }
    }

    private func undo() {
        guard let back = history.undo(from: snapshot) else { return }
        restore(back)
    }

    private func redo() {
        guard let next = history.redo(from: snapshot) else { return }
        restore(next)
    }

    private func restore(_ s: EditSnapshot) {
        settleToken = UUID()
        restoring = true
        dragBase = nil
        room = s.room
        takeoff = s.takeoff
        if let id = selectedWall, room.wall(id) == nil { selectedWall = nil }
        if let id = selectedItem, !takeoff.items.contains(where: { $0.id == id }) { selectedItem = nil }
        if let id = selectedOpening, !room.openings.contains(where: { $0.id == id }) { selectedOpening = nil }
    }

    // MARK: Walls

    private func tapWall(_ id: UUID) {
        guard let wall = room.wall(id) else { return }
        if editingWalls && mode == .measure {
            if selectedWall != id { face = 0; selectedOpening = nil }
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
        let curbWidth = takeoff.curbless ? 0 : stone.curbWidthFt
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
                        Text("Stone: \(inchText(ft)) (\(item.stone == .all ? "top, sides, base shelf and dividers" : "base shelf and dividers"))")
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
        takeoff.coveDepthFt = nil
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
                    Text("\(inchText(wall.lengthFt)) long · \(inchText(wall.heightFt)) high")
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
                    .frame(height: 330)

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
                Text("\(inchText(wall.lengthFt)) long · \(inchText(wall.heightFt)) high")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            // The wall face-on, to move and resize its doors, windows and openings.
            Text(wall.planned ? "Seen from the \(room.faceName(of: wall, face: face).replacingOccurrences(of: "Side", with: "side"))"
                              : "Seen from inside the room")
                .font(.caption).foregroundStyle(.secondary)
            WallElevation(room: room, wall: wall, face: face, takeoff: $takeoff, selectedPiece: .constant(nil),
                          endNames: (cornerName(wall, atStart: true), cornerName(wall, atStart: false)),
                          others: others, snaps: [],
                          onDoor: { d in
                              if let i = room.openings.firstIndex(where: { $0.id == d.id }) { room.openings[i] = d }
                          },
                          editOpenings: true, selectedOpening: $selectedOpening)
                .frame(height: 330)
            wallDistances(wall)
            openingEditor(on: wall)
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
                    }), applyWhenDone: true)
                    InchField(title: "Height", inches: Binding(get: { wall.heightFt * 12 }, set: { v in
                        editRoomOnce { r in
                            if let i = r.walls.firstIndex(where: { $0.id == wall.id }) { r.walls[i].heightFt = max(12, v) / 12 }
                        }
                    }), applyWhenDone: true)
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

    /// The distance from this wall to the nearest wall running the same way
    /// on each side; typing one slides this wall there (the room follows).
    @ViewBuilder
    private func wallDistances(_ wall: ScannedRoom.Wall) -> some View {
        let near = room.parallelNeighbors(of: wall.id)
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ForEach(near, id: \.wall.id) { n in
                        InchField(title: "To wall \(n.wall.label)", inches: Binding(
                            get: { (abs(n.offset) * 12 * 4).rounded() / 4 },
                            set: { v in editRoomOnce { $0.setDistance(of: wall.id, from: n.wall.id, to: v / 12) } }),
                                  applyWhenDone: true)
                    }
                }
                Text("Wall to wall, square across. Type what you measured and this wall moves there; walls joined to it follow.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Doors, windows and openings in a wall: add one; the chosen one's kind,
    /// size, height off the floor and distance to each end, typed; delete it.
    @ViewBuilder
    private func openingEditor(on wall: ScannedRoom.Wall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { addOpening(.door, on: wall) } label: { Label("Add door", systemImage: "door.left.hand.closed") }
                    Button { addOpening(.window, on: wall) } label: { Label("Add window", systemImage: "window.horizontal") }
                    Button { addOpening(.opening, on: wall) } label: { Label("Add opening", systemImage: "rectangle.portrait") }
                }
                .fixedSize()
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
            if let id = selectedOpening, let i = room.openings.firstIndex(where: { $0.id == id && $0.wallID == wall.id }),
               room.openings[i].kind != .showerDoor {
                let o = room.openings[i]
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Kind", selection: Binding(get: { room.openings[i].kind }, set: { k in
                            room.openings[i].kind = k
                            if k == .door { room.openings[i].bottomFt = 0 }
                        })) {
                            Text("Door").tag(ScannedRoom.OpeningKind.door)
                            Text("Window").tag(ScannedRoom.OpeningKind.window)
                            Text("Opening").tag(ScannedRoom.OpeningKind.opening)
                        }
                        .pickerStyle(.segmented)
                        Button(role: .destructive) {
                            room.openings.remove(at: i)
                            selectedOpening = nil
                        } label: { Image(systemName: "trash") }
                    }
                    HStack(spacing: 12) {
                        InchField(title: "Width", inches: Binding(get: { room.openings[i].widthFt * 12 }, set: { v in
                            let w = min(max(4, v) / 12, wall.lengthFt)
                            let left = room.span(of: room.openings[i]).lowerBound
                            room.openings[i].widthFt = w
                            room.openings[i].alongFt = min(left, wall.lengthFt - w) + w / 2
                        }))
                        InchField(title: "Height", inches: Binding(get: { room.openings[i].heightFt * 12 }, set: { v in
                            room.openings[i].heightFt = min(max(4, v) / 12, wall.heightFt - room.openings[i].bottomFt)
                        }))
                        if o.kind != .door {
                            InchField(title: "Off the floor", inches: Binding(get: { room.openings[i].bottomFt * 12 }, set: { v in
                                room.openings[i].bottomFt = min(max(0, v / 12), wall.heightFt - room.openings[i].heightFt)
                            }))
                        }
                    }
                    HStack(spacing: 12) {
                        InchField(title: "To \(cornerName(wall, atStart: true))", inches: Binding(
                            get: { room.span(of: room.openings[i]).lowerBound * 12 },
                            set: { v in
                                let w = room.openings[i].widthFt
                                room.openings[i].alongFt = min(max(0, v / 12), wall.lengthFt - w) + w / 2
                            }))
                        InchField(title: "To \(cornerName(wall, atStart: false))", inches: Binding(
                            get: { (wall.lengthFt - room.span(of: room.openings[i]).upperBound) * 12 },
                            set: { v in
                                let w = room.openings[i].widthFt
                                room.openings[i].alongFt = wall.lengthFt - min(max(0, v / 12), wall.lengthFt - w) - w / 2
                            }))
                    }
                    Text("Drag it on the wall above to move it; drag its sides, top or bottom to resize it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else if room.openings.contains(where: { $0.wallID == wall.id && $0.kind != .showerDoor }) {
                Text("Tap a door, window or opening on the wall above to change it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// A door, window or opening added in the middle of a wall's free part.
    private func addOpening(_ kind: ScannedRoom.OpeningKind, on wall: ScannedRoom.Wall) {
        let (w, h, bottom): (Double, Double, Double) = switch kind {
        case .door: (32, 80, 0)
        case .window: (36, 36, 36)
        default: (36, 80, 0)
        }
        let width = min(w / 12, wall.lengthFt)
        let o = ScannedRoom.Opening(kind: kind, wallID: wall.id, widthFt: width,
                                    heightFt: min(h / 12, wall.heightFt - bottom / 12), bottomFt: bottom / 12,
                                    alongFt: wall.lengthFt / 2)
        room.openings.append(o)
        selectedOpening = o.id
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
                            Text(h == roomHeight ? "Full \(inchText(h / 12))" : "\(Int(h))″ high")
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
                if area == .shower, !takeoff.curbless {
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
                        Label("Add a wall on the \(takeoff.curbless ? "opening" : "curb") (\(inchText(side.lengthFt)) open)", systemImage: "plus.rectangle.on.rectangle")
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
                    Text(inchText(piece.lengthFt) + (abs(piece.lengthFt - piece.measuredFt) > 0.01 ? " (measured \(inchText(piece.measuredFt)))" : ""))
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
                            Text(h == full ? "Full \(inchText(h / 12))" : "\(Int(h))″")
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
            Text("From and To are measured from the \(cornerName(wall, atStart: true)) end of the wall. This piece: \(ND.number(takeoff.sqft(of: piece.wrappedValue, in: room))) sq ft.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func split(_ id: UUID) {
        guard let i = takeoff.pieces.firstIndex(where: { $0.id == id }) else { return }
        let p = takeoff.pieces[i]
        let mid = ((p.fromFt + p.toFt) / 2 * 192).rounded() / 192
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
                    Label(header ? "No header (open to the ceiling)" : "Add a header at \(inchText(min(stone.doorHeightIn / 12, wall.heightFt)))",
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
                            Text("\(inchText(o.widthFt)) × \(inchText(o.heightFt))"
                                 + (o.bottomFt > 0.1 ? ", \(inchText(o.bottomFt)) off the floor" : ""))
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
                                takeoff.coveDepthFt = nil
                                takeoff.tileWallsAroundFloor(in: room)
                            } label: {
                                Label("Rotate", systemImage: "rotate.right")
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                        Text("Put the shower here: tap inside a cove of three walls and the shower fills it, its curb flush with the cove's outside corners; tap near a corner for a 48″ × 48″ shower there. Rotate turns it in its corner. Tap the floor, then drag anywhere to move it; tap an edge to drag that edge.")
                            .font(.caption).foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            InchField(title: "Width", inches: Binding(get: { r.widthFt * 12 }, set: { takeoff.floorRect?.widthFt = max(1, $0) / 12; takeoff.coveDepthFt = nil }))
                            InchField(title: "Depth", inches: Binding(get: { r.depthFt * 12 }, set: { takeoff.floorRect?.depthFt = max(1, $0) / 12; takeoff.coveDepthFt = nil }))
                        }
                        showerCurbAndDrain
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
                                Label("Size from the shower walls: \(inchText(s.width)) × \(inchText(s.depth))",
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

    /// The shower's curb (or none: curbless) and its drain (owner's calls, 2026-10-08).
    @ViewBuilder
    private var showerCurbAndDrain: some View {
        Button {
            takeoff.setCurbless(!takeoff.curbless, curbWidthFt: stone.curbWidthFt)
        } label: {
            Label(takeoff.curbless ? "Put the curb back" : "Remove the curb (curbless)",
                  systemImage: takeoff.curbless ? "plus.rectangle" : "minus.rectangle")
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
        Text(takeoff.curbless
             ? "Curbless: no curb, jambs from the floor, and Curbless Shower on the estimate (per sq ft of shower floor, its price and minimum in Admin → Price list)."
             : "The curb is \(inchText(stone.curbWidthFt)) wide, just outside the floor on its open sides.")
            .font(.caption).foregroundStyle(.secondary)

        Text("Drain").font(.subheadline.weight(.semibold))
        Picker("Drain", selection: Binding(
            get: { takeoff.drainShown()?.kind ?? .center },
            set: { kind in takeoff.drain = kind == .linear ? takeoff.startingLinearDrain(in: room) : nil })) {
            Text("4″ square").tag(AreaTakeoff.Drain.Kind.center)
            Text("Linear").tag(AreaTakeoff.Drain.Kind.linear)
        }
        .pickerStyle(.segmented)
        if let d = takeoff.drainShown(), d.kind == .linear, let r = takeoff.floorRect {
            HStack(alignment: .bottom, spacing: 12) {
                InchField(title: "Length", inches: Binding(
                    get: { d.lengthFt * 12 },
                    set: { v in
                        var n = d
                        n.lengthFt = max(6, v) / 12
                        takeoff.drain = n
                    }))
                    .frame(maxWidth: 140)
                Button {
                    takeoff.drain = AreaTakeoff.turnedDrain(d, in: r)
                } label: { Label("Turn", systemImage: "rotate.right") }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
        }
        Text(takeoff.drainShown()?.kind == .linear
             ? "Linear Drain goes on the estimate per foot of drain (Admin → Price list). Tap it on the plan, then drag anywhere: it snaps flush to each side of the floor; tap an end to drag that end."
             : "Tap the drain on the plan, then drag anywhere to move it.")
            .font(.caption).foregroundStyle(.secondary)
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
    /// The floor itself was moved, resized or turned by hand.
    var onFloorMoved: (() -> Void)? = nil
    /// The shower's curb: open sides of its floor.
    var curbEdges: [(ScannedRoom.Point, ScannedRoom.Point)] = []
    /// How wide the curb is: drawn just outside the floor (0: a line).
    var curbWidthFt: Double = 0
    /// The shower's drain, moved when held; and how it's drawn (the chosen
    /// one kept in the floor, else a square drain in its middle).
    var drain: Binding<AreaTakeoff.Drain?>? = nil
    var drainShown: AreaTakeoff.Drain? = nil
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
    /// …and how far it catches on a line or a wall, in feet at the zoom in use.
    /// It returns whether it caught on something.
    var onMovePlannedWall: (ScannedRoom.Wall, ScannedRoom.Point, Double) -> Bool = { _, _, _ in false }
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

    /// What a drag steers, chosen with a tap (owner's call, 2026-10-08: the
    /// thumb covers what it drags, so tap it, then drag anywhere).
    enum Hold: Equatable {
        case wall(UUID)
        case wallEnd(UUID, start: Bool)
        case floor
        case floorEdge(Axis, near: Bool)
        /// The drain, or one end of a linear drain.
        case drain
        case drainEnd(start: Bool)
    }
    enum Axis: Equatable { case u, v }

    @State private var hold: Hold? = nil
    @State private var viewport = PlanViewport()
    /// The viewport as a pinch or pan began.
    @State private var viewportStart: PlanViewport? = nil
    /// Steering: what was held as the drag began, the finger's last place,
    /// and how far the thing has been steered (plan feet).
    @State private var steerWall: ScannedRoom.Wall? = nil
    @State private var steerFloor: AreaTakeoff.FloorRect? = nil
    @State private var steerDrain: AreaTakeoff.Drain? = nil
    /// Catching turned off for the thing held (the magnet), till it's let go.
    @State private var catchOff = false
    /// It's caught on something now; and where to flash green when it catches.
    @State private var caught = false
    @State private var flash: (at: ScannedRoom.Point, id: UUID)? = nil
    /// The plan's size, for the nudge buttons' directions.
    @State private var planSize: CGSize = .zero
    @State private var lastTranslation: CGSize = .zero
    @State private var steered: ScannedRoom.Point = .init()
    @State private var steering = false
    /// The wall being drawn, start and end, while dragging.
    @State private var drawing: (ScannedRoom.Point, ScannedRoom.Point)? = nil

    /// Plan feet → screen points. The plan is turned by `angle` so the
    /// room's walls run straight across and up the screen (the scanner's
    /// north is wherever the phone pointed when the scan began).
    private struct Frame {
        let size: CGSize
        /// Feet to points, zoom included.
        let scale: CGFloat
        let cx: Double, cy: Double
        let pan: CGSize
        var cosA: Double = 1
        var sinA: Double = 0
        var zoom: CGFloat = 1
        /// A point turned to line up with the screen, still in feet.
        func turned(_ p: ScannedRoom.Point) -> (Double, Double) {
            let dx = p.x - cx, dy = p.y - cy
            return (dx * cosA - dy * sinA, dx * sinA + dy * cosA)
        }
        /// view = fitted × zoom + pan, fitted = middle of the screen + turned × fit.
        func at(_ p: ScannedRoom.Point) -> CGPoint {
            let (x, y) = turned(p)
            return CGPoint(x: size.width / 2 * zoom + x * scale + pan.width,
                           y: size.height / 2 * zoom + y * scale + pan.height)
        }
        /// The plan point under a screen point.
        func point(at s: CGPoint) -> ScannedRoom.Point {
            let x = Double((s.x - size.width / 2 * zoom - pan.width) / scale)
            let y = Double((s.y - size.height / 2 * zoom - pan.height) / scale)
            return ScannedRoom.Point(x: cx + x * cosA + y * sinA, y: cy - x * sinA + y * cosA)
        }
        /// A drag on screen, in plan feet.
        func feet(_ t: CGSize) -> (Double, Double) {
            let x = Double(t.width / scale), y = Double(t.height / scale)
            return (x * cosA + y * sinA, -x * sinA + y * cosA)
        }
    }

    /// The bottom of the plan, where the hint and the 2D/3D switch sit.
    static let controlStrip: CGFloat = 40

    private func frame(_ size: CGSize) -> Frame {
        let pts = room.floorOutline + room.walls.flatMap { [$0.start, $0.end] }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let a = -room.squaringAngle
        var f = Frame(size: size, scale: 1, cx: ((xs.min() ?? 0) + (xs.max() ?? 1)) / 2,
                      cy: ((ys.min() ?? 0) + (ys.max() ?? 1)) / 2, pan: .zero, cosA: cos(a), sinA: sin(a))
        // Fit the turned room.
        let t = pts.map { f.turned($0) }
        let tx = t.map(\.0), ty = t.map(\.1)
        let minX = tx.min() ?? -1, maxX = tx.max() ?? 1, minY = ty.min() ?? -1, maxY = ty.max() ?? 1
        // Room round the edge for the dimension lines — a row more where a
        // wall's stretches go outside it.
        let rows = interactive && showDimensions && room.walls.contains { w in
            !w.planned && !PlanDimensions.isPartition(w, in: room) && !PlanDimensions.stretches(of: w, in: room).isEmpty
        }
        let margin: CGFloat = interactive && showDimensions ? (rows ? 118 : 100) : 60
        // And a strip along the bottom kept for the hint and the 2D/3D switch.
        let below: CGFloat = interactive && showDimensions ? Self.controlStrip : 0
        let fit = min((size.width - margin) / max(maxX - minX, 1), (size.height - margin - below) / max(maxY - minY, 1))
        // Centre the turned room.
        // (Up by half the strip: part of the fit, so it zooms with the room.)
        let ox = (minX + maxX) / 2, oy = (minY + maxY) / 2 + Double(below / 2 / fit)
        f = Frame(size: size, scale: fit * viewport.zoom,
                  cx: f.cx + (ox * f.cosA + oy * f.sinA), cy: f.cy + (-ox * f.sinA + oy * f.cosA),
                  pan: viewport.pan, cosA: f.cosA, sinA: f.sinA, zoom: viewport.zoom)
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            plan
                .overlay(alignment: .bottomLeading) {
                    if let text = hold == nil ? hint : "Drag anywhere to move it · tap empty space to let go" {
                        Text(text).font(.caption2).foregroundStyle(hold == nil ? .secondary : .primary).padding(8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 6) {
                        holdStrip
                        holdControls
                        floorBar
                        drainBar
                    }
                    .padding(.top, 6)
                }
        }
        .onChange(of: hold) { _, h in
            caught = false
            if h == nil { catchOff = false }
        }
        .onChange(of: selectedWall) { _, id in
            // Chosen elsewhere (3-D, the panels): let go of a different wall.
            switch hold {
            case .wall(let w), .wallEnd(let w, _): if w != id { hold = nil }
            default: break
            }
        }
    }

    private var plan: some View {
        GeometryReader { geo in
            let f = frame(geo.size)
            if interactive {
                Canvas { ctx, _ in draw(ctx, f) }
                    .onAppear { planSize = geo.size }
                    .onChange(of: geo.size) { _, s in planSize = s }
                    .contentShape(Rectangle())
                    .gesture(addingWall ? nil : zoomPanSteer(geo.size, f))
                    .overlay {
                        if addingWall {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                                    // A direct touch: it catches within the touch reach (catch test).
                                    let reach = Steering.catchFt(steered: false, ptPerFt: Double(f.scale))
                                    let a = room.snappedToWall(f.point(at: v.startLocation), pull: reach)
                                    drawing = snapNewWall(a, room.plannedEnd(from: a, toward: f.point(at: v.location), reach: reach))
                                }.onEnded { _ in
                                    if let (a, b) = drawing,
                                       ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() >= 1 {
                                        onAddWall(a, b)
                                    }
                                    drawing = nil
                                })
                        }
                    }
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.25)) { viewport = PlanViewport() }
                    }
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in tap(at: location, f) }
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if !viewport.isFitted {
                            Button {
                                withAnimation(.easeOut(duration: 0.25)) { viewport = PlanViewport() }
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

    /// The held thing's measurements, live, at the top of the plan.
    @ViewBuilder
    private var holdStrip: some View {
        let text: String? = {
            switch hold {
            case .wall(let id), .wallEnd(let id, _):
                guard let w = room.wall(id) else { return nil }
                let near = room.parallelNeighbors(of: id).map { "to wall \($0.wall.label) \(inchText(abs($0.offset)))" }
                return (["\(room.name(of: w)) \(inchText(w.lengthFt))"] + near).joined(separator: " · ")
            case .floor, .floorEdge:
                guard let r = floorRect?.wrappedValue else { return nil }
                return "Shower floor \(inchText(r.widthFt)) × \(inchText(r.depthFt))"
            case .drain, .drainEnd:
                guard let d = drainShown, let r = floorRect?.wrappedValue else { return nil }
                // How far its middle is from the floor's sides.
                let across = d.kind == .linear ? (d.runsAlongWidth ? d.alongDepthFt : d.alongWidthFt) : d.alongDepthFt
                let name = d.kind == .linear ? "Linear drain \(inchText(d.lengthFt))" : "Drain"
                _ = r
                return d.kind == .linear ? "\(name) · \(inchText(across)) to its middle"
                    : "\(name) · \(inchText(d.alongWidthFt)) × \(inchText(d.alongDepthFt)) in from the corner"
            case nil:
                return nil
            }
        }()
        if let text {
            Text(text)
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .allowsHitTesting(false)
        }
    }

    /// While the floor is held: Rotate, Reset and Done.
    @ViewBuilder
    private var floorBar: some View {
        if floorHeld, let r = floorRect?.wrappedValue {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        floorRect?.wrappedValue = r.turned
                        onFloorChanged?()
                        onFloorMoved?()
                    }
                } label: { Label("Rotate", systemImage: "rotate.right") }
                if let onResetFloor {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { onResetFloor() }
                    } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { hold = nil }
                } label: { Text("Done").fontWeight(.semibold) }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.green)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// While a linear drain is held: Turn and Done.
    @ViewBuilder
    private var drainBar: some View {
        let held = hold == .drain || { if case .drainEnd = hold { true } else { false } }()
        if held, let d = drainShown, let r = floorRect?.wrappedValue {
            HStack(spacing: 8) {
                if d.kind == .linear {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { drain?.wrappedValue = AreaTakeoff.turnedDrain(d, in: r) }
                    } label: { Label("Turn", systemImage: "rotate.right") }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { hold = nil }
                } label: { Text("Done").fontWeight(.semibold) }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.green)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: Tap to choose, drag anywhere to steer

    /// What a tap chooses: a wall's end (of the chosen wall), the floor's
    /// edge or the floor (once the floor is held), the curb, a wall, the
    /// floor; empty space lets go.
    private func tap(at location: CGPoint, _ f: Frame) {
        if let onTapPoint { onTapPoint(f.point(at: location)); return }
        // The drain: a linear drain's end once it's held, else the drain.
        if drain != nil, let r = floorRect?.wrappedValue, let d = drainShown {
            if d.kind == .linear, hold == .drain || { if case .drainEnd = hold { true } else { false } }() {
                for start in [true, false] where hypot(location.x - f.at(drainEnd(d, r, start: start)).x,
                                                       location.y - f.at(drainEnd(d, r, start: start)).y) < 18 {
                    hold = .drainEnd(start: start)
                    return
                }
            }
            let k = AreaTakeoff.drainOutline(d, in: r).map(f.at)
            let box = CGRect(x: k.map(\.x).min()! - 10, y: k.map(\.y).min()! - 10,
                             width: k.map(\.x).max()! - k.map(\.x).min()! + 20, height: k.map(\.y).max()! - k.map(\.y).min()! + 20)
            if box.contains(location) { hold = .drain; return }
        }
        let editable: (ScannedRoom.Wall) -> Bool = { $0.planned || editAnyWall }
        // An end of the chosen wall.
        if let id = selectedWall, let w = room.wall(id), editable(w) {
            for start in [true, false] where hypot(location.x - f.at(start ? w.start : w.end).x,
                                                   location.y - f.at(start ? w.start : w.end).y) < 22 {
                hold = .wallEnd(id, start: start)
                return
            }
        }
        // The floor's edges and body, once the floor is held.
        if floorHeld, let r = floorRect?.wrappedValue {
            if let e = floorEdge(at: location, r, f) { hold = .floorEdge(e.axis, near: e.near); return }
            if inside(location, r, f) { hold = .floor; return }
        }
        // Inside the floor (not right on its edge) is the floor, before the curb or a wall.
        if let r = floorRect?.wrappedValue, inside(location, r, f), floorEdge(at: location, r, f, reach: 10) == nil {
            hold = .floor
            return
        }
        if let side = openSide(at: location, f) { hold = nil; onTapOpenSide(side); return }
        if let id = wall(at: location, f) {
            onTapWall(id)
            if let w = room.wall(id), editable(w) { hold = .wall(id) } else { hold = nil }
            return
        }
        if let r = floorRect?.wrappedValue, inside(location, r, f) { hold = .floor; return }
        hold = nil
    }

    /// Entering a catch: a light tick and a green flash where it caught
    /// (owner's call, 2026-10-08, so an unwanted catch is plain to see).
    private func cue(_ isCaught: Bool, at p: ScannedRoom.Point?) {
        if isCaught, !caught, let p {
            UISelectionFeedbackGenerator().selectionChanged()
            let id = UUID()
            flash = (p, id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if flash?.id == id { flash = nil } }
        }
        caught = isCaught
    }

    /// While something is held: the magnet (catching on or off for it) and
    /// nudge arrows, a sixteenth a tap, catching nothing.
    @ViewBuilder
    private var holdControls: some View {
        if interactive, let hold, planSize != .zero {
            let f = frame(planSize)
            HStack(spacing: 6) {
                Button {
                    catchOff.toggle()
                } label: {
                    Label(catchOff ? "Catch off" : "Catch on", systemImage: catchOff ? "scope" : "dot.scope")
                        .labelStyle(.titleAndIcon)
                }
                .tint(catchOff ? .orange : .green)
                ForEach(Array(nudgeAxes(hold).enumerated()), id: \.offset) { _, axis in
                    nudgeButtons(axis, f)
                }
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// The directions a held thing nudges along, on the plan.
    private func nudgeAxes(_ hold: Hold) -> [ScannedRoom.Point] {
        func unit(_ w: ScannedRoom.Wall) -> ScannedRoom.Point {
            let l = max(w.lengthFt, 1e-9)
            return .init(x: (w.end.x - w.start.x) / l, y: (w.end.y - w.start.y) / l)
        }
        switch hold {
        case .wall(let id):
            guard let w = room.wall(id) else { return [] }
            let u = unit(w)
            return [.init(x: -u.y, y: u.x)]
        case .wallEnd(let id, _):
            return room.wall(id).map { [unit($0)] } ?? []
        case .floor, .drain:
            guard let r = floorRect?.wrappedValue else { return [] }
            return [r.u, r.v]
        case .floorEdge(let axis, _):
            guard let r = floorRect?.wrappedValue else { return [] }
            return [axis == .u ? r.u : r.v]
        case .drainEnd:
            guard let r = floorRect?.wrappedValue, let d = drainShown else { return [] }
            return [d.runsAlongWidth ? r.u : r.v]
        }
    }

    /// Two arrows for one direction, pointing the way it goes on screen.
    private func nudgeButtons(_ dir: ScannedRoom.Point, _ f: Frame) -> some View {
        let a = f.at(.init(x: 0, y: 0)), b = f.at(dir)
        let sx = b.x - a.x, sy = b.y - a.y
        let across = abs(sx) >= abs(sy)
        // The step that moves it right (or up) on screen.
        let sign: Double = across ? (sx >= 0 ? 1 : -1) : (sy <= 0 ? 1 : -1)
        let step = ScannedRoom.Point(x: dir.x * sign / 192, y: dir.y * sign / 192)
        return HStack(spacing: 2) {
            Button { nudge(by: .init(x: -step.x, y: -step.y)) } label: {
                Image(systemName: across ? "chevron.left" : "chevron.down").frame(width: 16, height: 18)
            }
            Button { nudge(by: step) } label: {
                Image(systemName: across ? "chevron.right" : "chevron.up").frame(width: 16, height: 18)
            }
        }
    }

    /// The held thing moved a sixteenth along `d` (plan feet), catching nothing.
    private func nudge(by d: ScannedRoom.Point) {
        guard let hold else { return }
        switch hold {
        case .wall(let id):
            guard let w = room.wall(id) else { return }
            if w.planned { _ = onMovePlannedWall(w, d, 0) } else { onMoveWall(id, d) }
            onWallDragEnded()
        case .wallEnd(let id, let start):
            guard let w = room.wall(id) else { return }
            let e = start ? w.start : w.end
            let p = ScannedRoom.Point(x: e.x + d.x, y: e.y + d.y)
            if w.planned { onMovePlannedEnd(id, start, p) } else { onMoveWallEnd(id, start, p) }
            onWallDragEnded()
        case .floor:
            floorRect?.wrappedValue?.origin = .init(x: (floorRect?.wrappedValue?.origin.x ?? 0) + d.x,
                                                    y: (floorRect?.wrappedValue?.origin.y ?? 0) + d.y)
            onFloorChanged?()
            onFloorMoved?()
        case .floorEdge(let axis, let near):
            guard var r = floorRect?.wrappedValue else { return }
            let dir = axis == .u ? r.u : r.v
            let by = d.x * dir.x + d.y * dir.y
            if near {
                // The near edge moves; the far edge stays.
                r.origin = .init(x: r.origin.x + dir.x * by, y: r.origin.y + dir.y * by)
                if axis == .u { r.widthFt = max(0.5, r.widthFt - by) } else { r.depthFt = max(0.5, r.depthFt - by) }
            } else if axis == .u { r.widthFt = max(0.5, r.widthFt + by) } else { r.depthFt = max(0.5, r.depthFt + by) }
            floorRect?.wrappedValue = r
            onFloorChanged?()
            onFloorMoved?()
        case .drain:
            guard let r = floorRect?.wrappedValue, var dr = drain?.wrappedValue ?? drainShown else { return }
            dr.alongWidthFt += d.x * r.u.x + d.y * r.u.y
            dr.alongDepthFt += d.x * r.v.x + d.y * r.v.y
            drain?.wrappedValue = dr
        case .drainEnd(let atStart):
            guard let r = floorRect?.wrappedValue, var dr = drain?.wrappedValue ?? drainShown, dr.kind == .linear else { return }
            let dir = dr.runsAlongWidth ? r.u : r.v
            let by = d.x * dir.x + d.y * dir.y
            let mid = dr.runsAlongWidth ? dr.alongWidthFt : dr.alongDepthFt
            var lo = mid - dr.lengthFt / 2, hi = mid + dr.lengthFt / 2
            if atStart { lo = min(lo + by, hi - 6.0 / 12) } else { hi = max(hi + by, lo + 6.0 / 12) }
            dr.lengthFt = hi - lo
            if dr.runsAlongWidth { dr.alongWidthFt = (lo + hi) / 2 } else { dr.alongDepthFt = (lo + hi) / 2 }
            drain?.wrappedValue = dr
        }
    }

    /// One end of a linear drain, on the plan.
    private func drainEnd(_ d: AreaTakeoff.Drain, _ r: AreaTakeoff.FloorRect, start: Bool) -> ScannedRoom.Point {
        let k = AreaTakeoff.drainOutline(d, in: r)
        // The ends are the short sides: k0–k3 and k1–k2 along the width, k0–k1 and k3–k2 along the depth.
        let (p, q) = d.runsAlongWidth ? ((k[0], k[3]), (k[1], k[2])) : ((k[0], k[1]), (k[3], k[2]))
        let e = start ? p : q
        return .init(x: (e.0.x + e.1.x) / 2, y: (e.0.y + e.1.y) / 2)
    }

    private var floorHeld: Bool {
        switch hold { case .floor, .floorEdge: true; default: false }
    }

    private func inside(_ p: CGPoint, _ r: AreaTakeoff.FloorRect, _ f: Frame) -> Bool {
        AreaTakeoff.inside(r.corners, f.point(at: p))
    }

    /// The floor's edge within reach of a tap: which axis it bounds and
    /// whether it's the edge at the floor's origin.
    private func floorEdge(at p: CGPoint, _ r: AreaTakeoff.FloorRect, _ f: Frame, reach: CGFloat = 18) -> (axis: Axis, near: Bool)? {
        let c = r.corners
        let edges: [(ScannedRoom.Point, ScannedRoom.Point, Axis, Bool)] = [
            (c[0], c[1], .v, true), (c[1], c[2], .u, false), (c[2], c[3], .v, false), (c[3], c[0], .u, true),
        ]
        let best = edges.map { ($0.2, $0.3, distance(p, f.at($0.0), f.at($0.1))) }.min { $0.2 < $1.2 }
        guard let best, best.2 < reach else { return nil }
        return (best.0, best.1)
    }

    /// Pinch zooms about the fingers; a drag steers what's held (by the
    /// finger's speed), or pans when nothing is.
    private func zoomPanSteer(_ size: CGSize, _ f: Frame) -> some Gesture {
        let magnify = MagnifyGesture()
            .onChanged { v in
                let base = viewportStart ?? viewport
                if viewportStart == nil { viewportStart = viewport }
                viewport = base.zoomed(to: base.zoom * v.magnification, about: v.startLocation).clamped(in: size)
            }
            .onEnded { _ in viewportStart = nil }
        let drag = DragGesture(minimumDistance: 6)
            .onChanged { v in
                if let hold {
                    steer(hold, by: CGSize(width: v.translation.width - lastTranslation.width,
                                           height: v.translation.height - lastTranslation.height), f, size)
                    lastTranslation = v.translation
                } else {
                    let base = viewportStart ?? viewport
                    if viewportStart == nil { viewportStart = viewport }
                    viewport = base.panned(by: v.translation).clamped(in: size)
                }
            }
            .onEnded { _ in
                viewportStart = nil
                lastTranslation = .zero
                caught = false
                if steering {
                    steering = false
                    steerWall = nil
                    steerFloor = nil
                    steerDrain = nil
                    steered = .init()
                    onWallDragEnded()
                    if floorRect != nil { onFloorChanged?() }
                    if floorHeld { onFloorMoved?() }
                }
            }
        return magnify.simultaneously(with: drag)
    }

    /// One step of a drag, applied to what's held from where it started.
    private func steer(_ hold: Hold, by delta: CGSize, _ f: Frame, _ size: CGSize) {
        if !steering {
            steering = true
            steered = .init()
            switch hold {
            case .wall(let id), .wallEnd(let id, _): steerWall = room.wall(id)
            case .floor, .floorEdge: steerFloor = floorRect?.wrappedValue
            case .drain, .drainEnd: steerDrain = drain?.wrappedValue ?? drainShown
            }
        }
        let (fx, fy) = f.feet(Steering.steered(delta))
        steered = .init(x: steered.x + fx, y: steered.y + fy)
        // How far it catches, at this zoom (catch test: steered, in points);
        // nothing with the magnet off.
        let reach = catchOff ? 0 : Steering.catchFt(ptPerFt: Double(f.scale))
        var shown: ScannedRoom.Point? = nil
        switch hold {
        case .wall(let id):
            guard let base = steerWall else { return }
            shown = room.wall(id).map { .init(x: ($0.start.x + $0.end.x) / 2, y: ($0.start.y + $0.end.y) / 2) }
            if base.planned { cue(onMovePlannedWall(base, steered, reach), at: shown) } else { onMoveWall(id, steered) }
        case .wallEnd(let id, let start):
            guard let base = steerWall else { return }
            let from = start ? base.start : base.end, other = start ? base.end : base.start
            let target = ScannedRoom.Point(x: from.x + steered.x, y: from.y + steered.y)
            let p = room.plannedEnd(from: other, toward: target, except: id, reach: reach)
            let free = room.plannedEnd(from: other, toward: target, except: id, reach: 0)
            cue(hypot(p.x - free.x, p.y - free.y) > 1e-9, at: p)
            if base.planned { onMovePlannedEnd(id, start, p) } else { onMoveWallEnd(id, start, p) }
            shown = p
        case .floor:
            guard let start = steerFloor, let binding = floorRect else { return }
            let a = Steering.sixteenth(steered.x * start.u.x + steered.y * start.u.y)
            let b = Steering.sixteenth(steered.x * start.v.x + steered.y * start.v.y)
            binding.wrappedValue?.origin = .init(x: start.origin.x + start.u.x * a + start.v.x * b,
                                                 y: start.origin.y + start.u.y * a + start.v.y * b)
            shown = binding.wrappedValue?.center
        case .floorEdge(let axis, let near):
            guard let start = steerFloor, let binding = floorRect else { return }
            let dir = axis == .u ? start.u : start.v
            let out = near ? ScannedRoom.Point(x: -dir.x, y: -dir.y) : dir
            let old = axis == .u ? start.widthFt : start.depthFt
            let side = axis == .u ? start.v : start.u
            let sideLen = axis == .u ? start.depthFt : start.widthFt
            var anchor = ScannedRoom.Point(x: start.origin.x + side.x * sideLen / 2, y: start.origin.y + side.y * sideLen / 2)
            if near { anchor = .init(x: anchor.x + dir.x * old, y: anchor.y + dir.y * old) }
            let length = snapLength(old + steered.x * out.x + steered.y * out.y, from: anchor, toward: out, reach: reach)
            let free = snapLength(old + steered.x * out.x + steered.y * out.y, from: anchor, toward: out, reach: 0)
            cue(abs(length - free) > 1e-9, at: .init(x: anchor.x + out.x * length, y: anchor.y + out.y * length))
            var updated = start
            if axis == .u { updated.widthFt = length } else { updated.depthFt = length }
            if near {
                updated.origin = .init(x: start.origin.x - dir.x * (length - old), y: start.origin.y - dir.y * (length - old))
            }
            binding.wrappedValue = updated
            shown = .init(x: anchor.x + out.x * length, y: anchor.y + out.y * length)
        case .drain:
            guard let start = steerDrain, let r = floorRect?.wrappedValue, let binding = drain else { return }
            let a = steered.x * r.u.x + steered.y * r.u.y, b = steered.x * r.v.x + steered.y * r.v.y
            let moved = AreaTakeoff.snappedDrain(start, in: r, alongWidth: start.alongWidthFt + a,
                                                 alongDepth: start.alongDepthFt + b, pull: reach)
            let free = AreaTakeoff.snappedDrain(start, in: r, alongWidth: start.alongWidthFt + a,
                                                alongDepth: start.alongDepthFt + b, pull: 0)
            binding.wrappedValue = moved
            cue(moved != free, at: .init(x: r.origin.x + r.u.x * moved.alongWidthFt + r.v.x * moved.alongDepthFt,
                                         y: r.origin.y + r.u.y * moved.alongWidthFt + r.v.y * moved.alongDepthFt))
        case .drainEnd(let atStart):
            guard let start = steerDrain, start.kind == .linear, let r = floorRect?.wrappedValue, let binding = drain else { return }
            // Along its run: the held end moves, the other stays; an end
            // snaps to the floor's side within 1½″, else to the sixteenth.
            let dir = start.runsAlongWidth ? r.u : r.v
            let run = start.runsAlongWidth ? r.widthFt : r.depthFt
            let mid = start.runsAlongWidth ? start.alongWidthFt : start.alongDepthFt
            var lo = mid - start.lengthFt / 2, hi = mid + start.lengthFt / 2
            let moved = steered.x * dir.x + steered.y * dir.y
            func snapEnd(_ v: Double) -> Double {
                for t in [0, run] where abs(v - t) < reach { return t }
                return Steering.sixteenth(v)
            }
            let raw = (atStart ? lo : hi) + moved
            cue(abs(snapEnd(raw) - Steering.sixteenth(raw)) > 1e-9, at: drainEnd(start, r, start: atStart))
            if atStart { lo = min(max(0, snapEnd(lo + moved)), hi - 6.0 / 12) } else { hi = max(min(run, snapEnd(hi + moved)), lo + 6.0 / 12) }
            var d = start
            d.lengthFt = hi - lo
            if d.runsAlongWidth { d.alongWidthFt = (lo + hi) / 2 } else { d.alongDepthFt = (lo + hi) / 2 }
            binding.wrappedValue = d
        }
        // Keep it on screen.
        if let shown { viewport = viewport.keeping(f.at(shown), in: size) }
    }

    /// A length rounded to the sixteenth, or to where it would meet a wall
    /// when within 1½″, measured from `from` toward `dir`.
    private func snapLength(_ length: Double, from o: ScannedRoom.Point, toward dir: ScannedRoom.Point,
                            reach: Double = Steering.catchFt) -> Double {
        var best = max(6.0 / 12, Steering.sixteenth(length))
        var bestGap = reach
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
            ctx.draw(Text(inchText(len)).font(.caption.weight(.semibold)).foregroundColor(.green),
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
            let held = floorHeld
            ctx.fill(path, with: .color(Color.green.opacity(hold == .floor ? 0.32 : 0.18)))
            if held {
                ctx.stroke(path, with: .color(Color.green), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            } else {
                ctx.stroke(path, with: .color(Color.green.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            // The held edge, thick.
            if case .floorEdge(let axis, let near) = hold {
                let c = r.corners
                let (a, b): (ScannedRoom.Point, ScannedRoom.Point) = switch (axis, near) {
                case (.v, true): (c[0], c[1])
                case (.u, false): (c[1], c[2])
                case (.v, false): (c[2], c[3])
                case (.u, true): (c[3], c[0])
                }
                var e = Path()
                e.move(to: f.at(a)); e.addLine(to: f.at(b))
                ctx.stroke(e, with: .color(.white), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                ctx.stroke(e, with: .color(.green), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if interactive, !held, !showDimensions {
                let c = r.corners
                let center = f.at(ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2))
                ctx.draw(Text(Image(systemName: "hand.tap")).font(.system(size: 15)).foregroundColor(.green), at: center)
            }
        }
        // The drain: a 4″ square grate, or a linear one.
        if let r = floorRect?.wrappedValue ?? floorRectShown, let d = drainShown {
            let k = AreaTakeoff.drainOutline(d, in: r).map(f.at)
            var grate = Path()
            grate.addLines(k)
            grate.closeSubpath()
            ctx.fill(grate, with: .color(Color(white: 0.12)))
            let held = hold == .drain || { if case .drainEnd = hold { true } else { false } }()
            ctx.stroke(grate, with: .color(held ? .green : Color(white: 0.75)), lineWidth: held ? 2.5 : 1.2)
            // Its slots.
            var slots = Path()
            if d.kind == .linear {
                let (a0, a1) = (CGPoint(x: (k[0].x + k[3].x) / 2, y: (k[0].y + k[3].y) / 2),
                                CGPoint(x: (k[1].x + k[2].x) / 2, y: (k[1].y + k[2].y) / 2))
                let (b0, b1) = (CGPoint(x: (k[0].x + k[1].x) / 2, y: (k[0].y + k[1].y) / 2),
                                CGPoint(x: (k[3].x + k[2].x) / 2, y: (k[3].y + k[2].y) / 2))
                // Along its length.
                let longer = hypot(a1.x - a0.x, a1.y - a0.y) >= hypot(b1.x - b0.x, b1.y - b0.y)
                let (p, q) = longer ? (a0, a1) : (b0, b1)
                slots.move(to: p); slots.addLine(to: q)
                if held, interactive {
                    for end in [p, q] {
                        let ring = Path(ellipseIn: CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14))
                        let isHeld = hold == .drainEnd(start: end == p)
                        ctx.fill(ring, with: .color(isHeld ? .green : .white))
                        ctx.stroke(ring, with: .color(.green), lineWidth: 2)
                    }
                }
            } else {
                slots.move(to: k[0]); slots.addLine(to: k[2])
                slots.move(to: k[1]); slots.addLine(to: k[3])
            }
            ctx.stroke(slots, with: .color(Color(white: 0.6)), lineWidth: 1)
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
        let floorMid = (floorRect?.wrappedValue ?? floorRectShown)?.center
        for (a, b) in curbEdges {
            // Its inside face on the floor's edge, as wide as it is.
            let len = max(hypot(b.x - a.x, b.y - a.y), 1e-9)
            var n = ScannedRoom.Point(x: -(b.y - a.y) / len, y: (b.x - a.x) / len)
            if let m = floorMid, ((a.x + b.x) / 2 - m.x) * n.x + ((a.y + b.y) / 2 - m.y) * n.y < 0 { n = .init(x: -n.x, y: -n.y) }
            let w = max(curbWidthFt, 1.5 / 12)
            var band = Path()
            band.addLines([f.at(a), f.at(b), f.at(.init(x: b.x + n.x * w, y: b.y + n.y * w)), f.at(.init(x: a.x + n.x * w, y: a.y + n.y * w))])
            band.closeSubpath()
            ctx.fill(band, with: .color(Color(red: 0.85, green: 0.78, blue: 0.62)))
            let m = CGPoint(x: (f.at(a).x + f.at(b).x) / 2, y: (f.at(a).y + f.at(b).y) / 2)
            if interactive, !showDimensions {
                ctx.draw(Text("Curb").font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 0.85, green: 0.78, blue: 0.62)), at: CGPoint(x: m.x, y: m.y + 11))
            }
        }
        // The chosen wall that can move: its ends; what's held, lit.
        if interactive, let id = selectedWall, let w = room.wall(id), w.planned || editAnyWall {
            var line = Path()
            line.move(to: f.at(w.start)); line.addLine(to: f.at(w.end))
            if hold == .wall(id) {
                ctx.stroke(line, with: .color(.green), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            for start in [true, false] {
                let c = f.at(start ? w.start : w.end)
                let ring = Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
                let held = hold == .wallEnd(id, start: start)
                ctx.fill(ring, with: .color(held ? .green : .white))
                ctx.stroke(ring, with: .color(.green), lineWidth: 2.5)
            }
        }

        // Wall labels, just inside the room.
        let cx = room.walls.map { ($0.start.x + $0.end.x) / 2 }.reduce(0, +) / Double(max(room.walls.count, 1))
        let cy = room.walls.map { ($0.start.y + $0.end.y) / 2 }.reduce(0, +) / Double(max(room.walls.count, 1))
        for w in room.walls {
            let toward = letterSpot(w, f, center: .init(x: cx, y: cy))
            let label = Text(interactive && !showDimensions ? "\(w.label)  \(inchText(w.lengthFt))" : w.label)
                .font(.system(size: interactive ? 11 : 10, weight: .semibold))
                .foregroundColor(mine.contains { $0.wallID == w.id } ? .blue : Color(white: 0.75))
            ctx.draw(label, at: f.at(toward))
        }
        if interactive && showDimensions { drawDimensions(ctx, f, center: .init(x: cx, y: cy)) }
        // Just caught on something: a green flash where.
        if let flash {
            let c = f.at(flash.at)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26)), with: .color(.green), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.green))
        }
    }

    /// The plan's dimensions (`PlanDimensions`), laid out by
    /// `PlanDimensionPlacer` round what's already drawn, as architectural
    /// dimension lines: extension lines, slash ticks, the length on a dark patch.
    private func drawDimensions(_ ctx: GraphicsContext, _ f: Frame, center: ScannedRoom.Point) {
        let floor = floorRect?.wrappedValue ?? floorRectShown
        let dims = PlanDimensions.build(room: room, floor: floor, curbEdges: curbEdges, items: items,
                                        inward: { inward($0, face: $1) })
        // Everything already drawn claims its space: walls, the floor, curb,
        // tub and benches as lines, the wall letters as boxes.
        var placer = PlanDimensionPlacer()
        for w in room.walls {
            placer.claim(from: f.at(w.start), to: f.at(w.end))
            placer.edges.append((f.at(w.start), f.at(w.end)))
        }
        if let r = floor {
            let c = r.corners.map(f.at)
            for i in 0..<4 {
                placer.claim(from: c[i], to: c[(i + 1) % 4])
                placer.edges.append((c[i], c[(i + 1) % 4]))
            }
        }
        for (a, b) in curbEdges { placer.claim(from: f.at(a), to: f.at(b)) }
        if let r = floor, let d = drainShown {
            let k = AreaTakeoff.drainOutline(d, in: r).map(f.at)
            for i in k.indices { placer.claim(from: k[i], to: k[(i + 1) % k.count]) }
        }
        if room.tubOutline.count > 2 {
            let t = room.tubOutline.map(f.at)
            for i in t.indices { placer.claim(from: t[i], to: t[(i + 1) % t.count]) }
        }
        for w in room.walls {
            let at = f.at(letterSpot(w, f, center: center))
            placer.claimForLabelsOnly(CGRect(x: at.x - 8, y: at.y - 8, width: 16, height: 16))
        }
        placer.claimForLabelsOnly(CGRect(x: 0, y: f.size.height - Self.controlStrip,
                                         width: f.size.width, height: Self.controlStrip))
        placer.page = CGRect(x: 0, y: 0, width: f.size.width, height: f.size.height - Self.controlStrip)
        DimensionDrawing.draw(ctx, placer.layout(dims, at: f.at, measure: { DimensionDrawing.measure(ctx, $0) }))
    }

    /// Where a wall's letter goes: just inside the wall, a fixed distance on screen.
    private func letterSpot(_ w: ScannedRoom.Wall, _ f: Frame, center: ScannedRoom.Point) -> ScannedRoom.Point {
        let mid = ScannedRoom.Point(x: (w.start.x + w.end.x) / 2, y: (w.start.y + w.end.y) / 2)
        let dx = center.x - mid.x, dy = center.y - mid.y
        let len = max((dx * dx + dy * dy).squareRoot(), 1e-9)
        let inward = Double(interactive ? 16 : 9) / Double(f.scale)
        return ScannedRoom.Point(x: mid.x + dx / len * inward, y: mid.y + dy / len * inward)
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
    /// Editing the room: tapping a door, window or opening chooses it to
    /// move and resize (instead of taking it off the tile).
    var editOpenings = false
    var selectedOpening: Binding<UUID?> = .constant(nil)

    private let inset: CGFloat = 14
    private static let stone = Color(red: 0.85, green: 0.78, blue: 0.62)

    /// What a drag steers (owner's call, 2026-10-08): tap a thing to choose
    /// it, tap one of its edges (or its middle, to move it), then drag
    /// anywhere on the wall.
    enum Part: Equatable { case move, left, right, top, bottom }
    enum Hold: Equatable {
        case piece(UUID, Part)
        case item(UUID, Part)
        case opening(UUID, Part)
    }
    @State private var hold: Hold? = nil
    @State private var holdPiece: AreaTakeoff.Piece? = nil
    @State private var holdItem: AreaTakeoff.Item? = nil
    @State private var holdOpening: ScannedRoom.Opening? = nil
    @State private var steeredFt: CGSize = .zero
    @State private var lastTranslation: CGSize = .zero
    private let sixteenth = 1.0 / 192
    /// The magnet off for what's held; caught now; where to flash green
    /// (feet along, or feet up) when it catches.
    @State private var catchOff = false
    @State private var caught = false
    @State private var flash: (along: Double?, up: Double?, id: UUID)? = nil

    var body: some View {
        GeometryReader { geo in
            // Room for the dimension row under the wall and the column of heights beside it.
            let w = geo.size.width - 2 * inset - Self.heightColumn, h = geo.size.height - 2 * inset - Self.belowWall
            let scale = min(w / max(wall.lengthFt, 0.5), h / max(wall.heightFt, 0.5))
            let width = wall.lengthFt * scale, height = wall.heightFt * scale
            let origin = CGPoint(x: inset + (w - width) / 2 + 8, y: inset + (h - height) / 2 + height)
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
                    .onTapGesture { hold = nil }

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
                            Text("\(inchText(p.toFt - p.fromFt)) × \(inchText(p.heightIn / 12))")
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
                        .onTapGesture {
                            if selectedPiece != p.id { hold = nil }
                            selectedPiece = p.id
                            selectedItem.wrappedValue = nil
                        }
                }

                // Doors and windows.
                ForEach(room.openings.filter { $0.wallID == wall.id && $0.kind != .showerDoor }) { o in
                    openingView(o, scale: scale, at: at)
                }

                // The chosen door, window or opening: move it, drag its sides, top and bottom.
                if editOpenings, let id = selectedOpening.wrappedValue,
                   let o = room.openings.first(where: { $0.id == id && $0.wallID == wall.id && $0.kind != .showerDoor }) {
                    openingHandles(o, scale: scale, at: at)
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

                // The dimensions (`WallDimensions`), laid out round what's drawn.
                Canvas { ctx, size in
                    drawDimensions(ctx, size: size, at: at, scale: scale, origin: origin, width: width)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
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
                .position(x: origin.x + width / 2, y: origin.y + Self.belowWall - 6)

                // Just caught: a green line where.
                if let flash {
                    Path { p in
                        if let a = flash.along {
                            p.move(to: at(a, 0)); p.addLine(to: at(a, wall.heightFt))
                        }
                        if let u = flash.up {
                            p.move(to: at(0, u)); p.addLine(to: at(wall.lengthFt, u))
                        }
                    }
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                    .allowsHitTesting(false)
                }

                if let hold {
                    holdControls(hold).padding(6)
                } else {
                    Text("Tap a side or the middle, then drag anywhere")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                        .padding(6)
                        .opacity(selectedPiece != nil || selectedItem.wrappedValue != nil || selectedOpening.wrappedValue != nil ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "wall")
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("wall"))
                .onChanged { v in
                    guard let hold else { return }
                    let step = Steering.steered(CGSize(width: v.translation.width - lastTranslation.width,
                                                       height: v.translation.height - lastTranslation.height))
                    lastTranslation = v.translation
                    steeredFt = CGSize(width: steeredFt.width + step.width / scale,
                                       height: steeredFt.height - step.height / scale)
                    steer(hold, reach: catchOff ? 0 : Steering.catchFt(ptPerFt: scale))
                }
                .onEnded { _ in
                    lastTranslation = .zero
                    steeredFt = .zero
                    caught = false
                    holdPiece = nil; holdItem = nil; holdOpening = nil
                })
        }
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: hold) { _, h in
            caught = false
            if h == nil { catchOff = false }
        }
        .onChange(of: selectedPiece) { _, _ in if case .piece = hold { hold = nil } }
        .onChange(of: selectedItem.wrappedValue) { _, _ in if case .item = hold { hold = nil } }
        .onChange(of: selectedOpening.wrappedValue) { _, _ in if case .opening = hold { hold = nil } }
    }

    /// One step of a drag, applied to what's held from where it started
    /// (to the sixteenth, snapping to nearby edges).
    private func steer(_ hold: Hold, reach: Double) {
        let dx = Double(steeredFt.width), dy = Double(steeredFt.height)
        switch hold {
        case .piece(let id, let part):
            guard let i = takeoff.pieces.firstIndex(where: { $0.id == id }) else { return }
            if holdPiece == nil { holdPiece = takeoff.pieces[i] }
            guard let start = holdPiece else { return }
            switch part {
            case .left:
                let ft = snapped(start.fromFt + dx, to: snaps, pull: reach)
                cue(start.fromFt + dx, ft, along: true)
                takeoff.pieces[i].fromFt = min(max(0, ft), takeoff.pieces[i].toFt - 1.0 / 12)
            case .right:
                let ft = snapped(start.toFt + dx, to: snaps, pull: reach)
                cue(start.toFt + dx, ft, along: true)
                takeoff.pieces[i].toFt = max(min(wall.lengthFt, ft), takeoff.pieces[i].fromFt + 1.0 / 12)
            case .top:
                let tops = [wall.heightFt] + room.openings.filter { $0.wallID == wall.id }.flatMap { [$0.bottomFt, $0.bottomFt + $0.heightFt] }
                let up = snapped(start.heightIn / 12 + dy, to: tops, pull: reach)
                cue(start.heightIn / 12 + dy, up, along: false)
                takeoff.pieces[i].heightIn = min(max(1, up * 12), wall.heightFt * 12)
            default: break
            }
        case .item(let id, let part):
            guard let i = takeoff.items.firstIndex(where: { $0.id == id }) else { return }
            if holdItem == nil { holdItem = takeoff.items[i] }
            guard let start = holdItem else { return }
            let s16 = { (v: Double) in (v / self.sixteenth).rounded() * self.sixteenth }
            switch part {
            case .move:
                let up = s16(dy) * 12
                takeoff.items[i].bottomIn = min(max(0, start.bottomIn + up), wall.heightFt * 12 - (start.kind.isCorner ? 0 : start.heightIn))
                if !start.kind.isCorner {
                    let w = start.widthFt
                    let from = min(max(0, s16(start.fromFt + dx)), wall.lengthFt - w)
                    takeoff.items[i].fromFt = from
                    takeoff.items[i].toFt = from + w
                }
            case .left:
                takeoff.items[i].fromFt = min(max(0, s16(start.fromFt + dx)), takeoff.items[i].toFt - 4.0 / 12)
            case .right:
                takeoff.items[i].toFt = max(min(wall.lengthFt, s16(start.toFt + dx)), takeoff.items[i].fromFt + 4.0 / 12)
            case .top:
                if start.kind.isBench {
                    takeoff.items[i].heightIn = min(max(6, start.heightIn + s16(dy) * 12), wall.heightFt * 12)
                } else {
                    takeoff.items[i].heightIn = min(max(4, start.heightIn + s16(dy) * 12), wall.heightFt * 12 - start.bottomIn)
                }
            case .bottom:
                break
            }
        case .opening(let id, let part):
            guard let o = room.openings.first(where: { $0.id == id }) else { return }
            if holdOpening == nil { holdOpening = o }
            guard let start = holdOpening else { return }
            let s16 = { (v: Double) in (v / self.sixteenth).rounded() * self.sixteenth }
            let s0 = room.span(of: start)
            let width = s0.upperBound - s0.lowerBound
            var n = start
            switch part {
            case .move:
                cue(s0.lowerBound + dx, snapped(s0.lowerBound + dx, to: [0, wall.lengthFt - width], pull: reach), along: true)
                let left = min(max(0, snapped(s0.lowerBound + dx, to: [0, wall.lengthFt - width], pull: reach)),
                               max(0, wall.lengthFt - width))
                n.alongFt = left + width / 2
                if start.kind != .door && start.kind != .showerDoor {
                    n.bottomFt = min(max(0, s16(start.bottomFt + dy)), max(0, wall.heightFt - start.heightFt))
                }
            case .left:
                let left = min(max(0, s16(s0.lowerBound + dx)), s0.upperBound - 1.0 / 6)
                n = moved(start, left: left, right: s0.upperBound)
            case .right:
                let right = max(min(wall.lengthFt, s16(s0.upperBound + dx)), s0.lowerBound + 1.0 / 6)
                n = moved(start, left: s0.lowerBound, right: right)
            case .top:
                let top = snapped(start.bottomFt + start.heightFt + dy, to: [wall.heightFt], pull: reach)
                cue(start.bottomFt + start.heightFt + dy, top, along: false)
                n.heightFt = min(max(start.bottomFt + 1.0 / 6, top), wall.heightFt) - start.bottomFt
                if start.kind == .showerDoor { n.heightFt = max(n.heightFt, 3) }
            case .bottom:
                let top = start.bottomFt + start.heightFt
                let bottom = min(max(0, s16(start.bottomFt + dy)), top - 1.0 / 6)
                n.bottomFt = bottom
                n.heightFt = top - bottom
            }
            onDoor(n)
        }
    }

    /// Under the wall: the row of distances, the length, the end names.
    private static let belowWall: CGFloat = 66
    /// Beside it: the column of heights and the wall's height.
    private static let heightColumn: CGFloat = 46

    /// The wall's dimensions: along the bottom, up the right-hand end, and
    /// the chosen thing's own size — placed by `PlanDimensionPlacer` clear of
    /// the labels, grips and end names already there.
    private func drawDimensions(_ ctx: GraphicsContext, size: CGSize, at: (Double, Double) -> CGPoint,
                                scale: Double, origin: CGPoint, width: CGFloat) {
        var spans: [WallDimensions.Span] = room.openings.filter { $0.wallID == wall.id }.map { o in
            let s = room.span(of: o)
            return .init(from: s.lowerBound, to: s.upperBound, bottom: o.bottomFt, top: o.bottomFt + o.heightFt)
        }
        spans += itemsHere.map { item in
            let r = itemRect(item)
            return .init(from: r.from, to: r.to, bottom: r.bottom, top: r.top)
        }
        let pieces = takeoff.pieces.filter { $0.wallID == wall.id && $0.face == face }
        var chosen: WallDimensions.Span?
        if let id = selectedItem.wrappedValue, let item = itemsHere.first(where: { $0.id == id }), !item.kind.isCorner {
            let r = itemRect(item)
            chosen = .init(from: r.from, to: r.to, bottom: r.bottom, top: r.top)
        } else if editOpenings, let id = selectedOpening.wrappedValue,
                  let o = room.openings.first(where: { $0.id == id && $0.wallID == wall.id }) {
            let s = room.span(of: o)
            chosen = .init(from: s.lowerBound, to: s.upperBound, bottom: o.bottomFt, top: o.bottomFt + o.heightFt)
        }
        let dims = WallDimensions.build(lengthFt: wall.lengthFt, heightFt: wall.heightFt, spans: spans,
                                        tileTops: pieces.map { $0.heightIn / 12 }, chosen: chosen)

        var placer = PlanDimensionPlacer()
        placer.page = CGRect(origin: .zero, size: size)
        func edges(_ r: CGRect) {
            let c = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                     CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            for i in 0..<4 {
                placer.claim(from: c[i], to: c[(i + 1) % 4])
                placer.edges.append((c[i], c[(i + 1) % 4]))
            }
        }
        func box(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) {
            placer.claimForLabelsOnly(CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        }
        func rectOf(_ s: WallDimensions.Span) -> CGRect {
            let a = at(s.from, s.top), b = at(s.to, s.bottom)
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        }
        edges(CGRect(x: origin.x, y: origin.y - wall.heightFt * scale, width: width, height: wall.heightFt * scale))
        // Doors, windows and items: their outlines, and the label or icon in their middle.
        for s in spans {
            let r = rectOf(s)
            edges(r)
            if r.width > 30, r.height > 14 { box(CGPoint(x: r.midX, y: r.midY), min(r.width, 52), min(r.height, 30)) }
        }
        // This area's tile: its size capsule.
        for p in pieces {
            let r = rect(p, at)
            if r.width > 40, r.height > 22 { box(CGPoint(x: r.midX, y: r.maxY - 12), 96, 18) }
        }
        // Grips on what's chosen.
        for g in gripSpots(at: at) { box(g, 30, 30) }
        // The end names and the hint.
        box(CGPoint(x: origin.x + width / 2, y: origin.y + Self.belowWall - 6), max(width, 170), 14)
        box(CGPoint(x: 130, y: 18), 260, 34)

        DimensionDrawing.draw(ctx, placer.layout(dims, at: { at($0.x, $0.y) },
                                                 measure: { DimensionDrawing.measure(ctx, $0) }))
    }

    /// Where the grips of whatever is chosen sit.
    private func gripSpots(at: (Double, Double) -> CGPoint) -> [CGPoint] {
        func spots(_ a: CGPoint, _ b: CGPoint, out: CGFloat) -> [CGPoint] {
            let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
            return [CGPoint(x: r.minX - out, y: r.midY), CGPoint(x: r.maxX + out, y: r.midY),
                    CGPoint(x: r.midX, y: r.minY - out), CGPoint(x: r.midX, y: r.maxY + out)]
        }
        var out: [CGPoint] = []
        if let id = selectedItem.wrappedValue, let item = itemsHere.first(where: { $0.id == id }) {
            let r = itemRect(item)
            out += spots(at(r.from, r.top), at(r.to, r.bottom), out: 9).dropLast()
        } else if let p = takeoff.pieces.first(where: { $0.id == selectedPiece && $0.wallID == wall.id && $0.face == face }) {
            out += spots(at(p.fromFt, p.heightIn / 12), at(p.toFt, 0), out: 0).dropLast()
        }
        if editOpenings, let id = selectedOpening.wrappedValue,
           let o = room.openings.first(where: { $0.id == id && $0.wallID == wall.id }) {
            let s = room.span(of: o)
            out += spots(at(s.lowerBound, o.bottomFt + o.heightFt), at(s.upperBound, o.bottomFt), out: 9)
        }
        for d in room.openings where d.wallID == wall.id && d.kind == .showerDoor {
            let s = room.span(of: d)
            let a = at(s.lowerBound, d.bottomFt + d.heightFt), b = at(s.upperBound, d.bottomFt)
            out += [CGPoint(x: a.x, y: a.y + (b.y - a.y) * 0.3), CGPoint(x: b.x, y: a.y + (b.y - a.y) * 0.3),
                    CGPoint(x: (a.x + b.x) / 2, y: a.y)]
        }
        return out
    }

    /// Entering a catch: a light tick and a green line where it caught.
    private func cue(_ raw: Double, _ result: Double, along: Bool) {
        let isCaught = abs(result - Steering.sixteenth(raw)) > 1e-9
        if isCaught, !caught {
            UISelectionFeedbackGenerator().selectionChanged()
            let id = UUID()
            flash = (along ? result : nil, along ? nil : result, id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if flash?.id == id { flash = nil } }
        }
        caught = isCaught
    }

    /// While something is held: the magnet and nudge arrows, a sixteenth a
    /// tap, catching nothing (owner's call, 2026-10-08).
    private func holdControls(_ hold: Hold) -> some View {
        let (sideways, upDown): (Bool, Bool) = {
            switch hold {
            case .piece(_, let part): return (part == .left || part == .right, part == .top)
            case .item(let id, let part):
                let corner = takeoff.items.first { $0.id == id }?.kind.isCorner ?? false
                switch part {
                case .move: return (!corner, true)
                case .left, .right: return (true, false)
                case .top, .bottom: return (false, true)
                }
            case .opening(let id, let part):
                let door = room.openings.first { $0.id == id }.map { $0.kind == .door || $0.kind == .showerDoor } ?? false
                switch part {
                case .move: return (true, !door)
                case .left, .right: return (true, false)
                case .top, .bottom: return (false, true)
                }
            }
        }()
        return HStack(spacing: 4) {
            Button {
                catchOff.toggle()
            } label: {
                Label(catchOff ? "Catch off" : "Catch on", systemImage: catchOff ? "scope" : "dot.scope")
                    .labelStyle(.titleAndIcon)
            }
            .tint(catchOff ? .orange : .green)
            if sideways {
                Button { nudge(hold, dx: -sixteenth, dy: 0) } label: { Image(systemName: "chevron.left").frame(width: 18, height: 22) }
                Button { nudge(hold, dx: sixteenth, dy: 0) } label: { Image(systemName: "chevron.right").frame(width: 18, height: 22) }
            }
            if upDown {
                Button { nudge(hold, dx: 0, dy: -sixteenth) } label: { Image(systemName: "chevron.down").frame(width: 18, height: 22) }
                Button { nudge(hold, dx: 0, dy: sixteenth) } label: { Image(systemName: "chevron.up").frame(width: 18, height: 22) }
            }
        }
        .font(.caption2.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// What's held moved a sixteenth, catching nothing.
    private func nudge(_ hold: Hold, dx: Double, dy: Double) {
        holdPiece = nil; holdItem = nil; holdOpening = nil
        steeredFt = CGSize(width: dx, height: dy)
        let wasCaught = caught
        steer(hold, reach: 0)
        caught = wasCaught
        steeredFt = .zero
        holdPiece = nil; holdItem = nil; holdOpening = nil
    }

    /// A handle that chooses a part to steer: lit when it's the one held.
    private func grip(_ h: Hold, vertical: Bool, tint: Color, at p: CGPoint) -> some View {
        let held = hold == h
        return Capsule()
            .fill(held ? tint : Color.white)
            .overlay(Capsule().stroke(tint, lineWidth: 2.5))
            .frame(width: vertical ? 9 : 28, height: vertical ? 28 : 9)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .position(p)
            .onTapGesture { hold = held ? nil : h }
    }

    @ViewBuilder
    private func showerDoor(_ d: ScannedRoom.Opening, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let s = room.span(of: d)
        let top = d.bottomFt + d.heightFt
        let r = CGRect(x: at(s.lowerBound, 0).x, y: at(0, top).y, width: (s.upperBound - s.lowerBound) * scale, height: d.heightFt * scale)
        let header = room.hasHeader(d)
        // The opening, with the curb along its bottom and the header over it.
        Rectangle().fill(Color(white: 0.05))
            .overlay(Rectangle().stroke(Self.stone, style: StrokeStyle(lineWidth: 1.5)))
            .overlay(alignment: .bottom) { Rectangle().fill(Self.stone).frame(height: 4) }
            .overlay(
                VStack(spacing: 1) {
                    Image(systemName: "door.left.hand.open").font(.caption)
                    if !header { Text("no header").font(.system(size: 9)) }
                }
                .foregroundStyle(Self.stone).fixedSize()
            )
            .overlay(Rectangle().stroke(Color.green, lineWidth: hold == .opening(d.id, .move) ? 3 : 0))
            .frame(width: max(r.width, 1), height: max(r.height, 1))
            .position(x: r.midX, y: r.midY)
            .onTapGesture { hold = hold == .opening(d.id, .move) ? nil : .opening(d.id, .move) }
        if header {
            Rectangle().fill(Self.stone).frame(width: max(r.width, 1), height: 4)
                .position(x: r.midX, y: r.minY - 2)
                .allowsHitTesting(false)
        }
        // Its sides and top: tap one, then drag anywhere.
        grip(.opening(d.id, .left), vertical: true, tint: Self.stone, at: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
        grip(.opening(d.id, .right), vertical: true, tint: Self.stone, at: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
        grip(.opening(d.id, .top), vertical: false, tint: Self.stone, at: CGPoint(x: r.midX, y: r.minY))
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
                VStack(spacing: 0) {
                    // Its size and height are dimensioned (`WallDimensions`).
                    Text(item.kind.name).font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(color).fixedSize()
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
        .onTapGesture {
            // First tap chooses it; tapping it again takes hold of the whole thing.
            if selectedItem.wrappedValue == item.id { hold = hold == .item(item.id, .move) ? nil : .item(item.id, .move) }
            else { selectedItem.wrappedValue = item.id; hold = nil }
        }
    }

    /// Drag handles on the chosen item: a niche or window moves whole and
    /// takes its sides and top; a bench its ends and top; a corner piece moves up and down.
    @ViewBuilder
    private func itemHandles(_ i: Int, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let item = takeoff.items[i]
        let r = itemRect(item)
        let a = at(r.from, r.top), b = at(r.to, r.bottom)
        let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        if hold == .item(item.id, .move) {
            Rectangle().stroke(Color.green, lineWidth: 3)
                .frame(width: max(rect.width, 4), height: max(rect.height, 4))
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
        if !item.kind.isCorner {
            // Just outside the edges, so a small niche stays visible.
            grip(.item(item.id, .left), vertical: true, tint: .mint, at: CGPoint(x: rect.minX - 9, y: rect.midY))
            grip(.item(item.id, .right), vertical: true, tint: .mint, at: CGPoint(x: rect.maxX + 9, y: rect.midY))
            grip(.item(item.id, .top), vertical: false, tint: .mint, at: CGPoint(x: rect.midX, y: rect.minY - 9))
        }
    }

    /// A door, window or opening on the wall: tap to take it off the tile,
    /// or (editing the room) to choose it.
    private func openingView(_ o: ScannedRoom.Opening, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let s = room.span(of: o)
        let left: CGFloat = at(s.lowerBound, 0).x
        let top: CGFloat = at(0, o.bottomFt + o.heightFt).y
        let w: CGFloat = max((s.upperBound - s.lowerBound) * scale, 2)
        let h: CGFloat = max(o.heightFt * scale, 2)
        let off: Bool = takeoff.subtracted.contains(o.id) && !editOpenings
        let chosen: Bool = editOpenings && selectedOpening.wrappedValue == o.id
        let tint: Color = off ? .red : .cyan
        let label: String = off ? "off" : "tap"
        let symbol: String = o.kind == .window ? "window.horizontal" : "door.left.hand.closed"
        return RoundedRectangle(cornerRadius: 2)
            .fill(off ? Color(white: 0.08) : Color.cyan.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(tint.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: off ? [] : [4, 3])))
            .overlay(VStack(spacing: 0) {
                Image(systemName: symbol).font(.caption)
                // Its size and height are dimensioned (`WallDimensions`).
                if !editOpenings { Text(label).font(.system(size: 9)).fixedSize() }
            }.foregroundStyle(tint))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: chosen ? 2.5 : 0))
            .frame(width: w, height: h)
            .position(x: left + w / 2, y: top + h / 2)
            .onTapGesture {
                if editOpenings {
                    if selectedOpening.wrappedValue == o.id { hold = hold == .opening(o.id, .move) ? nil : .opening(o.id, .move) }
                    else { selectedOpening.wrappedValue = o.id; hold = nil }
                } else if off {
                    takeoff.subtracted.removeAll { $0 == o.id }
                } else {
                    takeoff.subtracted.append(o.id)
                }
            }
    }

    @ViewBuilder
    private func openingHandles(_ o: ScannedRoom.Opening, scale: Double, at: @escaping (Double, Double) -> CGPoint) -> some View {
        let s = room.span(of: o)
        let a = at(s.lowerBound, o.bottomFt + o.heightFt), b = at(s.upperBound, o.bottomFt)
        let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        if hold == .opening(o.id, .move) {
            Rectangle().stroke(Color.green, lineWidth: 3)
                .frame(width: max(r.width, 4), height: max(r.height, 4))
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
        }
        grip(.opening(o.id, .left), vertical: true, tint: .cyan, at: CGPoint(x: r.minX - 9, y: r.midY))
        grip(.opening(o.id, .right), vertical: true, tint: .cyan, at: CGPoint(x: r.maxX + 9, y: r.midY))
        grip(.opening(o.id, .top), vertical: false, tint: .cyan, at: CGPoint(x: r.midX, y: r.minY - 9))
        if o.kind != .door {
            grip(.opening(o.id, .bottom), vertical: false, tint: .cyan, at: CGPoint(x: r.midX, y: r.maxY + 9))
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
        grip(.piece(p.id, .left), vertical: true, tint: .blue, at: CGPoint(x: r.minX, y: r.midY))
        grip(.piece(p.id, .right), vertical: true, tint: .blue, at: CGPoint(x: r.maxX, y: r.midY))
        grip(.piece(p.id, .top), vertical: false, tint: .blue, at: CGPoint(x: r.midX, y: r.minY))
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

/// A length, typed: shown in inches, typed either way.
struct InchField: View {
    let title: String
    /// The length, in inches, to the sixteenth: shown in inches, typed in
    /// inches or feet and inches.
    @Binding var inches: Double
    /// Empty, not "0", until something's typed (a tape measurement not taken yet).
    var blankWhenZero = false
    /// Only set when typing ends (Set, or tapping away): for a value that
    /// moves walls, where "9" on the way to "96" would wreck the room.
    var applyWhenDone = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 3) {
                TextField(blankWhenZero ? "" : "0\"", text: $text)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focused)
                    .font(.body.monospacedDigit())
                    .minimumScaleFactor(0.7)
                if applyWhenDone && focused {
                    Button("Set") { focused = false }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .onAppear { text = shown(inches) }
        .onChange(of: inches) { _, v in if !focused { text = shown(v) } }
        .onChange(of: text) { _, t in
            if focused, !applyWhenDone {
                if let v = Lengths.parse(t), abs(v - inches) > 0.0001 { inches = v }
                else if t.isEmpty, blankWhenZero { inches = 0 }
            }
        }
        .onChange(of: focused) { _, f in
            if !f {
                if applyWhenDone, let v = Lengths.parse(text), abs(v - inches) > 0.0001 { inches = v }
                text = shown(inches)
            }
        }
        .onSubmit { focused = false }
    }

    private func shown(_ v: Double) -> String {
        blankWhenZero && v == 0 ? "" : Lengths.typedInches(v)
    }

    /// A plain number of inches, for text that says ″ after it.
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
