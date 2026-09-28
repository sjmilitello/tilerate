import SwiftUI

/// The whole estimate before it goes out: what needs fixing, what each area
/// costs, the charges and the total, then Save and Create PDF.
struct EstimateReviewView: View {
    @ObservedObject var store: Store
    @ObservedObject var saved: SavedEstimatesStore
    let onEditArea: (_ room: UUID, _ section: UUID, _ step: Int) -> Void

    @AppStorage("estimate.counter") private var estimateCounter: Int = 1400
    @AppStorage("export.shipping") private var exportShipping: Double = 0.0
    @AppStorage("export.taxPercent") private var taxPercent: Double = 0.0
    @AppStorage("additions.shippingEnabled") private var shippingEnabled: Bool = false
    @AppStorage("export.forceSinglePage") private var forceSinglePage: Bool = false
    @AppStorage("biz.name") private var bizName: String = ""
    @AppStorage("biz.address") private var bizAddress: String = ""
    @AppStorage("biz.address2") private var bizAddress2: String = ""
    @AppStorage("biz.cityStateZip") private var bizCityStateZip: String = ""
    @AppStorage("biz.phone") private var bizPhone: String = ""
    @AppStorage("biz.email") private var bizEmail: String = ""
    @AppStorage("biz.logoBase64") private var bizLogoBase64: String = ""
    @AppStorage("cust.name") private var custName: String = ""
    @AppStorage("cust.address") private var custAddress: String = ""
    @AppStorage("cust.address2") private var custAddress2: String = ""
    @AppStorage("cust.cityStateZip") private var custCityStateZip: String = ""
    @AppStorage("cust.phone") private var custPhone: String = ""
    @AppStorage("cust.email") private var custEmail: String = ""

    @State private var showCustomer = false
    @State private var askForCustomer = false
    @State private var pdf: NDPDF? = nil
    @State private var notice: String? = nil

    private struct NDPDF: Identifiable {
        let id = UUID()
        let data: Data
        let url: URL
    }

    private var totals: EstimateTotals {
        computeTotals(document: store.doc, rates: store.rates,
                      shippingEnabled: shippingEnabled, shipping: exportShipping,
                      taxPercent: taxPercent)
    }

    private var hasMaterials: Bool {
        store.doc.rooms.contains { $0.sections.contains { !$0.additionsMaterials.isEmpty } }
    }

    var body: some View {
        let t = totals
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Review before sending").font(.ndTitle(26))
                    warnings(t)
                    customerCard
                    ForEach(t.sections, id: \.section.id) { item in
                        areaCard(item)
                    }
                    chargesCard
                    totalsBlock(t)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            footer.modifier(NDHiddenWhileTyping())
        }
        .background(ND.ground.ignoresSafeArea())
        .foregroundStyle(ND.text)
        .navigationTitle(Text(verbatim: "Estimate #\(estimateCounter + 1)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ND.ground, for: .navigationBar)
        .ndKeyboardDone()
        .sheet(isPresented: $showCustomer) { NDCustomerSheet() }
        .sheet(item: $pdf) { p in
            NavigationStack {
                PDFKitPreview(data: p.data, onTap: {})
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Estimate PDF")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { pdf = nil } }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                let url = p.url
                                pdf = nil
                                presentPDFShareSheet(url: url)
                            } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("No customer on this estimate", isPresented: $askForCustomer, titleVisibility: .visible) {
            Button("Add customer details") { showCustomer = true }
            Button("Create PDF anyway") { createPDF() }
        } message: {
            Text("The PDF will have a blank customer section.")
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Parts

    @ViewBuilder
    private func warnings(_ t: EstimateTotals) -> some View {
        ForEach(t.sections, id: \.section.id) { item in
            let list = NDAreaText.warnings(item.section)
            if let first = list.first {
                NDWarning(title: "\(item.room.name) · \(item.section.area?.rawValue ?? "New area")",
                          message: list.count > 1 ? "\(first) (and \(list.count - 1) more)" : first,
                          actionTitle: "Fix",
                          action: {
                              let step = item.section.area == nil ? 0 : (isSectionReady(item.section) ? 2 : 1)
                              onEditArea(item.room.id, item.section.id, step)
                          })
            }
        }
    }

    private var customerCard: some View {
        Button { showCustomer = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle").font(.system(size: 26)).foregroundStyle(ND.link)
                VStack(alignment: .leading, spacing: 2) {
                    Text(custName.isEmpty ? "Add customer" : custName).font(.system(size: 16, weight: .semibold))
                    Text(custName.isEmpty ? "Name, address and contact for the PDF"
                         : [custAddress, custCityStateZip].filter { !$0.isEmpty }.joined(separator: ", "))
                        .font(.system(size: 13)).foregroundStyle(ND.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ND.muted)
            }
            .padding(14)
            .background(ND.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ND.border))
        }
        .buttonStyle(.plain)
    }

    private func areaCard(_ item: SectionPrice) -> some View {
        Button { onEditArea(item.room.id, item.section.id, 4) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(item.room.name) · \(item.section.area?.rawValue ?? "New area")")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text(ND.money(item.subtotal)).font(.system(size: 17, weight: .bold).monospacedDigit())
                }
                ForEach(item.core.lines) { line in
                    HStack(alignment: .top) {
                        Text(line.label).font(.system(size: 14)).foregroundStyle(ND.secondary)
                        Spacer(minLength: 12)
                        Text(ND.money(line.amount)).font(.system(size: 14).monospacedDigit())
                    }
                }
                ForEach(item.section.additionsLabor + item.section.additionsMaterials) { add in
                    HStack(alignment: .top) {
                        Text(add.activity.isEmpty ? "Other charge" : add.activity)
                            .font(.system(size: 14)).foregroundStyle(ND.secondary)
                        Spacer(minLength: 12)
                        Text(ND.money(add.amount)).font(.system(size: 14).monospacedDigit())
                    }
                }
            }
            .padding(14)
            .background(ND.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ND.border))
            .foregroundStyle(ND.text)
        }
        .buttonStyle(.plain)
    }

    private var chargesCard: some View {
        NDCard {
            VStack(alignment: .leading, spacing: 12) {
                NDLabel("Charges")
                LabeledContent("Tax on taxable materials (%)") {
                    NDNumberField(placeholder: "0", value: $taxPercent, alignment: .trailing).frame(width: 100)
                }
                .font(.system(size: 15))
                if hasMaterials {
                    Toggle("Charge shipping", isOn: $shippingEnabled).font(.system(size: 15))
                    if shippingEnabled {
                        LabeledContent("Shipping") {
                            NDNumberField(placeholder: "0", value: $exportShipping, alignment: .trailing).frame(width: 100)
                        }
                        .font(.system(size: 15))
                    }
                }
                Toggle("Fit PDF on one page", isOn: $forceSinglePage).font(.system(size: 15))
            }
            .padding(14)
        }
    }

    private func totalsBlock(_ t: EstimateTotals) -> some View {
        VStack(spacing: 8) {
            row("Subtotal", t.subtotal)
            if t.shipping > 0 { row("Shipping", t.shipping) }
            if t.tax > 0 { row("Tax (\(ND.number(t.taxPercent))%)", t.tax) }
            Divider().overlay(ND.border)
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(.ndTitle(20))
                Spacer()
                Text(ND.money(t.grandTotal)).font(.system(size: 30, weight: .bold).monospacedDigit())
            }
        }
        .padding(.horizontal, 4)
    }

    private func row(_ title: String, _ v: Double) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(ND.secondary)
            Spacer()
            Text(ND.money(v)).font(.system(size: 15).monospacedDigit())
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                NDEstimateActions.save(store: store, saved: saved, totals: totals)
                notice = "Estimate saved."
            } label: {
                Text("Save")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ND.secondary)
                    .frame(width: 96, height: 52)
                    .background(ND.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Button {
                if custName.trimmingCharacters(in: .whitespaces).isEmpty { askForCustomer = true } else { createPDF() }
            } label: {
                Label("Create PDF", systemImage: "doc.text")
            }
            .buttonStyle(NDPrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ND.footer.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(ND.border) }
    }

    // MARK: PDF

    private func createPDF() {
        let biz = PartyInfo(name: bizName, address: bizAddress, address2: bizAddress2,
                            cityStateZip: bizCityStateZip, phone: bizPhone, email: bizEmail)
        let cust = PartyInfo(name: custName, address: custAddress, address2: custAddress2,
                             cityStateZip: custCityStateZip, phone: custPhone, email: custEmail)
        let number = estimateCounter + 1
        do {
            let (data, url) = try EstimatePDF.make(
                document: store.doc,
                totals: totals,
                biz: biz,
                cust: cust,
                logo: decodeBase64Image(bizLogoBase64),
                estimateNumber: number,
                forceSinglePage: forceSinglePage,
                fallbackDescription: ""
            )
            estimateCounter = number
            pdf = NDPDF(data: data, url: url)
        } catch {
            notice = "The PDF couldn't be created: \(error.localizedDescription)"
        }
    }
}
