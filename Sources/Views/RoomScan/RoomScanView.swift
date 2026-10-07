import RoomPlan
import SwiftUI
import simd

// Measuring a room with the iPhone's LiDAR (Apple's RoomPlan): scan, then
// choose the walls being tiled, a tile height for each, and which doors,
// windows and openings come off. Only on iPhones with LiDAR.

enum RoomScanner {
    static var isAvailable: Bool { RoomCaptureSession.isSupported }
}

// MARK: - From RoomPlan's result to ScannedRoom

extension ScannedRoom {
    private static let feet = 3.28084

    init(captured room: CapturedRoom) {
        self.init()
        let f = Self.feet

        func center(_ t: simd_float4x4) -> SIMD3<Float> { SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z) }

        // Walls, lettered clockwise round the middle of the room.
        let mid = room.walls.isEmpty ? SIMD3<Float>(0, 0, 0)
            : room.walls.map { center($0.transform) }.reduce(SIMD3<Float>(0, 0, 0), +) / Float(room.walls.count)
        let ordered = room.walls.sorted {
            let a = center($0.transform) - mid, b = center($1.transform) - mid
            return atan2(Double(a.z), Double(a.x)) < atan2(Double(b.z), Double(b.x))
        }
        var wallIDs: [UUID: UUID] = [:]
        var wallBottoms: [UUID: Float] = [:]
        for w in ordered {
            let c = center(w.transform)
            let axis = simd_normalize(SIMD2(w.transform.columns.0.x, w.transform.columns.0.z))
            let half = axis * w.dimensions.x / 2
            var wall = Wall()
            wall.lengthFt = Double(w.dimensions.x) * f
            wall.heightFt = Double(w.dimensions.y) * f
            wall.start = Point(x: Double(c.x - half.x) * f, y: Double(c.z - half.y) * f)
            wall.end = Point(x: Double(c.x + half.x) * f, y: Double(c.z + half.y) * f)
            walls.append(wall)
            wallIDs[w.identifier] = wall.id
            wallBottoms[wall.id] = c.y - w.dimensions.y / 2
        }
        // One straight wall the scanner split in two becomes one again.
        let (merged, into) = Self.mergingStraightRuns(walls)
        walls = merged
        for (k, v) in wallIDs { wallIDs[k] = into[v] ?? v }
        for (k, v) in wallBottoms where into[k] != nil {
            let id = into[k]!
            wallBottoms[id] = min(wallBottoms[id] ?? v, v)
        }
        Self.letter(&walls)
        let floorLevel = wallBottoms.values.min() ?? 0

        // Doors, windows and openings, each in its wall when the scan says.
        func add(_ surfaces: [CapturedRoom.Surface], _ kind: OpeningKind) {
            for s in surfaces {
                var o = Opening()
                o.kind = kind
                o.wallID = s.parentIdentifier.flatMap { wallIDs[$0] } ?? nearestWall(to: center(s.transform))
                o.widthFt = Double(s.dimensions.x) * f
                o.heightFt = Double(s.dimensions.y) * f
                let bottom = center(s.transform).y - s.dimensions.y / 2 - (o.wallID.flatMap { wallBottoms[$0] } ?? floorLevel)
                o.bottomFt = max(0, Double(bottom) * f)
                if let w = o.wallID.flatMap({ id in walls.first { $0.id == id } }) {
                    let c = center(s.transform)
                    o.alongFt = along(Point(x: Double(c.x) * f, y: Double(c.z) * f), on: w)
                }
                openings.append(o)
            }
        }
        func nearestWall(to p: SIMD3<Float>) -> UUID? {
            let q = SIMD2(Double(p.x) * f, Double(p.z) * f)
            return walls.min { distance(q, $0) < distance(q, $1) }?.id
        }
        add(room.doors, .door)
        add(room.windows, .window)
        add(room.openings, .opening)

        // The floor: its outline from the scan, or else the walls' corners.
        if let floor = room.floors.first, !floor.polygonCorners.isEmpty {
            floorOutline = floor.polygonCorners.map { corner in
                let world = floor.transform * SIMD4(corner.x, corner.y, corner.z, 1)
                return Point(x: Double(world.x) * f, y: Double(world.z) * f)
            }
        } else {
            floorOutline = Self.outline(of: walls.flatMap { [$0.start, $0.end] })
        }
        floorSqft = Self.area(floorOutline)

        if let tub = room.objects.first(where: { $0.category == .bathtub }) {
            tubLengthFt = Double(max(tub.dimensions.x, tub.dimensions.z)) * f
            let c = center(tub.transform)
            let ax = SIMD2(tub.transform.columns.0.x, tub.transform.columns.0.z) * tub.dimensions.x / 2
            let az = SIMD2(tub.transform.columns.2.x, tub.transform.columns.2.z) * tub.dimensions.z / 2
            let mid = SIMD2(c.x, c.z)
            tubOutline = [mid - ax - az, mid + ax - az, mid + ax + az, mid - ax + az].map {
                Point(x: Double($0.x) * f, y: Double($0.y) * f)
            }
        }
    }

    /// Walls in line with each other and meeting end to end, merged into
    /// one: the scanner sometimes splits a wall (at a vanity, a column). The
    /// second value maps each merged-away wall to the wall it joined.
    static func mergingStraightRuns(_ input: [Wall]) -> ([Wall], [UUID: UUID]) {
        var walls = input
        var into: [UUID: UUID] = [:]
        func dir(_ w: Wall) -> SIMD2<Double> {
            let d = SIMD2(w.end.x - w.start.x, w.end.y - w.start.y)
            return d / max(simd_length(d), 1e-9)
        }
        func gap(_ a: Point, _ b: Point) -> Double { simd_length(SIMD2(a.x - b.x, a.y - b.y)) }
        var changed = true
        while changed {
            changed = false
            outer: for i in walls.indices {
                for j in walls.indices where j > i {
                    let a = walls[i], b = walls[j]
                    guard abs(simd_dot(dir(a), dir(b))) > 0.996 else { continue }       // within ~5°
                    let ends = [a.start, a.end, b.start, b.end]
                    let touching = [gap(a.end, b.start), gap(a.end, b.end), gap(a.start, b.start), gap(a.start, b.end)].min()! < 0.4
                    // In line, not just parallel: b's ends sit on a's line.
                    let n = SIMD2(-dir(a).y, dir(a).x)
                    let off = max(abs(simd_dot(SIMD2(b.start.x - a.start.x, b.start.y - a.start.y), n)),
                                  abs(simd_dot(SIMD2(b.end.x - a.start.x, b.end.y - a.start.y), n)))
                    guard touching, off < 0.3 else { continue }
                    // The two ends farthest apart become the merged wall.
                    var best = (ends[0], ends[1], 0.0)
                    for x in ends.indices { for y in ends.indices where y > x {
                        let d = gap(ends[x], ends[y]); if d > best.2 { best = (ends[x], ends[y], d) }
                    } }
                    var m = a
                    m.start = best.0
                    m.end = best.1
                    m.lengthFt = best.2
                    m.heightFt = max(a.heightFt, b.heightFt)
                    walls[i] = m
                    walls.remove(at: j)
                    into[b.id] = a.id
                    for (k, v) in into where v == b.id { into[k] = a.id }
                    changed = true
                    break outer
                }
            }
        }
        return (walls, into)
    }

    /// Letters the walls A, B, C… round the room, each running the same way
    /// (the room on its right on the plan), so a wall's start is on your
    /// left when you stand in the room facing it.
    static func letter(_ walls: inout [Wall]) {
        guard !walls.isEmpty else { return }
        let cx = walls.map { ($0.start.x + $0.end.x) / 2 }.reduce(0, +) / Double(walls.count)
        let cy = walls.map { ($0.start.y + $0.end.y) / 2 }.reduce(0, +) / Double(walls.count)
        for i in walls.indices {
            let w = walls[i]
            let cross = (w.end.x - w.start.x) * (cy - w.start.y) - (w.end.y - w.start.y) * (cx - w.start.x)
            if cross < 0 { (walls[i].start, walls[i].end) = (w.end, w.start) }
        }
        walls.sort {
            atan2(($0.start.y + $0.end.y) / 2 - cy, ($0.start.x + $0.end.x) / 2 - cx)
                < atan2(($1.start.y + $1.end.y) / 2 - cy, ($1.start.x + $1.end.x) / 2 - cx)
        }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for i in walls.indices { walls[i].label = i < letters.count ? String(letters[i]) : "\(i + 1)" }
    }

    private func distance(_ q: SIMD2<Double>, _ w: Wall) -> Double {
        let a = SIMD2(w.start.x, w.start.y), b = SIMD2(w.end.x, w.end.y)
        let ab = b - a
        let t = simd_clamp(simd_dot(q - a, ab) / max(simd_dot(ab, ab), 1e-9), 0, 1)
        return simd_length(q - (a + t * ab))
    }

    /// Points put in order round their middle.
    static func outline(of points: [Point]) -> [Point] {
        guard !points.isEmpty else { return [] }
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        return points.sorted { atan2($0.y - cy, $0.x - cx) < atan2($1.y - cy, $1.x - cx) }
    }

    /// The area inside an outline (shoelace).
    static func area(_ outline: [Point]) -> Double {
        guard outline.count > 2 else { return 0 }
        var sum = 0.0
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}

// MARK: - Scanning

/// Apple's room scanner, full screen: walk round the room, tap Done, and the
/// finished room comes back.
struct RoomScanCover: View {
    let onFinished: (ScannedRoom) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stopRequested = false
    @State private var processing = false
    @State private var failure: String? = nil
    @State private var savedBrightness: CGFloat? = nil

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(stopRequested: $stopRequested) { result in
                switch result {
                case .success(let captured):
                    let room = ScannedRoom(captured: captured)
                    dismiss()
                    onFinished(room)
                case .failure(let error):
                    failure = error.localizedDescription
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16)
                Spacer()
                if stopRequested {
                    Label("Building the floor plan…", systemImage: "hourglass")
                        .padding(14).background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 30)
                } else {
                    VStack(spacing: 10) {
                        Text("Walk slowly round the room, pointing at the walls, floor and doors.")
                            .font(.footnote).multilineTextAlignment(.center)
                            .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        Button {
                            stopRequested = true
                        } label: {
                            Text("Done scanning").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NDPrimaryButtonStyle())
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        // Awake and at full brightness while scanning; put back afterwards.
        .onAppear {
            savedBrightness = UIScreen.main.brightness
            UIApplication.shared.isIdleTimerDisabled = true
            UIScreen.main.brightness = 1
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if let savedBrightness { UIScreen.main.brightness = savedBrightness }
        }
        .alert("The scan didn't finish", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(failure ?? "")
        }
    }
}

/// Apple's room scanner view. Setting `stopRequested` ends the scan.
private struct RoomCaptureRepresentable: UIViewRepresentable {
    @Binding var stopRequested: Bool
    let onResult: (Result<CapturedRoom, Error>) -> Void

    func makeCoordinator() -> RoomCaptureCoordinator { RoomCaptureCoordinator(onResult: onResult) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if stopRequested, !context.coordinator.stopped {
            context.coordinator.stopped = true
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        if !coordinator.stopped { view.captureSession.stop() }
    }
}

/// Receives the finished room from the scanner.
@objc(TileRateRoomCaptureCoordinator)
final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate {
    let onResult: (Result<CapturedRoom, Error>) -> Void
    var stopped = false
    private var delivered = false

    init(onResult: @escaping (Result<CapturedRoom, Error>) -> Void) { self.onResult = onResult }
    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        guard !delivered else { return }
        delivered = true
        if let error { onResult(.failure(error)) } else { onResult(.success(processedResult)) }
    }
}

#if DEBUG
extension ScannedRoom {
    /// A made-up 9′ × 8′ bathroom for trying the editor in the simulator,
    /// which has no LiDAR: a tub along wall A, a door in C, a window in B.
    static var sample: ScannedRoom {
        var r = ScannedRoom()
        func wall(_ label: String, _ a: (Double, Double), _ b: (Double, Double)) -> Wall {
            let len = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            return Wall(label: label, lengthFt: len, heightFt: 8, start: .init(x: a.0, y: a.1), end: .init(x: b.0, y: b.1))
        }
        r.walls = [wall("A", (0, 0), (9, 0)), wall("B", (9, 0), (9, 8)), wall("C", (9, 8), (0, 8)), wall("D", (0, 8), (0, 0))]
        r.openings = [
            Opening(kind: .door, wallID: r.walls[2].id, widthFt: 2.5, heightFt: 80.0 / 12, bottomFt: 0, alongFt: 2),
            Opening(kind: .window, wallID: r.walls[1].id, widthFt: 2.5, heightFt: 3, bottomFt: 3.5, alongFt: 5),
        ]
        r.floorOutline = [.init(x: 0, y: 0), .init(x: 9, y: 0), .init(x: 9, y: 8), .init(x: 0, y: 8)]
        r.floorSqft = 72
        r.tubOutline = [.init(x: 0, y: 0), .init(x: 5, y: 0), .init(x: 5, y: 2.5), .init(x: 0, y: 2.5)]
        r.tubLengthFt = 5
        return r
    }
}
#endif
