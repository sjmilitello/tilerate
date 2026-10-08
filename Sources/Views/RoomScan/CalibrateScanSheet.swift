import SwiftUI

/// Calibrating a room's scan with a tape measure (owner asked 2026-10-07):
/// tape one wall — or one each way, for length and width — and optionally
/// the ceiling; the scan and every area measured from it are corrected to
/// match (`ScanCalibration`). Shows how far off the scan was, and how close
/// each measured wall comes out, before anything changes.
struct CalibrateScanSheet: View {
    let room: ScannedRoom
    let onApply: (ScanCalibration) -> Void
    /// Taking the last calibration back off, when there is one.
    let onUndo: (() -> Void)?
    /// Offered straight after a scan: "Skip" rather than "Cancel".
    var afterScan = false

    @Environment(\.dismiss) private var dismiss
    @State private var tape: [UUID: Double] = [:]
    @State private var ceilingIn: Double = 0

    private var scanned: [ScannedRoom.Wall] { room.walls.filter { !$0.planned } }
    private var entered: [UUID: Double] { tape.filter { $0.value > 0 } }
    /// The correction the tape asks for; nil when it changes nothing (e.g.
    /// the earlier measurements, shown again, already match).
    private var calibration: ScanCalibration? {
        guard !entered.isEmpty || ceilingIn > 0 else { return nil }
        let c = ScanCalibration.solve(room, tapeIn: entered, ceilingIn: ceilingIn > 0 ? ceilingIn : nil)
        return abs(c.sx - 1) < 1e-5 && abs(c.sy - 1) < 1e-5 && abs(c.sz - 1) < 1e-5 ? nil : c
    }

    /// What was taped before, shown again: changing one keeps the others
    /// (one wall alone would otherwise rescale both ways).
    private func loadEarlierTape() {
        for c in room.calibrations {
            for (key, inches) in c.tapeIn {
                if let id = UUID(uuidString: key), room.wall(id) != nil { tape[id] = inches }
            }
            if let ceiling = c.ceilingIn { ceilingIn = ceiling }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlanCanvas(room: room, mine: [], interactive: false)
                        .frame(height: 170)
                        .listRowInsets(EdgeInsets())
                        .background(Color(white: 0.09))
                } footer: {
                    Text("Tape one wall, or better, one wall each way (say A and B), and enter it below. The scan and every area measured from it are corrected to match.")
                }

                Section("Walls") {
                    ForEach(scanned) { w in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wall \(w.label)").font(.body.weight(.semibold))
                                Text("Scan \(feetAndInches(w.lengthFt)) (\(InchField.format(w.lengthFt * 12))″)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            InchField(title: "Tape", inches: Binding(get: { tape[w.id] ?? 0 }, set: { tape[w.id] = $0 }), blankWhenZero: true)
                                .frame(width: 120)
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ceiling height").font(.body.weight(.semibold))
                            Text("Scan \(feetAndInches(room.ceilingFt))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        InchField(title: "Tape", inches: $ceilingIn, blankWhenZero: true).frame(width: 120)
                    }
                } header: {
                    Text("Optional")
                }

                if let c = calibration {
                    Section("What changes") {
                        ForEach(summary(c), id: \.self) { Text($0) }
                        ForEach(scanned.filter { entered[$0.id] != nil }) { w in
                            let after = w.lengthFt * c.lengthFactor(of: w) * 12
                            let off = after - (entered[w.id] ?? 0)
                            LabeledContent("Wall \(w.label)",
                                           value: abs(off) < 0.125 ? "matches the tape" : "\(off > 0 ? "+" : "−")\(InchField.format(abs(off)))″ from the tape")
                        }
                    }
                }

                if let onUndo, !room.calibrations.isEmpty {
                    Section {
                        Button("Undo the last calibration", role: .destructive) {
                            onUndo()
                            dismiss()
                        }
                    } footer: {
                        Text("Already calibrated \(room.calibrations.count == 1 ? "once" : "\(room.calibrations.count) times"). Calibrating again corrects it further.")
                    }
                }
            }
            .navigationTitle(afterScan ? "Tape a wall?" : "Calibrate the scan")
            .onAppear(perform: loadEarlierTape)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(afterScan ? "Skip" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let c = calibration { onApply(c) }
                        dismiss()
                    }
                    .disabled(calibration == nil)
                }
            }
        }
    }

    /// "Along walls A and C, the scan was 1.1% long", each way and up.
    private func summary(_ c: ScanCalibration) -> [String] {
        let u = ScannedRoom.Point(x: cos(c.angle), y: sin(c.angle))
        func labels(_ alongU: Bool) -> String {
            let ws = scanned.filter { w in
                let du = abs((w.end.x - w.start.x) * u.x + (w.end.y - w.start.y) * u.y) / max(w.lengthFt, 1e-9)
                return alongU ? du > 0.9 : du < 0.44
            }.map(\.label)
            return ws.isEmpty ? (alongU ? "one way" : "the other way") : "along wall" + (ws.count > 1 ? "s " : " ") + ws.joined(separator: ", ")
        }
        func change(_ s: Double) -> String {
            let pct = (1 / s - 1) * 100
            if abs(pct) < 0.05 { return "the scan was right" }
            return "the scan was \(String(format: "%.1f", abs(pct)))% \(pct > 0 ? "long" : "short")"
        }
        var out: [String] = []
        if abs(c.sx - c.sy) < 1e-9 {
            out.append("Everywhere, \(change(c.sx)).")
        } else {
            out.append("\(labels(true).prefix(1).capitalized + labels(true).dropFirst()), \(change(c.sx)).")
            out.append("\(labels(false).prefix(1).capitalized + labels(false).dropFirst()), \(change(c.sy)).")
        }
        if c.sz != 1 { out.append("Heights: \(change(c.sz)).") }
        return out
    }
}
