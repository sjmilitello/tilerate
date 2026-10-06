import SwiftUI

/// Admin → Price List: extras picked for an area instead of typed each time.
struct PriceListSection: View {
    @Binding var items: [PriceListItem]

    var body: some View {
        Section {
            ForEach($items) { $item in
                NavigationLink {
                    PriceListItemEditor(item: $item) {
                        items.removeAll { $0.id == item.id }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "Unnamed item" : item.name)
                            Text(item.isMaterial ? (item.taxable ? "Materials, taxable" : "Materials") : "Labor")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(currencyString(item.price)) \(item.unit.rawValue)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if item.minimum > 0 {
                                Text("min \(currencyString(item.minimum))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            Button {
                items.append(PriceListItem(name: "New item"))
            } label: {
                Label("Add item", systemImage: "plus")
            }
        } header: {
            Text("Price List")
        } footer: {
            Text("Pick these for an area under Additions / Extras. The price can still be changed on one estimate. Per-sq-ft items fill in the area's square feet.")
        }
    }
}

struct PriceListItemEditor: View {
    private static func text(_ v: Double) -> String {
        v == 0 ? "" : v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
    private static func number(_ t: String) -> Double {
        Double(t.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    @Binding var item: PriceListItem
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var minimumText = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Name on the estimate", text: $item.name)
                Picker("Charged", selection: $item.unit) {
                    ForEach(PriceListUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                if item.unit == .perSqft {
                    Picker("Square feet of", selection: $item.measure) {
                        ForEach(PriceListMeasure.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                LabeledContent("Price") {
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 70, maxWidth: 110)
                    }
                }
                LabeledContent("Minimum charge") {
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("None", text: $minimumText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 70, maxWidth: 110)
                    }
                }
            } footer: {
                Text("The least this item charges on an area, however small the quantity. Leave empty for no minimum.")
            }
            Section {
                Picker("Type", selection: $item.isMaterial) {
                    Text("Labor").tag(false)
                    Text("Materials").tag(true)
                }
                .pickerStyle(.segmented)
                if item.isMaterial {
                    Toggle("Taxable", isOn: $item.taxable)
                }
            } footer: {
                Text("Materials count toward shipping; taxable materials are taxed.")
            }
            Section {
                Button("Delete this item", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Estimates that already use it keep their line.")
            }
        }
        .navigationTitle(item.name.isEmpty ? "Price list item" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            priceText = Self.text(item.price)
            minimumText = Self.text(item.minimum)
        }
        .onChange(of: priceText) { _, t in
            let v = Self.number(t)
            if v != item.price { item.price = v }
        }
        .onChange(of: minimumText) { _, t in
            let v = Self.number(t)
            if v != item.minimum { item.minimum = v }
        }
        .confirmationDialog("Delete \(item.name.isEmpty ? "this item" : item.name)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete()
            }
        }
    }
}

/// The price list as menu entries. Items named "Group: name" (e.g. "Demo:
/// Tile walls") are gathered under a submenu for their group.
struct PriceListMenuItems: View {
    let items: [PriceListItem]
    let onPick: (PriceListItem) -> Void

    private func split(_ item: PriceListItem) -> (group: String?, name: String) {
        let parts = item.name.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2 && !parts[0].isEmpty ? (parts[0], parts[1]) : (nil, item.name)
    }

    private func label(_ item: PriceListItem, _ name: String) -> String {
        "\(name) — \(currencyString(item.price)) \(item.unit.rawValue)"
    }

    var body: some View {
        let groups = items.compactMap { split($0).group }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ForEach(groups, id: \.self) { group in
            Menu(group == "Demo" ? "Demolition" : group) {
                ForEach(items.filter { split($0).group == group }) { item in
                    Button(label(item, split(item).name)) { onPick(item) }
                }
            }
        }
        ForEach(items.filter { split($0).group == nil }) { item in
            Button(label(item, item.name)) { onPick(item) }
        }
    }
}
