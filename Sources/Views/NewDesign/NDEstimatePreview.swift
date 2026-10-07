import SwiftUI

/// The finished estimate before it goes out (roadmap Phase 4): drawn in each
/// layout, swiped through left and right, starting on the one chosen for the
/// estimate (the default, ★, unless another was chosen). Tapping an area's
/// description edits its wording on this estimate. "Use this layout" chooses
/// the one on screen for this estimate; "Make default" for new estimates.
struct NDEstimatePreview: View {
    @ObservedObject var store: Store
    let totals: () -> EstimateTotals
    let biz: PartyInfo
    let cust: PartyInfo
    let logo: UIImage?
    let estimateNumber: Int
    let forceSinglePage: Bool
    /// Called with the PDF in the layout on screen, which is then chosen for
    /// the estimate.
    let onShare: (Data, URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(EstimateTemplate.chosenKey) private var chosenLayout: String = ""
    @State private var page: UUID = EstimateTemplate.classicID
    @State private var editing: EstimateSection? = nil
    @State private var notice: String? = nil

    private var layouts: [EstimateTemplate] { store.pricingRates.estimateTemplates }
    private var defaultID: UUID { store.rates.defaultTemplateID }
    private var chosenID: UUID { store.pricingRates.template(UUID(uuidString: chosenLayout)).id }
    private var current: EstimateTemplate { layouts.first { $0.id == page } ?? store.pricingRates.template(nil) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(layouts) { layout in
                        GeometryReader { geo in
                            ScrollView {
                                EstimatePDF.view(totals: totals(), template: layout, biz: biz, cust: cust,
                                                 logo: logo, estimateNumber: estimateNumber,
                                                 onEditWording: { id in editing = section(id) })
                                    .environment(\.colorScheme, .light)
                                    .frame(width: 612)
                                    .scaleEffect(geo.size.width / 612, anchor: .topLeading)
                                    .frame(width: geo.size.width, height: pageHeight(layout) * geo.size.width / 612,
                                           alignment: .topLeading)
                                    .shadow(color: .black.opacity(0.25), radius: 6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .tag(layout.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                footer
            }
            .background(ND.ground.ignoresSafeArea())
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: $editing) { section in
                NDWordingSheet(section: section, wording: store.pricingRates.wording,
                               onSave: { text in update(section.id) { $0.setWording(text, wording: store.pricingRates.wording) } },
                               onUseGenerated: { update(section.id) { $0.customWording = nil } })
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { page = chosenID }
    }

    /// The layout's name, ★ for the default, a dot for each layout.
    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if current.id == defaultID { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                Text(current.name).font(.system(size: 17, weight: .semibold))
                if current.id == chosenID && current.id != defaultID {
                    Text("· this estimate").font(.system(size: 15)).foregroundStyle(ND.secondary)
                }
            }
            HStack(spacing: 7) {
                ForEach(layouts) { l in
                    Circle().fill(l.id == page ? ND.text : ND.secondary.opacity(0.4)).frame(width: 7, height: 7)
                }
            }
            Text("Swipe for other layouts · tap a description to change its wording")
                .font(.system(size: 12)).foregroundStyle(ND.secondary)
        }
        .foregroundStyle(ND.text)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    chosenLayout = current.id.uuidString
                } label: {
                    Label(current.id == chosenID ? "Used for this estimate" : "Use this layout",
                          systemImage: current.id == chosenID ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NDSecondaryButtonStyle())
                .disabled(current.id == chosenID)

                Button {
                    makeDefault(current)
                } label: {
                    Label(current.id == defaultID ? "Default" : "Make default",
                          systemImage: current.id == defaultID ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NDSecondaryButtonStyle())
                .disabled(current.id == defaultID)
            }
            Button {
                share()
            } label: {
                Label("Share \(current.name) PDF", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NDPrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ND.footer.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(ND.border) }
    }

    /// The page's height at full size, to give the scaled page its room.
    private func pageHeight(_ layout: EstimateTemplate) -> CGFloat {
        let host = UIHostingController(rootView: EstimatePDF.view(totals: totals(), template: layout, biz: biz, cust: cust,
                                                                  logo: logo, estimateNumber: estimateNumber)
            .environment(\.colorScheme, .light))
        let size = host.sizeThatFits(in: CGSize(width: 612, height: CGFloat.greatestFiniteMagnitude))
        return max(792, size.height)
    }

    private func makeDefault(_ layout: EstimateTemplate) {
        // A layout from an estimate saved with older rates may not be in the
        // current list yet.
        if !store.rates.estimateTemplates.contains(where: { $0.id == layout.id }) {
            store.rates.estimateTemplates.append(layout)
        }
        store.rates.defaultTemplateID = layout.id
        notice = "New estimates will start with \(layout.name). You can change this in Admin → Estimate layouts."
    }

    private func share() {
        chosenLayout = current.id.uuidString
        do {
            let (data, url) = try EstimatePDF.make(totals: totals(), template: current, biz: biz, cust: cust,
                                                   logo: logo, estimateNumber: estimateNumber,
                                                   forceSinglePage: forceSinglePage)
            dismiss()
            onShare(data, url)
        } catch {
            notice = "The PDF couldn't be created: \(error.localizedDescription)"
        }
    }

    private func section(_ id: UUID) -> EstimateSection? {
        store.doc.rooms.lazy.flatMap(\.sections).first { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout EstimateSection) -> Void) {
        for r in store.doc.rooms.indices {
            if let i = store.doc.rooms[r].sections.firstIndex(where: { $0.id == id }) {
                change(&store.doc.rooms[r].sections[i])
                return
            }
        }
    }
}
