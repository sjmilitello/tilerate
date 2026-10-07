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
    @State private var choosingPictures = false

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
            .sheet(isPresented: $choosingPictures) {
                NDPicturesSheet(store: store, layout: current)
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
            if !NDPicturesSheet.scannedAreas(store).isEmpty {
                let chosen = store.doc.pictures.filter(\.included).count
                Button { choosingPictures = true } label: {
                    Label(chosen == 0 ? "3-D views" : "3-D views (\(chosen))" + (current.include3DViews ? "" : " · off in this layout"),
                          systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NDSecondaryButtonStyle())
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
                                                   forceSinglePage: forceSinglePage,
                                                   pictures: NDPicturesSheet.pdfPictures(store))
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


/// Choosing the 3-D views that go with the PDF: for each scanned area its
/// standard views (into the area, the whole room) and any saved from the
/// 3-D view with "Add to estimate", each ticked in or out.
struct NDPicturesSheet: View {
    @ObservedObject var store: Store
    let layout: EstimateTemplate
    @Environment(\.dismiss) private var dismiss

    /// Areas of the estimate measured from a scan.
    static func scannedAreas(_ store: Store) -> [(room: EstimateRoom, section: EstimateSection)] {
        store.doc.rooms.flatMap { r in
            r.sections.filter { ($0.roomScan ?? r.scan) != nil && $0.scanTakeoff != nil }.map { (r, $0) }
        }
    }

    /// The chosen views, in order, ready to draw on the PDF.
    static func pdfPictures(_ store: Store) -> [PDFPicture] {
        let rates = store.pricingRates
        return store.doc.pictures.filter(\.included).compactMap { p in
            guard let (room, section) = scannedAreas(store).first(where: { $0.section.id == p.sectionID }) else { return nil }
            let caption = [room.name, section.area?.rawValue, p.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return PDFPicture(caption: caption) { size in
                guard let c = Room3DContent.of(room: room, section: section, rates: rates, fixtures: p.fixtures) else { return nil }
                return Room3DScene.picture(c, eye: p.eye, target: p.target, size: size)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !layout.include3DViews {
                    Section {
                        Text("\(layout.name) leaves 3-D views out. They go in the PDF with layouts that have \"3-D views of the job\" on.")
                            .font(.footnote)
                        if store.rates.estimateTemplates.contains(where: { $0.id == layout.id }) {
                            Button("Turn on 3-D views for \(layout.name)") {
                                if let i = store.rates.estimateTemplates.firstIndex(where: { $0.id == layout.id }) {
                                    store.rates.estimateTemplates[i].include3DViews = true
                                }
                            }
                        }
                    }
                }
                ForEach(Self.scannedAreas(store), id: \.section.id) { room, section in
                    Section("\(room.name.isEmpty ? "" : room.name + " · ")\(section.area?.rawValue ?? "Area")") {
                        ForEach(standard(section), id: \.self) { name in
                            row(name: name, section: section, room: room)
                        }
                        ForEach(store.doc.pictures.filter { $0.sectionID == section.id && !standard(section).contains($0.name) }) { p in
                            row(name: p.name, section: section, room: room)
                        }
                        .onDelete { offsets in
                            let mine = store.doc.pictures.filter { $0.sectionID == section.id && !standard(section).contains($0.name) }
                            let ids = Set(offsets.map { mine[$0].id })
                            store.doc.pictures.removeAll { ids.contains($0.id) }
                        }
                    }
                }
                Section {
                    Text("Turn a view the way you want it in the area's 3-D view (Measure → Adjust on the plan → 3D) and tap Add to estimate to add your own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("3-D views")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func standard(_ s: EstimateSection) -> [String] {
        [s.area == .shower ? "Shower" : (s.area?.rawValue ?? "This area"), "Whole room"]
    }

    private func row(name: String, section: EstimateSection, room: EstimateRoom) -> some View {
        let existing = store.doc.pictures.first { $0.sectionID == section.id && $0.name == name }
        let on = existing?.included ?? false
        return Button {
            if let i = store.doc.pictures.firstIndex(where: { $0.sectionID == section.id && $0.name == name }) {
                store.doc.pictures[i].included.toggle()
            } else if let c = Room3DContent.of(room: room, section: section, rates: store.pricingRates) {
                let cam = Room3DScene.standard(name == "Whole room" ? .room : .area, content: c)
                store.doc.pictures.append(EstimatePicture(sectionID: section.id, name: name, eye: cam.eye, target: cam.target))
            }
        } label: {
            HStack(spacing: 12) {
                PictureThumb(room: room, section: section, picture: existing, standardName: name, rates: store.pricingRates)
                    .frame(width: 96, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(name).foregroundStyle(.primary)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .font(.title3)
            }
        }
    }
}

/// A small picture of a 3-D view, drawn once.
private struct PictureThumb: View {
    let room: EstimateRoom
    let section: EstimateSection
    let picture: EstimatePicture?
    let standardName: String
    let rates: Rates
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Color(white: 0.9)
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { ProgressView() }
        }
        .task {
            guard image == nil, let c = Room3DContent.of(room: room, section: section, rates: rates,
                                                         fixtures: picture?.fixtures ?? true) else { return }
            let cam = picture.map { ($0.eye, $0.target) }
                ?? { let s = Room3DScene.standard(standardName == "Whole room" ? .room : .area, content: c); return (s.eye, s.target) }()
            image = Room3DScene.picture(c, eye: cam.0, target: cam.1, size: CGSize(width: 288, height: 192))
        }
    }
}
