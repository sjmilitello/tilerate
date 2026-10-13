import SwiftUI

/// A room measured by hand, drawn from its sides as the same kind of model
/// a scan gives (owner, 2026-10-12): pick a shape, type its sides and the
/// ceiling, then tap walls and floors, drag walls, add walls, doors and the
/// shower with the same tools.
enum RoomSketch {
    enum Shape: String, CaseIterable, Identifiable {
        case rectangle = "Rectangle", lShape = "L-shape"
        var id: String { rawValue }
    }

    /// The sides, in inches. Rectangle: width (A, C) and depth (B, D).
    /// L-shape: overall width and depth, and the corner cut out of it
    /// (bottom right as drawn): its width and depth.
    struct Sides: Equatable {
        var widthIn: Double = 96
        var depthIn: Double = 120
        var cutWidthIn: Double = 36
        var cutDepthIn: Double = 48
        var ceilingIn: Double = 96
    }

    /// Whether the sides make a room.
    static func valid(_ shape: Shape, _ s: Sides) -> Bool {
        guard s.widthIn >= 12, s.depthIn >= 12, s.ceilingIn >= 24 else { return false }
        if shape == .lShape {
            return s.cutWidthIn >= 6 && s.cutDepthIn >= 6
                && s.cutWidthIn <= s.widthIn - 6 && s.cutDepthIn <= s.depthIn - 6
        }
        return true
    }

    /// The corners in order round the room (feet; y down the plan), each
    /// wall running from one to the next with the room on its right.
    static func corners(_ shape: Shape, _ s: Sides) -> [ScannedRoom.Point] {
        let w = s.widthIn / 12, d = s.depthIn / 12
        switch shape {
        case .rectangle:
            return [.init(x: 0, y: 0), .init(x: w, y: 0), .init(x: w, y: d), .init(x: 0, y: d)]
        case .lShape:
            let cw = s.cutWidthIn / 12, cd = s.cutDepthIn / 12
            return [.init(x: 0, y: 0), .init(x: w, y: 0), .init(x: w, y: d - cd),
                    .init(x: w - cw, y: d - cd), .init(x: w - cw, y: d), .init(x: 0, y: d)]
        }
    }

    static func room(_ shape: Shape, _ s: Sides) -> ScannedRoom {
        var r = ScannedRoom()
        r.sketched = true
        let k = corners(shape, s)
        let h = s.ceilingIn / 12
        r.walls = k.indices.map { i in
            let a = k[i], b = k[(i + 1) % k.count]
            return ScannedRoom.Wall(lengthFt: hypot(b.x - a.x, b.y - a.y), heightFt: h, start: a, end: b)
        }
        r.floorOutline = k
        r.floorSqft = FloorGeometry.area(k)
        r.reletter()
        return r
    }
}

extension EstimateRoom {
    /// Each new area started on the room's model where the model suggests
    /// it (owner's call, 2026-10-12: "place what it can"): the floor on the
    /// room's floor, a shower filling a cove of three walls, a tub surround
    /// round a found tub, a backsplash behind a cabinet. Anything that can't
    /// be placed starts empty, to be set on the model.
    mutating func placeAreas(_ ids: [UUID], prices: StonePrices) {
        guard let scan else { return }
        var used: Set<String> = []
        for id in ids {
            guard let i = sections.firstIndex(where: { $0.id == id }), let area = sections[i].area else { continue }
            var s = sections[i]
            let others = sections.filter { $0.id != id }
            let found = scan.suggestions().first { sug in
                sug.area == area && !used.contains(Self.key(sug.takeoff))
            }
            var t: AreaTakeoff
            if let found {
                used.insert(Self.key(found.takeoff))
                t = found.takeoff
            } else {
                t = AreaTakeoff.starting(for: area, room: scan, otherAreas: others)
            }
            t.apply(scan, to: &s, prices: prices)
            sections[i] = s
        }
        refreshFloorCutouts(prices: prices)
    }

    private static func key(_ t: AreaTakeoff) -> String {
        "\(t.floorRect.map { "\($0.origin.x),\($0.origin.y)" } ?? "")|\(t.pieces.map { "\($0.wallID)" }.joined())|\(t.floor)"
    }
}

/// Adding a room: its name and every area in it, ticked (with a count),
/// then how to measure it (owner, 2026-10-12).
struct NDNewRoomSheet: View {
    enum Method { case scan, sketch, type }
    let defaultName: String
    let onCreate: (String, [Area], Method) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var counts: [Area: Int] = [:]

    private var chosen: [Area] {
        Area.allCases.flatMap { a in Array(repeating: a, count: counts[a] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        NDLabel("Room name")
                        TextField(defaultName, text: $name)
                            .font(.system(size: 17, weight: .semibold))
                            .padding(12)
                            .background(ND.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        NDLabel("What are we tiling? Tick all that apply")
                        ForEach(Area.allCases) { a in row(a) }
                    }
                    VStack(spacing: 10) {
                        NDLabel("How to measure").frame(maxWidth: .infinity, alignment: .leading)
                        if RoomScanner.isAvailable {
                            method("Scan the room", "viewfinder", .scan, primary: true)
                        }
                        #if DEBUG
                        if !RoomScanner.isAvailable {
                            method("Use a sample room (no LiDAR here)", "viewfinder", .scan, primary: true)
                        }
                        #endif
                        method("Sketch it: type its sides", "pencil.and.ruler", .sketch, primary: !RoomScanner.isAvailable)
                        Button { create(.type) } label: {
                            Text("Just type square feet").font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(ND.link)
                        .padding(.top, 2)
                    }
                    .disabled(chosen.isEmpty)
                    .opacity(chosen.isEmpty ? 0.45 : 1)
                    if chosen.isEmpty {
                        Text("Tick at least one area.").font(.system(size: 13)).foregroundStyle(ND.muted)
                    }
                }
                .padding(20)
            }
            .background(ND.ground.ignoresSafeArea())
            .foregroundStyle(ND.text)
            .navigationTitle("Add room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ a: Area) -> some View {
        let n = counts[a] ?? 0
        return HStack(spacing: 12) {
            Button {
                counts[a] = n == 0 ? 1 : 0
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: n > 0 ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22)).foregroundStyle(n > 0 ? ND.link : ND.muted)
                    NDAreaIcon(area: a, size: 22).frame(width: 30)
                    Text(a.rawValue).font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if n > 0 {
                Stepper("\(n)", value: Binding(get: { n }, set: { counts[a] = max(0, min(9, $0)) }), in: 0...9)
                    .labelsHidden()
                Text("\(n)").font(.system(size: 16, weight: .semibold).monospacedDigit()).frame(width: 18)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(n > 0 ? ND.selectedBg : ND.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(n > 0 ? ND.link : ND.border, lineWidth: n > 0 ? 1.5 : 1))
    }

    private func method(_ title: String, _ icon: String, _ m: Method, primary: Bool) -> some View {
        Button { create(m) } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(primary ? Color.white : ND.text)
                .background(primary ? ND.brand : ND.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func create(_ m: Method) {
        guard !chosen.isEmpty else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        onCreate(n.isEmpty ? defaultName : n, chosen, m)
        dismiss()
    }
}

/// Sketching a room by hand: its shape, sides and ceiling, drawn as you type.
struct NDSketchRoomSheet: View {
    let roomName: String
    let onMake: (ScannedRoom) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shape: RoomSketch.Shape = .rectangle
    @State private var sides = RoomSketch.Sides()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Shape", selection: $shape) {
                        ForEach(RoomSketch.Shape.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    preview.frame(height: 220)
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            InchField(title: shape == .rectangle ? "Width (A, C)" : "Overall width (A)", inches: $sides.widthIn)
                            InchField(title: shape == .rectangle ? "Depth (B, D)" : "Overall depth", inches: $sides.depthIn)
                        }
                        if shape == .lShape {
                            HStack(spacing: 12) {
                                InchField(title: "Corner cut out: width", inches: $sides.cutWidthIn)
                                InchField(title: "Corner cut out: depth", inches: $sides.cutDepthIn)
                            }
                        }
                        InchField(title: "Ceiling height", inches: $sides.ceilingIn)
                    }
                    Text("Typed as a tape is read (120, 10' 0\", 96 1/2). Doors, a shower, a tub or anything else are added on the model, where walls can also be dragged, split and added.")
                        .font(.footnote).foregroundStyle(ND.muted)
                    Button {
                        onMake(RoomSketch.room(shape, sides))
                        dismiss()
                    } label: {
                        Text("Make the model").font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(ND.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!RoomSketch.valid(shape, sides))
                    .opacity(RoomSketch.valid(shape, sides) ? 1 : 0.45)
                }
                .padding(20)
            }
            .background(ND.ground.ignoresSafeArea())
            .foregroundStyle(ND.text)
            .navigationTitle("Sketch \(roomName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    /// The room as typed, to scale, its walls lettered with their lengths.
    private var preview: some View {
        Canvas { ctx, size in
            guard RoomSketch.valid(shape, sides) else { return }
            let room = RoomSketch.room(shape, sides)
            let k = room.floorOutline
            let maxX = k.map(\.x).max() ?? 1, maxY = k.map(\.y).max() ?? 1
            let scale = min((size.width - 90) / maxX, (size.height - 50) / maxY)
            let ox = (size.width - maxX * scale) / 2, oy = (size.height - maxY * scale) / 2
            func p(_ q: ScannedRoom.Point) -> CGPoint { CGPoint(x: ox + q.x * scale, y: oy + q.y * scale) }
            var path = Path()
            path.addLines(k.map(p))
            path.closeSubpath()
            ctx.fill(path, with: .color(ND.surface))
            ctx.stroke(path, with: .color(ND.secondary), lineWidth: 4)
            for w in room.walls {
                let a = p(w.start), b = p(w.end)
                let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                // Just outside its own wall (the room is on each wall's right).
                let l = max(hypot(b.x - a.x, b.y - a.y), 1)
                let n = CGPoint(x: (b.y - a.y) / l, y: -(b.x - a.x) / l)
                let gap = abs(n.x) * 38 + abs(n.y) * 13
                let out = CGPoint(x: m.x + n.x * gap, y: m.y + n.y * gap)
                ctx.draw(Text("\(w.label) \(inchText(w.lengthFt))").font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ND.link), at: out)
            }
        }
        .background(ND.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
