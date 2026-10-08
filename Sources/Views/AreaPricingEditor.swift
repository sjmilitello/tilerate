import SwiftUI

// Admin → Area pricing (roadmap Phase 5): each surface's rule — a square-foot
// rate with a minimum, or a minimum with an escalator window — with example
// prices, a warning when a bigger area would cost less, and a suggested
// escalator. Tile, size and layout adders go on top of every rule.

struct AreaPricingSection: View {
    @Binding var rates: Rates

    /// The window an escalator starts with when switched on: the floor's
    /// saved one for floors, otherwise 50 to 99 sq ft.
    private func startingWindow(_ surface: PricedSurface) -> EscalatorWindow {
        surface == .floor
            ? EscalatorWindow(from: rates.floorEscThresholdLower, through: rates.floorEscThresholdUpper,
                              perSqft: rates.floorEscAdjPerSqft)
            : EscalatorWindow(from: 50, through: 99, perSqft: 0)
    }

    var body: some View {
        Section {
            ForEach(PricedSurface.allCases) { surface in
                NavigationLink {
                    SurfaceRuleEditor(surface: surface, startingWindow: startingWindow(surface), rule: Binding(
                        get: { rates.rule(for: surface) },
                        set: { rates.setRule($0, for: surface) }))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(surface.title)
                            if firstPriceDrop(rates.rule(for: surface)) != nil {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                        Text(ruleSummary(rates.rule(for: surface)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Area pricing")
        } footer: {
            Text("What each surface charges per square foot, its minimum, and any escalator. Tile, size and layout adders go on top.")
        }
    }
}

/// Admin → Stone pieces, new walls and shower doors, and what's placed on a
/// scan: benches, niches, windows and corner pieces.
struct KneeWallSection: View {
    @Binding var rates: Rates

    private func stone(_ item: StoneItem) -> Binding<StoneRate> {
        Binding(get: { rates.stoneRate(item) }, set: { rates.setStoneRate($0, for: item) })
    }

    private var defaults: Binding<ScanItemDefaults> { $rates.scanDefaults }

    var body: some View {
        Section {
            ForEach(StoneItem.allCases, id: \.self) { item in
                NavigationLink {
                    StoneRateEditor(title: item.title, rate: stone(item))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(stoneSummary(rates.stoneRate(item))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Stone pieces")
        } footer: {
            Text("Curbs, caps, headers, jambs and bench tops and fronts are tile unless switched to stone on the plan; stone goes on its own line (still changeable on an estimate). Set a piece's usual width to price it by the square foot instead. A niche's or window's stone counts toward its own charge (below).")
        }

        Section {
            AmountRow(title: "Bench minimum (each)", value: $rates.unitBench, prefix: "$")
            AmountRow(title: "Bench, per linear ft", value: $rates.benchPerLinFt, prefix: "$")
            AmountRow(title: "Niche minimum (each)", value: $rates.unitNiche, prefix: "$")
            AmountRow(title: "Window minimum (each)", value: $rates.unitWindow, prefix: "$")
            AmountRow(title: "Corner shelf (each)", value: $rates.unitShelf, prefix: "$")
            AmountRow(title: "Corner footrest (each)", value: $rates.unitFootrest, prefix: "$")
            AmountRow(title: "Corner seat (each)", value: $rates.unitSeat, prefix: "$")
        } header: {
            Text("Benches, niches, windows & corner pieces")
        } footer: {
            Text("A bench placed on a scan is its length at the per-foot price, or the minimum if that's more. A stone niche or window is its stone at the niche or window stone price, or the minimum if that's more; in tile, the minimum. Corner shelves, footrests and seats are stone, each at their price.")
        }

        Section {
            AmountRow(title: "Framed bench height", value: defaults.framedBenchHeightIn, suffix: "in")
            AmountRow(title: "Framed bench depth", value: defaults.framedBenchDepthIn, suffix: "in")
            AmountRow(title: "Floating bench height", value: defaults.floatingBenchHeightIn, suffix: "in")
            AmountRow(title: "Floating bench depth", value: defaults.floatingBenchDepthIn, suffix: "in")
            AmountRow(title: "Niche width", value: defaults.nicheWidthIn, suffix: "in")
            AmountRow(title: "Niche height", value: defaults.nicheHeightIn, suffix: "in")
            AmountRow(title: "Niche off the floor", value: defaults.nicheBottomIn, suffix: "in")
            AmountRow(title: "Window width", value: defaults.windowWidthIn, suffix: "in")
            AmountRow(title: "Window height", value: defaults.windowHeightIn, suffix: "in")
            AmountRow(title: "Window off the floor", value: defaults.windowBottomIn, suffix: "in")
            AmountRow(title: "Corner shelf size", value: defaults.cornerShelfIn, suffix: "in")
            AmountRow(title: "Corner shelf height", value: defaults.cornerShelfHeightIn, suffix: "in")
            AmountRow(title: "Corner footrest size", value: defaults.cornerFootrestIn, suffix: "in")
            AmountRow(title: "Corner footrest height", value: defaults.cornerFootrestHeightIn, suffix: "in")
            AmountRow(title: "Corner seat size", value: defaults.cornerSeatIn, suffix: "in")
            AmountRow(title: "Corner seat height", value: defaults.cornerSeatHeightIn, suffix: "in")
        } header: {
            Text("Starting sizes on a scan")
        } footer: {
            Text("What each starts at when placed on a room scan; drag or type to change it there.")
        }

        Section {
            AmountRow(title: "Curb height", value: $rates.curbHeightIn, suffix: "in")
            AmountRow(title: "New wall thickness", value: $rates.kneeWallThicknessIn, suffix: "in")
            AmountRow(title: "Shower door width", value: $rates.showerDoorWidthIn, suffix: "in")
            AmountRow(title: "Shower door height (to header)", value: $rates.showerDoorHeightIn, suffix: "in")
        } header: {
            Text("Curbs, new walls & shower doors")
        } footer: {
            Text("Jambs run from the curb to the top of the tile, or to the header over a shower door. A shower door starts at this size; drag it on the wall to change it, or to the ceiling for no header. A wall added on the plan starts at this thickness (4½″ is a 2×4 with backer board both sides).")
        }
    }
}

/// "$30/lin ft" or "4″ wide · $45/sq ft"
func stoneSummary(_ r: StoneRate) -> String {
    func money(_ v: Double) -> String { v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0...2))) }
    if r.usesSqft { return "\(inchText(r.widthIn / 12)) wide · \(money(r.perSqft))/sq ft" }
    return "\(money(r.perLinFt))/lin ft" + (r.widthIn > 0 ? " · \(inchText(r.widthIn / 12)) wide" : "")
}

/// One stone piece's price: per linear foot, a usual width, and — with a
/// width — per square foot instead.
struct StoneRateEditor: View {
    let title: String
    @Binding var rate: StoneRate

    var body: some View {
        Form {
            Section {
                AmountRow(title: "Per linear ft", value: $rate.perLinFt, prefix: "$")
                AmountRow(title: "Usual width", value: $rate.widthIn, suffix: "in")
                if rate.widthIn > 0 {
                    Toggle("Price by the square foot", isOn: $rate.bySqft)
                    if rate.bySqft {
                        AmountRow(title: "Per sq ft", value: $rate.perSqft, prefix: "$")
                    }
                }
            } footer: {
                Text(rate.widthIn > 0
                     ? "Square feet are the length × \(inchText(rate.widthIn / 12))."
                     : "Enter its usual width to be able to price it by the square foot.")
            }
        }
        .navigationTitle(title)
    }
}

/// "$22/sq ft · min $1,500 · $14/sq ft from 50 to 99 sq ft"
func ruleSummary(_ rule: SurfaceRule) -> String {
    func money(_ v: Double) -> String { v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0...2))) }
    switch rule {
    case let .rate(rate, minimum):
        return "\(money(rate))/sq ft" + ((minimum ?? 0) > 0 ? " · min \(money(minimum!))" : "")
    case let .escalator(rate, minimum, window):
        let escalator = window.perSqft > 0
            ? " · \(money(window.perSqft))/sq ft over \(window.from), up to \(window.through) sq ft" : ""
        return "\(money(rate))/sq ft · min \(money(minimum))" + escalator
    }
}

struct SurfaceRuleEditor: View {
    let surface: PricedSurface
    let startingWindow: EscalatorWindow
    @Binding var rule: SurfaceRule

    @State private var suggestionNote: String? = nil

    private var isEscalator: Binding<Bool> {
        Binding(get: { rule.isEscalator }, set: { on in
            switch (rule, on) {
            case let (.rate(rate, minimum), true):
                rule = .escalator(perSqft: rate, minimum: minimum ?? 0, window: startingWindow)
            case let (.escalator(rate, minimum, _), false):
                rule = .rate(perSqft: rate, minimum: minimum)
            default: break
            }
        })
    }

    var body: some View {
        Form {
            Section {
                Picker("Rule", selection: isEscalator) {
                    Text("Rate and minimum").tag(false)
                    Text("Minimum with escalator").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(rule.isEscalator
                     ? "Small areas pay the minimum. Inside the window, each square foot over its start adds the escalator. Past the window, the square-foot price takes over whenever it is more."
                     : "Square feet × the rate, or the minimum when that comes to less.")
            }

            Section("Prices") {
                AmountRow(title: "Per sq ft", value: Binding(get: { rule.rate }, set: { rule.rate = $0 }), prefix: "$")
                AmountRow(title: "Minimum", value: Binding(get: { rule.minimum }, set: { rule.minimum = $0 }), prefix: "$")
            }

            if case let .escalator(rate, minimum, window) = rule {
                Section {
                    AmountRow(title: "Escalator per sq ft", value: Binding(get: { window.perSqft }, set: { v in
                        rule = .escalator(perSqft: rate, minimum: minimum,
                                          window: EscalatorWindow(from: window.from, through: window.through, perSqft: v))
                    }), prefix: "$")
                    AmountRow(title: "Starts after (sq ft)", value: Binding(get: { Double(window.from) }, set: { v in
                        rule = .escalator(perSqft: rate, minimum: minimum,
                                          window: EscalatorWindow(from: Int(v), through: window.through, perSqft: window.perSqft))
                    }), wholeNumber: true)
                    AmountRow(title: "Ends at (sq ft)", value: Binding(get: { Double(window.through) }, set: { v in
                        rule = .escalator(perSqft: rate, minimum: minimum,
                                          window: EscalatorWindow(from: window.from, through: Int(v), perSqft: window.perSqft))
                    }), wholeNumber: true)
                    if window.through < window.from {
                        Text("The window ends before it starts, so the escalator never applies.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Button("Suggest an escalator") { suggest(rate: rate, minimum: minimum, window: window) }
                    if let suggestionNote {
                        Text(suggestionNote).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Escalator")
                } footer: {
                    Text("The suggestion closes the gap between the minimum and the square-foot price with no jump and no drop: (price per sq ft × the first sq ft after the window − minimum) ÷ the window's width, rounded down to the cent.")
                }
            }

            Section {
                ForEach(exampleSizes, id: \.self) { size in
                    LabeledContent("\(size) sq ft", value: basePrice(rule, sqft: Double(size))
                        .formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                }
                if let drop = firstPriceDrop(rule) {
                    Label {
                        Text("A bigger area costs less: \(drop.sqft) sq ft is \(money(drop.price)) but \(drop.sqft + 1) sq ft is \(money(drop.next)). \(dropAdvice)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Examples, before adders")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(surface.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var exampleSizes: [Int] {
        guard case let .escalator(_, _, window) = rule else { return [10, 25, 50, 75, 100, 150, 200] }
        let points = [max(1, window.from - 10), window.from, window.from + 1, (window.from + window.through) / 2,
                      window.through, window.through + 1, window.through * 2]
        return Array(Set(points.filter { $0 > 0 })).sorted()
    }

    private var dropAdvice: String {
        rule.isEscalator
            ? "Use Suggest an escalator, raise the price per sq ft, or end the window where the price per sq ft catches up."
            : "Raise the price per sq ft or lower the minimum."
    }

    private func suggest(rate: Double, minimum: Double, window: EscalatorWindow) {
        if let e = suggestedEscalator(perSqft: rate, minimum: minimum, from: window.from, through: window.through) {
            rule = .escalator(perSqft: rate, minimum: minimum,
                              window: EscalatorWindow(from: window.from, through: window.through, perSqft: e))
            suggestionNote = "Set to \(money(e)) per sq ft: \(window.through) sq ft comes to \(money(basePrice(rule, sqft: Double(window.through)))), and \(window.through + 1) sq ft at the square-foot price to \(money(rate * Double(window.through + 1)))."
        } else if rate * Double(window.from) >= minimum {
            suggestionNote = "No escalator is needed: at \(window.from) sq ft the square-foot price already reaches the minimum."
        } else {
            suggestionNote = "The square-foot price never reaches the minimum by the end of the window. Raise the price per sq ft or move the window's end."
        }
    }

    private func money(_ v: Double) -> String {
        v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

extension SurfaceRule {
    /// The square-foot price, whichever the rule.
    var rate: Double {
        get {
            switch self {
            case let .rate(r, _), let .escalator(r, _, _): r
            }
        }
        set {
            switch self {
            case let .rate(_, m): self = .rate(perSqft: newValue, minimum: m)
            case let .escalator(_, m, w): self = .escalator(perSqft: newValue, minimum: m, window: w)
            }
        }
    }

    /// The minimum charge (0 = none), whichever the rule.
    var minimum: Double {
        get {
            switch self {
            case let .rate(_, m): m ?? 0
            case let .escalator(_, m, _): m
            }
        }
        set {
            switch self {
            case let .rate(r, _): self = .rate(perSqft: r, minimum: newValue)
            case let .escalator(r, _, w): self = .escalator(perSqft: r, minimum: newValue, window: w)
            }
        }
    }
}

/// A dollar amount that keeps what is typed and saves as you go.
private struct AmountRow: View {
    let title: String
    @Binding var value: Double
    var prefix: String = ""
    var suffix: String = ""
    var wholeNumber: Bool = false
    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                if !prefix.isEmpty { Text(prefix).foregroundStyle(.secondary) }
                TextField("0", text: $text)
                    .keyboardType(wholeNumber ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 70, maxWidth: 110)
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
            }
        }
        .onAppear { text = value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
        .onChange(of: value) { _, v in
            let shown = Double(text.replacingOccurrences(of: ",", with: "")) ?? 0
            if abs(shown - v) > 0.0001 { text = v == 0 ? "" : v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
        }
        .onChange(of: text) { _, t in
            let v = Double(t.replacingOccurrences(of: ",", with: "")) ?? 0
            if v != value { value = v }
        }
    }
}
