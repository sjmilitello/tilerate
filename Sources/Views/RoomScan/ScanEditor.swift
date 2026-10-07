import SwiftUI

// Measuring an area from a room scan: the floor plan on top (pinch to zoom,
// drag to pan, double-tap to fit, tap a wall to tile it), the chosen wall
// face-on underneath (drag a piece's sides to where the tile starts and stops,
// drag its top to its height, tap a door or window to take it off), then the
// floor and ceiling. Everything snaps to the inch and to edges nearby.

/// Another area in the same room, shown faintly so walls aren't counted twice.
struct OtherAreaPieces {
    let name: String
    let pieces: [AreaTakeoff.Piece]
    var floor: AreaTakeoff.FloorRect? = nil
}

struct ScanEditor: View {
    let room: ScannedRoom
    let area: Area?
    let title: String
    let others: [OtherAreaPieces]
    let onUse: (AreaTakeoff) -> Void
    let onRescan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var takeoff: AreaTakeoff
    @State private var selectedWall: UUID? = nil
    @State private var selectedPiece: UUID? = nil

    init(room: ScannedRoom, area: Area?, title: String, takeoff: AreaTakeoff, others: [OtherAreaPieces],
         onUse: @escaping (AreaTakeoff) -> Void, onRescan: @escaping () -> Void) {
        self.room = room
        self.area = area
        self.title = title
        self.others = others
        self.onUse = onUse
        self.onRescan = onRescan
        _takeoff = State(initialValue: takeoff)
        _selectedWall = State(initialValue: takeoff.pieces.first?.wallID)
        _selectedPiece = State(initialValue: takeoff.pieces.first?.id)
    }

    private var usesWalls: Bool { area != .floor }
    private var otherPieces: [AreaTakeoff.Piece] { others.flatMap(\.pieces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlanCanvas(room: room, mine: takeoff.pieces, others: others, selectedWall: selectedWall,
                           floorRect: takeoff.floor == .drawn ? $takeoff.floorRect : nil) { wallID in
                    tapWall(wallID)
                }
                .frame(height: 250)
                .background(Color(white: 0.09))
                .overlay(alignment: .bottomLeading) {
                    Text(usesWalls ? "Tap a wall to tile it · pinch to zoom · double-tap to fit"
                                   : "Pinch to zoom · double-tap to fit")
                        .font(.caption2).foregroundStyle(.secondary).padding(8)
                }

                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if usesWalls { wallPanel.id("wall") }
                            if area == .floor || area == .shower || area == .tub { floorPanel }
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
        guard usesWalls, let wall = room.wall(id) else { return }
        selectedWall = id
        if let mine = takeoff.pieces.first(where: { $0.wallID == id }) {
            selectedPiece = mine.id
        } else if let new = takeoff.addPiece(on: wall, area: area, others: otherPieces) {
            selectedPiece = new.id
            fillShowerFloorIfBlank()
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
        if let wallID = selectedWall, let wall = room.wall(wallID) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Wall \(wall.label)").font(.ndTitle(20))
                    Text("\(feetAndInches(wall.lengthFt)) long · \(feetAndInches(wall.heightFt)) high")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                WallElevation(room: room, wall: wall, takeoff: $takeoff, selectedPiece: $selectedPiece,
                              others: others, snaps: room.snapPoints(on: wall, others: otherPieces))
                    .frame(height: 210)

                if let pieceIndex = takeoff.pieces.firstIndex(where: { $0.id == selectedPiece && $0.wallID == wallID }) {
                    pieceControls(pieceIndex, wall: wall)
                } else {
                    Text("Tap the blue tile on the wall to adjust it, or add a piece.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        if let p = takeoff.addPiece(on: wall, area: area, others: otherPieces) { selectedPiece = p.id }
                    } label: { Label("Add piece", systemImage: "plus") }
                    if let id = selectedPiece, let p = takeoff.pieces.first(where: { $0.id == id }), p.toFt - p.fromFt > 1 {
                        Button { split(id) } label: { Label("Split", systemImage: "scissors") }
                    }
                    if let id = selectedPiece, takeoff.pieces.contains(where: { $0.id == id }) {
                        Button(role: .destructive) {
                            takeoff.pieces.removeAll { $0.id == id }
                            selectedPiece = takeoff.pieces.first { $0.wallID == wallID }?.id
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)

                openingsList(on: wall)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose the walls").font(.ndTitle(20))
                Text("Tap each wall on the plan that gets tile for this \(area?.rawValue.lowercased() ?? "area"). Then drag the tile on the wall to where it starts and stops, and up to its height.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
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
        let near = room.walls.filter { $0.id != wall.id }.min { a, b in
            min(dist(a.start, end), dist(a.end, end)) < min(dist(b.start, end), dist(b.end, end))
        }
        if let near, min(dist(near.start, end), dist(near.end, end)) < 1.5 { return "wall \(near.label)" }
        return atStart ? "left" : "right"
    }

    private func dist(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
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
                        Text("Drag the green handles on the plan: the arrows on its sides to size it, the middle one to move it. Sides snap to walls.")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            InchField(title: "Width", inches: Binding(get: { r.widthFt * 12 }, set: { takeoff.floorRect?.widthFt = max(1, $0) / 12 }))
                            InchField(title: "Depth", inches: Binding(get: { r.depthFt * 12 }, set: { takeoff.floorRect?.depthFt = max(1, $0) / 12 }))
                        }
                        Button {
                            placeShowerFloor()
                        } label: {
                            Label("Fit to the shower walls", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                        .disabled(takeoff.pieces.isEmpty)
                    } else {
                        Text("Choose the shower's walls on the plan and the floor is placed in their corner, ready to drag.")
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
        return VStack(spacing: 10) {
            Text(parts.joined(separator: " · ") + " sq ft")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Button {
                onUse(takeoff)
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
    var onTapWall: (UUID) -> Void = { _ in }

    @State private var zoom: CGFloat = 1
    @State private var dragStart: AreaTakeoff.FloorRect? = nil
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    private struct Frame {
        let size: CGSize
        let scale: CGFloat
        let cx: Double, cy: Double
        let pan: CGSize
        func at(_ p: ScannedRoom.Point) -> CGPoint {
            CGPoint(x: size.width / 2 + (p.x - cx) * scale + pan.width,
                    y: size.height / 2 + (p.y - cy) * scale + pan.height)
        }
    }

    private func frame(_ size: CGSize) -> Frame {
        let pts = room.floorOutline + room.walls.flatMap { [$0.start, $0.end] }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let fit = min((size.width - 60) / max(maxX - minX, 1), (size.height - 60) / max(maxY - minY, 1))
        return Frame(size: size, scale: fit * zoom, cx: (minX + maxX) / 2, cy: (minY + maxY) / 2, pan: pan)
    }

    var body: some View {
        GeometryReader { geo in
            let f = frame(geo.size)
            if interactive {
                Canvas { ctx, _ in draw(ctx, f) }
                    .contentShape(Rectangle())
                    .gesture(zoomAndPan(geo.size))
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.25)) { zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero }
                    }
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
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

    /// Handles on the floor rectangle: its far side along each wall (width,
    /// depth) and its middle (move). Sizes snap to the inch, and a side
    /// snaps to a wall within 3″.
    @ViewBuilder
    private func floorHandles(_ binding: Binding<AreaTakeoff.FloorRect?>, _ f: Frame) -> some View {
        if let r = binding.wrappedValue {
            let c = r.corners
            ZStack {
                FloorHandle(symbol: "arrow.left.and.right")
                    .position(midpoint(c[1], c[2], f))
                    .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let start = dragStart ?? r
                        if dragStart == nil { dragStart = r }
                        binding.wrappedValue?.widthFt = snapSide(start.widthFt + along(v.translation, start.u, f), start, alongU: true)
                    }.onEnded { _ in dragStart = nil })
                FloorHandle(symbol: "arrow.up.and.down")
                    .position(midpoint(c[2], c[3], f))
                    .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let start = dragStart ?? r
                        if dragStart == nil { dragStart = r }
                        binding.wrappedValue?.depthFt = snapSide(start.depthFt + along(v.translation, start.v, f), start, alongU: false)
                    }.onEnded { _ in dragStart = nil })
                FloorHandle(symbol: "arrow.up.and.down.and.arrow.left.and.right")
                    .position(midpoint(c[0], c[2], f))
                    .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let start = dragStart ?? r
                        if dragStart == nil { dragStart = r }
                        // Move in whole inches along the rectangle's own sides.
                        let a = (along(v.translation, start.u, f) * 12).rounded() / 12
                        let b = (along(v.translation, start.v, f) * 12).rounded() / 12
                        binding.wrappedValue?.origin = .init(x: start.origin.x + start.u.x * a + start.v.x * b,
                                                             y: start.origin.y + start.u.y * a + start.v.y * b)
                    }.onEnded { _ in dragStart = nil })
            }
        }
    }

    private func midpoint(_ a: ScannedRoom.Point, _ b: ScannedRoom.Point, _ f: Frame) -> CGPoint {
        let p = f.at(a), q = f.at(b)
        return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
    }

    /// How far a drag on screen goes along a direction on the plan, in feet.
    private func along(_ t: CGSize, _ dir: ScannedRoom.Point, _ f: Frame) -> Double {
        Double(t.width / f.scale) * dir.x + Double(t.height / f.scale) * dir.y
    }

    /// A width or depth rounded to the inch, or to where that side would
    /// meet a wall when within 3″.
    private func snapSide(_ length: Double, _ r: AreaTakeoff.FloorRect, alongU: Bool) -> Double {
        let dir = alongU ? r.u : r.v
        var best = max(1.0 / 12, (length * 12).rounded() / 12)
        var bestGap = 0.25
        for w in room.walls {
            // Where the ray from the origin along `dir` crosses this wall.
            let ex = w.end.x - w.start.x, ey = w.end.y - w.start.y
            let den = dir.x * ey - dir.y * ex
            guard abs(den) > 1e-6 else { continue }
            let t = ((w.start.x - r.origin.x) * ey - (w.start.y - r.origin.y) * ex) / den
            let s = ((w.start.x - r.origin.x) * dir.y - (w.start.y - r.origin.y) * dir.x) / den
            guard t > 0.5, s >= -0.05, s <= 1.05, abs(t - length) < bestGap else { continue }
            best = t
            bestGap = abs(t - length)
        }
        return best
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
        // Walls.
        for w in room.walls {
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
                if let s = segment(p.wallID, from: p.fromFt, to: p.toFt, f) {
                    ctx.stroke(s, with: .color(Color.orange.opacity(0.55)), style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                }
            }
        }
        for p in mine {
            if let s = segment(p.wallID, from: p.fromFt, to: p.toFt, f) {
                ctx.stroke(s, with: .color(Color.blue), style: StrokeStyle(lineWidth: 7, lineCap: .butt))
            }
        }
        // The shower floor.
        if let r = floorRect?.wrappedValue ?? floorRectShown {
            var path = Path()
            path.addLines(r.corners.map(f.at))
            path.closeSubpath()
            ctx.fill(path, with: .color(Color.green.opacity(0.22)))
            ctx.stroke(path, with: .color(Color.green), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            let c = r.corners
            let center = f.at(ScannedRoom.Point(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2))
            if interactive {
                ctx.draw(Text("\(feetAndInches(r.widthFt)) × \(feetAndInches(r.depthFt))")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.green),
                         at: CGPoint(x: center.x, y: center.y + 24))
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
            let label = Text(interactive ? "\(w.label)  \(feetAndInches(w.lengthFt))" : w.label)
                .font(.system(size: interactive ? 11 : 10, weight: .semibold))
                .foregroundColor(mine.contains { $0.wallID == w.id } ? .blue : Color(white: 0.75))
            ctx.draw(label, at: f.at(toward))
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
    @Binding var takeoff: AreaTakeoff
    @Binding var selectedPiece: UUID?
    let others: [OtherAreaPieces]
    let snaps: [Double]

    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 2 * inset, h = geo.size.height - 2 * inset - 14
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
                    ForEach(others[i].pieces.filter { $0.wallID == wall.id }) { p in
                        let r = rect(p, at)
                        Rectangle().fill(Color.orange.opacity(0.22))
                            .overlay(Rectangle().stroke(Color.orange.opacity(0.6), lineWidth: 1))
                            .overlay(Text(others[i].name).font(.caption2).foregroundStyle(.orange).padding(3), alignment: .topLeading)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }

                // This area's tile.
                ForEach(takeoff.pieces.filter { $0.wallID == wall.id }) { p in
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
                        .onTapGesture { selectedPiece = p.id }
                }

                // Doors and windows.
                ForEach(room.openings.filter { $0.wallID == wall.id }) { o in
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

                // Handles on the chosen piece.
                if let i = takeoff.pieces.firstIndex(where: { $0.id == selectedPiece && $0.wallID == wall.id }) {
                    handles(i, scale: scale, at: at)
                }

                // The floor line, and the wall's length.
                Text(feetAndInches(wall.lengthFt))
                    .font(.caption2).foregroundStyle(.secondary)
                    .position(x: origin.x + width / 2, y: origin.y + 10)
            }
            .coordinateSpace(name: "wall")
        }
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 12))
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
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.body.monospacedDigit())
                Text("in").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            Text(feetAndInches(inches / 12)).font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { text = Self.format(inches) }
        .onChange(of: inches) { _, v in if !focused { text = Self.format(v) } }
        .onChange(of: text) { _, t in
            if focused, let v = Double(t.replacingOccurrences(of: ",", with: ".")), abs(v - inches) > 0.001 { inches = v }
        }
        .onChange(of: focused) { _, f in if !f { text = Self.format(inches) } }
    }

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

/// A round grab handle on the plan, big enough for a thumb.
private struct FloorHandle: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.green))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
