import SwiftUI

// Admin screens for electric radiant heat: the list of systems, one system's
// pricing, and one part with its stocked sizes.

/// A plain number field that keeps what's typed and saves as you go.
private struct AmountField: View {
    let title: String
    @Binding var value: Double
    var prefix: String = ""
    var suffix: String = ""

    @State private var text = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                if !prefix.isEmpty { Text(prefix).foregroundStyle(.secondary) }
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 70, maxWidth: 110)
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, t in
            let v = Double(t.replacingOccurrences(of: ",", with: "")) ?? 0
            if v != value { value = v }
        }
    }

    static func format(_ v: Double) -> String {
        v == 0 ? "" : v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

/// A small number box for a row with two values.
private struct NumberBox: View {
    let placeholder: String
    @Binding var value: Double
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 100)
            .onAppear { text = AmountField.format(value) }
            .onChange(of: text) { _, t in
                let v = Double(t.replacingOccurrences(of: ",", with: "")) ?? 0
                if v != value { value = v }
            }
    }
}

/// Admin → Radiant Heat: every system the owner sells.
struct HeatingSystemsSection: View {
    @Binding var systems: [HeatingSystem]

    var body: some View {
        Section {
            ForEach($systems) { $system in
                NavigationLink {
                    HeatingSystemEditor(system: $system) {
                        systems.removeAll { $0.id == system.id }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(system.name).lineLimit(2)
                        Text("\(system.parts.count) parts · \(system.markupPercent.formatted())% markup")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { systems.remove(atOffsets: $0) }
            Button {
                systems.append(HeatingSystem(parts: [
                    HeatingPart(name: "Mat", rule: .coversFloor),
                    HeatingPart(name: "Heating cable", rule: .sizedToHeatedArea,
                                sizeGroups: [HeatingSizeGroup(name: "", sizes: [])]),
                    HeatingPart(name: "Thermostat", rule: .onePerSizedItem),
                ]))
            } label: {
                Label("Add heating system", systemImage: "plus")
            }
        } header: {
            Text("Electric Radiant Heat")
        } footer: {
            Text("Each system is priced from its parts at your cost, plus your markup, with installation charged per square foot of the floor or of the heated area.")
        }
    }
}

struct HeatingSystemEditor: View {
    @Binding var system: HeatingSystem
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var marginText: String {
        let m = system.markupPercent
        guard m > -100 else { return "" }
        let margin = (m / (100 + m) * 100).formatted(.number.precision(.fractionLength(0...1)))
        let price = (100 * (1 + m / 100)).formatted(.number.precision(.fractionLength(0...2)))
        return "\(m.formatted())% markup = \(margin)% margin. A $100 cost sells for $\(price)."
    }

    var body: some View {
        Form {
            Section("On the estimate") {
                TextField("Kit name", text: $system.name, axis: .vertical)
                TextField("Installation line", text: $system.laborName)
                Toggle("Kit is taxable", isOn: $system.taxable)
            }
            Section {
                AmountField(title: "Markup on cost", value: $system.markupPercent, suffix: "%")
            } header: {
                Text("Materials")
            } footer: {
                Text(marginText)
            }
            Section {
                Picker("Charge per sq ft of", selection: $system.laborOnHeatedAreaOnly) {
                    Text("Whole floor").tag(false)
                    Text("Heated area").tag(true)
                }
                AmountField(title: "Per sq ft", value: $system.laborPerSqft, prefix: "$")
                AmountField(title: "Minimum", value: $system.laborMinimum, prefix: "$")
            } header: {
                Text("Installation")
            } footer: {
                Text(system.laborOnHeatedAreaOnly
                     ? "Installation is charged on the heated square feet only."
                     : "Installation is charged on the whole floor, heated or not.")
            }
            Section {
                ForEach($system.parts) { $part in
                    NavigationLink {
                        HeatingPartEditor(part: $part)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.name.isEmpty ? "Unnamed part" : part.name)
                            Text(part.rule.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { system.parts.remove(atOffsets: $0) }
                .onMove { system.parts.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    system.parts.append(HeatingPart(name: "New part"))
                } label: {
                    Label("Add part", systemImage: "plus")
                }
            } header: {
                Text("Parts")
            }
            Section {
                Button("Delete this system", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete this heating system?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete()
            }
        } message: {
            Text("Areas that use it will no longer be charged for radiant heat.")
        }
        .navigationTitle("Heating system")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HeatingPartEditor: View {
    @Binding var part: HeatingPart

    var body: some View {
        Form {
            Section {
                TextField("Part name", text: $part.name)
                Picker("Quantity", selection: $part.rule) {
                    ForEach(HeatingPartRule.allCases) { Text($0.rawValue).tag($0) }
                }
            } footer: {
                Text(ruleHelp)
            }

            switch part.rule {
            case .coversFloor:
                Section {
                    AmountField(title: "Sq ft per piece", value: $part.coverageSqft)
                    AmountField(title: "Cost per piece", value: $part.unitCost, prefix: "$")
                }
            case .onePerSizedItem:
                Section { AmountField(title: "Cost each", value: $part.unitCost, prefix: "$") }
            case .fixedPerJob:
                Section {
                    AmountField(title: "Quantity per job", value: $part.quantity)
                    AmountField(title: "Cost each", value: $part.unitCost, prefix: "$")
                }
            case .sizedToHeatedArea:
                Section {
                    AmountField(title: "Needed per heated sq ft", value: $part.amountPerHeatedSqft,
                                suffix: part.unitLabel)
                    LabeledContent("Sizes measured in") {
                        TextField("LF", text: $part.unitLabel).multilineTextAlignment(.trailing)
                    }
                }
                ForEach($part.sizeGroups) { $group in
                    sizeGroupSection($group)
                }
                Section {
                    Button {
                        part.sizeGroups.append(HeatingSizeGroup())
                    } label: {
                        Label("Add size list", systemImage: "plus")
                    }
                } footer: {
                    Text("Use more than one list when the choice depends on the heated area, e.g. 120V wire up to 100 sq ft and 240V above. The list with the smallest limit that fits is used; leave the limit empty for any size of area.")
                }
            }
        }
        .navigationTitle(part.name.isEmpty ? "Part" : part.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ruleHelp: String {
        switch part.rule {
        case .coversFloor: "Floor sq ft ÷ sq ft per piece, rounded up."
        case .sizedToHeatedArea: "Heated sq ft × amount per sq ft, rounded up to the next stocked size. Longer runs are split evenly across the fewest pieces."
        case .onePerSizedItem: "One for each piece chosen from a size list, e.g. a thermostat per wire."
        case .fixedPerJob: "The same quantity on every job."
        }
    }

    private func sizeGroupSection(_ group: Binding<HeatingSizeGroup>) -> some View {
        Section {
            TextField("List name (e.g. 120V)", text: group.name)
            AmountField(title: "Up to heated sq ft", value: Binding(
                get: { group.wrappedValue.maxHeatedSqft ?? 0 },
                set: { group.wrappedValue.maxHeatedSqft = $0 > 0 ? $0 : nil }))
            ForEach(group.sizes) { $size in
                HStack(spacing: 6) {
                    NumberBox(placeholder: "Size", value: $size.amount)
                    Text(part.unitLabel).foregroundStyle(.secondary)
                    Spacer()
                    Text("$").foregroundStyle(.secondary)
                    NumberBox(placeholder: "Cost", value: $size.cost)
                }
            }
            .onDelete { group.wrappedValue.sizes.remove(atOffsets: $0) }
            Button {
                group.wrappedValue.sizes.append(HeatingSize())
            } label: {
                Label("Add size", systemImage: "plus")
            }
            Button("Delete this size list", role: .destructive) {
                part.sizeGroups.removeAll { $0.id == group.wrappedValue.id }
            }
        } header: {
            Text(group.wrappedValue.name.isEmpty ? "Sizes" : "\(group.wrappedValue.name) sizes")
        }
    }
}
