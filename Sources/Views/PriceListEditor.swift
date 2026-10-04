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
                        Text("\(currencyString(item.price)) \(item.unit.rawValue)")
                            .font(.subheadline).foregroundStyle(.secondary)
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
    @Binding var item: PriceListItem
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Name on the estimate", text: $item.name)
                Picker("Charged", selection: $item.unit) {
                    ForEach(PriceListUnit.allCases) { Text($0.rawValue).tag($0) }
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
            priceText = item.price == 0 ? "" : item.price.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        }
        .onChange(of: priceText) { _, t in
            let v = Double(t.replacingOccurrences(of: ",", with: "")) ?? 0
            if v != item.price { item.price = v }
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
