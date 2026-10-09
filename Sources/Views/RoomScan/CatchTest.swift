import SwiftUI

/// Admin → Catch test (owner asked 2026-10-08): how close the owner's own
/// aim gets, to set how near something must be before it catches on a wall,
/// corner or edge (`Steering.catchFt`). Three drills, the way the model is
/// used — no catching during them, so the raw miss is measured:
///
///  1. Start a wall: tap right on a wall's line (a direct touch).
///  2. Drag a wall's end to touch another wall (hold, then steer).
///  3. Line up a tile edge with a window's side on the wall view (hold, then steer).
///
/// Each miss is kept in screen points (finger accuracy is fixed on the
/// glass) and in inches at the zoom it was done at, and summed up as the
/// miss 19 tries in 20 stay within. Results are kept in UserDefaults
/// ("catchTest.v1") and can be copied.
struct CatchTestView: View {
    enum Drill: String, CaseIterable, Identifiable {
        case startWall = "Start a wall"
        case dragEnd = "Drag an end to a wall"
        case lineUp = "Line up an edge"
        var id: String { rawValue }
        var steps: String {
            switch self {
            case .startWall: "Tap right on the blue wall's line, as if starting a new wall there."
            case .dragEnd: "The green end is held. Drag anywhere (slow for fine) until the end just touches the blue wall, then tap Done."
            case .lineUp: "The tile's right edge is held. Drag anywhere until it lines up with the window's left side, then tap Done."
            }
        }
    }
    enum Zoom: String, CaseIterable, Identifiable {
        case fitted = "As fitted"
        case zoomed = "Zoomed in ×3"
        var id: String { rawValue }
    }

    /// Points to the foot, as the model draws a 9′ × 8′ bathroom fitted on
    /// this phone (plan) or an 8′ wall (wall view); ×3 zoomed in.
    private func scale(_ drill: Drill, _ zoom: Zoom) -> Double {
        let base = drill == .lineUp ? 24.0 : 30.0
        return zoom == .zoomed ? base * 3 : base
    }

    static let goal = 15
    @State private var drill: Drill = .startWall
    @State private var zoom: Zoom = .fitted
    @State private var results: [String: [Double]] = CatchTestView.load()
    @State private var round = 0
    /// Drills 2 and 3: where the held thing is (points from its target), and the last drag step.
    @State private var gapPt: Double = Double.random(in: 6...24) / 12 * 30
    @State private var lastTranslation: CGSize = .zero
    /// Drill 1: the wall to tap (vertical or not, and where across the canvas, 0…1).
    // Chosen before the first drawing (set on appear, the first one wasn't redrawn).
    @State private var vertical = Bool.random()
    @State private var linePos = Double.random(in: 0.25...0.75)
    @State private var lastMiss: Double? = nil
    @State private var copied = false

    private var key: String { "\(drill.rawValue)|\(drill == .lineUp ? Zoom.fitted.rawValue : zoom.rawValue)" }
    private var misses: [Double] { results[key] ?? [] }

    var body: some View {
        Form {
            Section {
                Picker("Drill", selection: $drill) {
                    ForEach(Drill.allCases) { Text($0.rawValue).tag($0) }
                }
                if drill != .lineUp {
                    Picker("Zoom", selection: $zoom) {
                        ForEach(Zoom.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Text(drill.steps).font(.footnote).foregroundStyle(.secondary)
            } footer: {
                Text("Do \(Self.goal) tries of each drill, holding the phone the way you do on a job. Nothing catches during the test, so it measures your own aim.")
            }

            Section {
                canvas
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                if drill != .startWall {
                    Button {
                        record(abs(gapPt))
                    } label: {
                        Text("Done").frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
                HStack {
                    Text("Try \(min(misses.count + 1, Self.goal)) of \(Self.goal)")
                    Spacer()
                    if let lastMiss {
                        Text("Last: \(points(lastMiss)) · \(inches(lastMiss))").foregroundStyle(.secondary)
                    }
                }
                .font(.footnote.monospacedDigit())
            }

            Section("Results") {
                ForEach(Drill.allCases) { d in
                    ForEach(d == .lineUp ? [Zoom.fitted] : Zoom.allCases) { z in
                        resultRow(d, z)
                    }
                }
                Button(copied ? "Copied" : "Copy results") {
                    UIPasteboard.general.string = summary
                    copied = true
                }
                Button("Clear this drill's tries", role: .destructive) {
                    results[key] = nil
                    save()
                    newRound()
                }
            }
        }
        .navigationTitle("Catch test")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: drill) { _, _ in newRound() }
        .onChange(of: zoom) { _, _ in newRound() }
    }

    // MARK: The drills

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(white: 0.09)
                switch drill {
                case .startWall: startWall(size)
                case .dragEnd: dragEnd(size)
                case .lineUp: lineUp(size)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: "catch")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("catch"))
                .onChanged { v in
                    guard drill != .startWall else { return }
                    let step = Steering.steered(CGSize(width: v.translation.width - lastTranslation.width,
                                                       height: v.translation.height - lastTranslation.height))
                    lastTranslation = v.translation
                    // Moves to the sixteenth, as the model does; no catching.
                    let s = scale(drill, zoom) / 192
                    gapPt = ((gapPt - step.width) / s).rounded() * s
                }
                .onEnded { v in
                    lastTranslation = .zero
                    if drill == .startWall {
                        let p = v.location
                        let miss = vertical ? abs(p.x - size.width * linePos) : abs(p.y - size.height * linePos)
                        record(miss)
                    }
                })
        }
    }

    private func startWall(_ size: CGSize) -> some View {
        Path { p in
            if vertical {
                p.move(to: CGPoint(x: size.width * linePos, y: 20)); p.addLine(to: CGPoint(x: size.width * linePos, y: size.height - 20))
            } else {
                p.move(to: CGPoint(x: 20, y: size.height * linePos)); p.addLine(to: CGPoint(x: size.width - 20, y: size.height * linePos))
            }
        }
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        .allowsHitTesting(false)
    }

    /// A wall from the left whose end is `gapPt` short of a blue wall.
    private func dragEnd(_ size: CGSize) -> some View {
        let target = size.width * 0.7
        let end = CGPoint(x: target - gapPt, y: size.height / 2)
        return ZStack {
            Path { p in p.move(to: CGPoint(x: target, y: 20)); p.addLine(to: CGPoint(x: target, y: size.height - 20)) }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Path { p in p.move(to: CGPoint(x: 30, y: size.height / 2)); p.addLine(to: end) }
                .stroke(Color(white: 0.6), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().fill(Color.green).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 2))
                .position(end)
        }
        .allowsHitTesting(false)
    }

    /// A tile piece whose right edge is `gapPt` short of a window's left side.
    private func lineUp(_ size: CGSize) -> some View {
        let window = size.width * 0.62
        let edge = window - gapPt
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(white: 0.16)).frame(width: size.width - 40, height: size.height - 60)
                .position(x: size.width / 2, y: size.height / 2)
            Rectangle().stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 60, height: 80).position(x: window + 30, y: size.height / 2 - 40)
            Rectangle().fill(Color.blue.opacity(0.35)).overlay(Rectangle().stroke(Color.blue, lineWidth: 1.5))
                .frame(width: max(edge - 40, 1), height: size.height - 60)
                .position(x: (40 + edge) / 2, y: size.height / 2)
            Capsule().fill(Color.green).frame(width: 9, height: 28).position(x: edge, y: size.height / 2 + 40)
        }
        .allowsHitTesting(false)
    }

    // MARK: Recording

    private func record(_ missPt: Double) {
        var list = results[key] ?? []
        list.append(missPt)
        results[key] = list
        lastMiss = missPt
        save()
        newRound()
    }

    /// A new try: the wall somewhere else, or the held thing 6–24″ short.
    private func newRound() {
        round += 1
        vertical = Bool.random()
        linePos = Double.random(in: 0.25...0.75)
        gapPt = Double.random(in: 6...24) / 12 * scale(drill, zoom)
    }

    private func points(_ pt: Double) -> String { String(format: "%.1f pt", pt) }
    private func inches(_ pt: Double, scale s: Double? = nil) -> String {
        inchText(pt / (s ?? scale(drill, zoom)))
    }

    /// The miss 19 tries in 20 stay within (and the middle one).
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let i = min(sorted.count - 1, max(0, Int((p * Double(sorted.count)).rounded(.up)) - 1))
        return sorted[i]
    }

    private func resultRow(_ d: Drill, _ z: Zoom) -> some View {
        let list = results["\(d.rawValue)|\(z.rawValue)"] ?? []
        let s = scale(d, z)
        return VStack(alignment: .leading, spacing: 2) {
            Text(d == .lineUp ? d.rawValue : "\(d.rawValue) · \(z.rawValue)").font(.subheadline.weight(.semibold))
            if let p95 = Self.percentile(list, 0.95), let mid = Self.percentile(list, 0.5) {
                Text("\(list.count) tries · 19 in 20 within \(points(p95)) (\(inches(p95, scale: s))) · typical \(points(mid)) (\(inches(mid, scale: s)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("No tries yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        var lines = ["TileRate catch test"]
        for d in Drill.allCases {
            for z in d == .lineUp ? [Zoom.fitted] : Zoom.allCases {
                let list = results["\(d.rawValue)|\(z.rawValue)"] ?? []
                guard !list.isEmpty else { continue }
                let s = scale(d, z)
                let p95 = Self.percentile(list, 0.95) ?? 0, mid = Self.percentile(list, 0.5) ?? 0
                lines.append("\(d.rawValue), \(z.rawValue) (\(Int(s)) pt/ft): \(list.count) tries, 95% within "
                             + "\(points(p95)) = \(inches(p95, scale: s)), typical \(points(mid)); all: "
                             + list.map { String(format: "%.1f", $0) }.joined(separator: " "))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Kept on the phone

    private static let storeKey = "catchTest.v1"
    private static func load() -> [String: [Double]] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let r = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return r
    }
    private func save() {
        if let data = try? JSONEncoder().encode(results) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }
}
