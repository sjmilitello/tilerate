import SwiftUI

// Admin → Estimate layouts (roadmap Phase 4): the PDF layouts, the one new
// estimates use, and each layout's settings with a preview.

struct EstimateLayoutsSection: View {
    @Binding var rates: Rates

    var body: some View {
        Section {
            Picker("New estimates use", selection: $rates.defaultTemplateID) {
                ForEach(rates.estimateTemplates) { Text($0.name).tag($0.id) }
            }
            ForEach($rates.estimateTemplates) { $template in
                NavigationLink {
                    LayoutEditor(template: $template, rates: rates,
                                 canDelete: rates.estimateTemplates.count > 1) {
                        rates.estimateTemplates.removeAll { $0.id == template.id }
                        if rates.defaultTemplateID == template.id, let first = rates.estimateTemplates.first {
                            rates.defaultTemplateID = first.id
                        }
                    }
                } label: {
                    LabeledContent(template.name, value: template.detail.rawValue)
                }
            }
            Button {
                var copy = rates.template(nil)
                copy.id = UUID()
                copy.name = "\(copy.name) copy"
                rates.estimateTemplates.append(copy)
            } label: {
                Label("Add a layout (copy of the default)", systemImage: "plus")
            }
            let missing = EstimateTemplate.starters.filter { s in !rates.estimateTemplates.contains { $0.id == s.id } }
            if !missing.isEmpty {
                Button("Bring back \(missing.map(\.name).joined(separator: ", "))") {
                    rates.estimateTemplates += missing
                }
            }
        } header: {
            Text("Estimate layouts")
        } footer: {
            Text("How the PDF is laid out. Each estimate can use a different layout (on its review screen), and a saved estimate keeps the layout it was sent in.")
        }
    }
}

struct LayoutEditor: View {
    @Binding var template: EstimateTemplate
    let rates: Rates
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var preview: Data? = nil

    var body: some View {
        Form {
            Section {
                LabeledContent("Layout name") {
                    TextField("Name", text: $template.name).multilineTextAlignment(.trailing)
                }
                LabeledContent("Title on the PDF") {
                    TextField("Estimate", text: $template.title).multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker("Show", selection: $template.detail) {
                    ForEach(EstimateTemplate.Detail.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Quantity and rate columns", isOn: $template.showQuantities)
                Toggle("Group price list items", isOn: $template.groupPriceList)
                if template.groupPriceList {
                    Toggle("List the items under each group", isOn: $template.listGroupedItems)
                }
            } header: {
                Text("Detail")
            } footer: {
                Text(detailHelp + " Grouping puts items named \"Group: name\" (such as \"Demo: Tile walls\") on one line per group. Totals are the same in every layout.")
            }

            Section {
                Picker("Colour", selection: $template.accent) {
                    ForEach(EstimateTemplate.Accent.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper(template.validForDays == 0 ? "No \"valid until\" date" : "Valid for \(template.validForDays) days",
                        value: $template.validForDays, in: 0...365, step: template.validForDays < 30 ? 1 : 15)
                Toggle("Signature lines", isOn: $template.showSignature)
            } header: {
                Text("Look")
            }

            Section {
                Toggle("3-D views of the job", isOn: $template.include3DViews)
                if template.include3DViews {
                    Picker("Pictures per page", selection: $template.picturesPerPage) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                Text("Pages after the estimate with the 3-D views chosen for it (Preview → 3-D views). Drawn from the room scan, so they match the job.")
            }

            Section {
                ForEach($template.sections) { $section in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Heading (e.g. Payment terms)", text: $section.heading)
                            .font(.subheadline.weight(.semibold))
                        TextField("Text", text: $section.body, axis: .vertical)
                            .lineLimit(2...8)
                    }
                }
                .onDelete { template.sections.remove(atOffsets: $0) }
                .onMove { template.sections.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    template.sections.append(.init())
                } label: {
                    Label("Add text", systemImage: "plus")
                }
            } header: {
                Text("Text after the totals")
            } footer: {
                Text("Payment terms, what's not included, warranty, notes. Swipe left to remove one.")
            }

            Section {
                Button {
                    preview = try? EstimatePDF.make(totals: Self.sampleTotals(rates), template: template,
                                                    biz: Self.business, cust: Self.sampleCustomer,
                                                    logo: decodeBase64Image(UserDefaults.standard.string(forKey: "biz.logoBase64") ?? ""),
                                                    estimateNumber: 1000, forceSinglePage: false).data
                } label: {
                    Label("Preview with a sample estimate", systemImage: "doc.richtext")
                }
            }

            if canDelete {
                Section {
                    Button("Delete this layout", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Saved estimates that used it keep it.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                NavigationStack {
                    PDFKitPreview(data: preview)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.preview = nil } } }
                }
            }
        }
        .confirmationDialog("Delete \(template.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                onDelete()
            }
        }
    }

    private var detailHelp: String {
        switch template.detail {
        case .everyLine: "Every area's installation and each extra on its own line."
        case .laborAndMaterials: "Each area as one labor line and one materials line, with the extras named under them."
        case .areaTotals: "One price per area, with its extras named under it."
        }
    }

    private static var business: PartyInfo {
        let d = UserDefaults.standard
        func s(_ k: String) -> String { d.string(forKey: k) ?? "" }
        return PartyInfo(name: s("biz.name"), address: s("biz.address"), address2: s("biz.address2"),
                         cityStateZip: s("biz.cityStateZip"), phone: s("biz.phone"), email: s("biz.email"))
    }

    private static let sampleCustomer = PartyInfo(name: "Sample Customer", address: "123 Main Street",
                                                  cityStateZip: "Anytown", phone: "", email: "")

    /// A shower with extras and a floor, priced at the current rates.
    static func sampleTotals(_ rates: Rates) -> EstimateTotals {
        var shower = WordingEditor.example(.shower)
        shower.additionsLabor = [
            AdditionItem(activity: "Demo: Tile walls", qty: 80, rate: 3),
            AdditionItem(activity: "Demo: Tile shower base", qty: 15, rate: 8),
            AdditionItem(activity: "Waterproofing", qty: 1, rate: 300),
        ]
        shower.additionsMaterials = [AdditionItem(activity: "Trim and setting materials", qty: 1, rate: 240, taxable: true)]
        var room = EstimateRoom(name: "Primary bath")
        room.sections = [shower, WordingEditor.example(.floor)]
        return computeTotals(document: EstimateDocument(rooms: [room]), rates: rates,
                             shippingEnabled: false, shipping: 0, taxPercent: 6.25)
    }
}
