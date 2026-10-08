import SwiftUI

/// Where the new design can navigate to.
enum NDRoute: Hashable {
    case area(room: UUID, section: UUID, step: Int)
    case review
}

/// The new design's home: the estimate at a glance, with rooms and areas.
/// It reads and writes the same saved estimate as the classic design.
struct NewEstimateView: View {
    @StateObject private var store = Store()
    @ObservedObject private var saved = SavedEstimatesStore.shared
    @State private var path: [NDRoute] = []

    @State private var showAdmin = false
    @State private var showCustomer = false
    @State private var showSaved = false
    @State private var confirmNew = false
    @State private var roomPrompt: RoomPrompt? = nil
    @State private var roomToDelete: EstimateRoom? = nil
    /// A room just added: how it's to be measured.
    @State private var askMeasure: RoomRef? = nil
    @State private var scanningRoom: RoomRef? = nil
    @State private var calibratingRoom: RoomRef? = nil
    @State private var pendingFirstArea: UUID? = nil

    /// A room to act on; `newRoom` when it was just added (its first area
    /// starts once it's scanned).
    private struct RoomRef: Identifiable {
        let id: UUID
        var newRoom = false
    }
    @State private var notice: String? = nil

    @AppStorage(DesignPreference.key) private var useNewDesign = true
    @AppStorage("estimate.counter") private var estimateCounter: Int = 1400
    @AppStorage("export.shipping") private var exportShipping: Double = 0.0
    @AppStorage("export.taxPercent") private var exportTaxPercent: Double = 0.0
    @AppStorage("additions.shippingEnabled") private var shippingEnabled: Bool = false
    @AppStorage("export.forceSinglePage") private var forceSinglePage: Bool = false
    @AppStorage("cust.name") private var custName: String = ""
    @AppStorage("cust.cityStateZip") private var custCityStateZip: String = ""

    private struct RoomPrompt: Identifiable {
        let id = UUID()
        var roomID: UUID?        // nil = new room
        var name: String
    }

    private var totals: EstimateTotals {
        computeTotals(document: store.doc, rates: store.pricingRates,
                      shippingEnabled: shippingEnabled, shipping: exportShipping,
                      taxPercent: exportTaxPercent)
    }

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .navigationDestination(for: NDRoute.self) { route in
                    switch route {
                    case let .area(room, section, step):
                        AreaFlowView(store: store, roomID: room, sectionID: section, startStep: step,
                                     onFinish: { path.removeAll() })
                    case .review:
                        EstimateReviewView(store: store, saved: saved,
                                           onEditArea: { room, section, step in
                                               path.append(.area(room: room, section: section, step: step))
                                           })
                    }
                }
        }
        .tint(ND.link)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdmin) {
            AdminGate(rates: $store.rates, taxDefault: $exportTaxPercent)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showCustomer) { NDCustomerSheet() }
        .sheet(isPresented: $showSaved) {
            NDSavedEstimatesSheet(saved: saved) { e in
                NDEstimateActions.load(e, into: store)
                showSaved = false
                path.removeAll()
            }
        }
        .alert(roomPrompt?.roomID == nil ? "Add room" : "Rename room",
               isPresented: Binding(get: { roomPrompt != nil }, set: { if !$0 { roomPrompt = nil } })) {
            TextField("Room name", text: Binding(get: { roomPrompt?.name ?? "" },
                                                 set: { roomPrompt?.name = $0 }))
            Button("Cancel", role: .cancel) { roomPrompt = nil }
            Button("Save") { commitRoomPrompt() }
        }
        .confirmationDialog("How do you want to measure \(roomName(askMeasure?.id))?",
                            isPresented: Binding(get: { askMeasure != nil }, set: { if !$0 { askMeasure = nil } }),
                            titleVisibility: .visible, presenting: askMeasure) { ref in
            if RoomScanner.isAvailable {
                Button("Scan the room") { scanningRoom = ref }
            }
            #if DEBUG
            if !RoomScanner.isAvailable {
                Button("Use a sample room (no LiDAR here)") { finishRoomScan(ScannedRoom.sample.turned(by: 27), ref) }
            }
            #endif
            Button("Enter measurements by hand") { askMeasure = nil }
        } message: { _ in
            Text("Scan it and choose what's tiled on the model, or type the measurements as before.")
        }
        .fullScreenCover(item: $scanningRoom) { ref in
            RoomScanCover { room in finishRoomScan(room, ref) }
        }
        .sheet(item: $calibratingRoom, onDismiss: startFirstArea) { ref in
            if let r = store.doc.rooms.firstIndex(where: { $0.id == ref.id }), let scan = store.doc.rooms[r].scan {
                CalibrateScanSheet(room: scan, onApply: { c in
                    if let r = store.doc.rooms.firstIndex(where: { $0.id == ref.id }), let scan = store.doc.rooms[r].scan {
                        store.doc.rooms[r].scan = scan.calibrated(c)
                    }
                }, onUndo: nil, afterScan: true)
            }
        }
        .confirmationDialog("Start a new estimate?", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("Clear this estimate", role: .destructive) { store.reset() }
        } message: {
            Text("This clears the rooms and areas you're working on. Saved estimates are not affected.")
        }
        .confirmationDialog("Delete \(roomToDelete?.name ?? "room")?",
                            isPresented: Binding(get: { roomToDelete != nil }, set: { if !$0 { roomToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete room and its areas", role: .destructive) {
                if let r = roomToDelete { store.doc.rooms.removeAll { $0.id == r.id } }
                roomToDelete = nil
            }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Overview

    private var overview: some View {
        let t = totals
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    OpenedPricingBanner(store: store) {
                        computeTotals(document: store.doc, rates: $0, shippingEnabled: shippingEnabled,
                                      shipping: exportShipping, taxPercent: exportTaxPercent)
                    }
                    totalCard(t)
                    if store.doc.rooms.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.doc.rooms) { room in
                            roomBlock(room, totals: t)
                        }
                        Button { roomPrompt = RoomPrompt(roomID: nil, name: "Room \(store.doc.rooms.count + 1)") } label: {
                            Label("Add room", systemImage: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(ND.secondary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(ND.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            footer
        }
        .background(ND.ground.ignoresSafeArea())
        .foregroundStyle(ND.text)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                NDLabel("Estimate #\(estimateCounter + 1)")
                Button { showCustomer = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(custName.isEmpty ? "New estimate" : custName)
                            .font(.ndTitle(28))
                            .foregroundStyle(ND.text)
                            .multilineTextAlignment(.leading)
                        Label(custName.isEmpty ? "Add customer details" : (custCityStateZip.isEmpty ? "Customer details" : custCityStateZip),
                              systemImage: "person")
                            .font(.system(size: 15))
                            .foregroundStyle(custName.isEmpty ? ND.link : ND.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button { showCustomer = true } label: { Label("Customer details", systemImage: "person") }
                Button { save() } label: { Label("Save estimate", systemImage: "square.and.arrow.down") }
                Button { showSaved = true } label: { Label("Saved estimates", systemImage: "folder") }
                Button { showAdmin = true } label: { Label("Admin", systemImage: "gearshape") }
                Divider()
                Button { useNewDesign = false } label: { Label("Switch to classic design", systemImage: "arrow.uturn.backward") }
                Button(role: .destructive) { confirmNew = true } label: { Label("Start new estimate", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ND.text)
                    .frame(width: 44, height: 44)
                    .background(ND.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ND.border))
            }
            .accessibilityLabel("More")
        }
    }

    private func totalCard(_ t: EstimateTotals) -> some View {
        let installation = t.sections.reduce(0) { $0 + $1.core.total }
        let extras = t.sections.reduce(0) { $0 + $1.labor + $1.mats }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                NDLabel("Estimate total")
                Spacer()
                Text("before tax").font(.system(size: 13)).foregroundStyle(ND.muted)
            }
            Text(ND.money(t.subtotal))
                .font(.system(size: 44, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                miniTotal("Installation", installation)
                miniTotal("Extras & materials", extras)
            }
        }
        .padding(18)
        .background(ND.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ND.border))
    }

    private func miniTotal(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(ND.muted)
            Text(ND.money(value)).font(.system(size: 17, weight: .semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ND.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        NDCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Start with a room").font(.ndTitle(20))
                Text("Add a room, then the areas you're tiling in it: a shower, a floor, a backsplash.")
                    .font(.system(size: 15))
                    .foregroundStyle(ND.secondary)
                Button("Add room") { roomPrompt = RoomPrompt(roomID: nil, name: "Room 1") }
                    .buttonStyle(NDPrimaryButtonStyle())
            }
            .padding(18)
        }
    }

    private func roomBlock(_ room: EstimateRoom, totals t: EstimateTotals) -> some View {
        let roomTotal = t.sections.filter { $0.room.id == room.id }.reduce(0) { $0 + $1.subtotal }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    Button { roomPrompt = RoomPrompt(roomID: room.id, name: room.name) } label: { Label("Rename", systemImage: "pencil") }
                    if RoomScanner.isAvailable {
                        Button { scanningRoom = RoomRef(id: room.id) } label: {
                            Label(room.scan == nil ? "Scan this room" : "Scan the room again", systemImage: "viewfinder")
                        }
                    }
                    Button(role: .destructive) { roomToDelete = room } label: { Label("Delete room", systemImage: "trash") }
                } label: {
                    HStack(spacing: 6) {
                        Text(room.name).font(.ndTitle(19))
                        if room.scan != nil {
                            Image(systemName: "viewfinder").font(.system(size: 13, weight: .semibold)).foregroundStyle(ND.link)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(ND.muted)
                    }
                    .foregroundStyle(ND.text)
                }
                Spacer()
                Text(ND.money(roomTotal))
                    .font(.system(size: 16, weight: .medium).monospacedDigit())
                    .foregroundStyle(ND.secondary)
            }

            if !room.sections.isEmpty {
                NDCard {
                    ForEach(Array(room.sections.enumerated()), id: \.element.id) { i, sec in
                        if i > 0 { Divider().overlay(ND.border) }
                        areaRow(room: room, section: sec, totals: t)
                    }
                }
            }

            Button {
                let sec = EstimateSection()
                if let r = store.doc.rooms.firstIndex(where: { $0.id == room.id }) {
                    store.doc.rooms[r].sections.append(sec)
                    path.append(.area(room: room.id, section: sec.id, step: 0))
                }
            } label: {
                Label("Add area to \(room.name)", systemImage: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ND.link)
        }
    }

    private func areaRow(room: EstimateRoom, section sec: EstimateSection, totals t: EstimateTotals) -> some View {
        let price = t.sections.first { $0.section.id == sec.id }?.subtotal ?? 0
        let warnings = NDAreaText.warnings(sec)
        return NavigationLink(value: NDRoute.area(room: room.id, section: sec.id, step: isSectionReady(sec) ? 2 : 0)) {
            HStack(spacing: 12) {
                NDAreaIcon(area: sec.area, size: 18)
                    .foregroundStyle(ND.link)
                    .frame(width: 40, height: 40)
                    .background(ND.selectedBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sec.area?.rawValue ?? "New area").font(.system(size: 16, weight: .semibold))
                    if let w = warnings.first {
                        Label(w, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(ND.warning)
                            .lineLimit(1)
                    } else {
                        Text(NDAreaText.summary(sec))
                            .font(.system(size: 13))
                            .foregroundStyle(ND.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(ND.money(price)).font(.system(size: 16, weight: .semibold).monospacedDigit())
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ND.muted)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                if let r = store.doc.rooms.firstIndex(where: { $0.id == room.id }) {
                    store.doc.rooms[r].sections.removeAll { $0.id == sec.id }
                }
            } label: { Label("Delete area", systemImage: "trash") }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { showSaved = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "folder").font(.system(size: 18))
                    Text("Estimates").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(ND.secondary)
                .frame(width: 96, height: 52)
                .background(ND.raised)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { path.append(.review) } label: {
                Label("Review & create PDF", systemImage: "doc.text")
            }
            .buttonStyle(NDPrimaryButtonStyle())
            .disabled(store.doc.rooms.isEmpty)
            .opacity(store.doc.rooms.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ND.footer.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(ND.border) }
    }

    // MARK: - Actions

    private func commitRoomPrompt() {
        guard let p = roomPrompt else { return }
        let name = p.name.trimmingCharacters(in: .whitespaces)
        if let id = p.roomID, let i = store.doc.rooms.firstIndex(where: { $0.id == id }) {
            store.doc.rooms[i].name = name.isEmpty ? store.doc.rooms[i].name : name
        } else {
            let room = EstimateRoom(name: name.isEmpty ? "Room \(store.doc.rooms.count + 1)" : name)
            store.doc.rooms.append(room)
            // Scan it, or measure by hand (owner's flow, 2026-10-08).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { askMeasure = RoomRef(id: room.id, newRoom: true) }
        }
        roomPrompt = nil
    }

    private func roomName(_ id: UUID?) -> String {
        store.doc.rooms.first { $0.id == id }?.name ?? "the room"
    }

    /// A scan kept on its room; then the offer to calibrate it.
    private func finishRoomScan(_ scan: ScannedRoom, _ ref: RoomRef) {
        guard let r = store.doc.rooms.firstIndex(where: { $0.id == ref.id }) else { return }
        store.doc.rooms[r].scan = scan
        pendingFirstArea = ref.newRoom ? ref.id : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { calibratingRoom = ref }
    }

    /// After a new room's scan (calibrated or not): its first area, on the
    /// same Area screen as by hand.
    private func startFirstArea() {
        guard let id = pendingFirstArea, let r = store.doc.rooms.firstIndex(where: { $0.id == id }) else { return }
        pendingFirstArea = nil
        let sec = EstimateSection()
        store.doc.rooms[r].sections.append(sec)
        path.append(.area(room: id, section: sec.id, step: 0))
    }

    private func save() {
        guard !store.doc.rooms.isEmpty else { notice = "Add a room before saving."; return }
        NDEstimateActions.save(store: store, saved: saved, totals: totals)
        notice = "Estimate saved."
    }
}

// MARK: - Words for an area

enum NDAreaText {
    /// Why an area is not priced yet, or what is missing from its price.
    static func warnings(_ sec: EstimateSection) -> [String] {
        if sec.area == nil { return ["Choose what's being tiled"] }
        if !isSectionReady(sec) { return ["Choose the tile to price this area"] }
        return missingSizeWarnings(sec).map { $0.replacingOccurrences(of: ": no size adder charged.", with: "") }
    }

    /// One line under the area's name.
    static func summary(_ sec: EstimateSection) -> String {
        guard let area = sec.area else { return "Not set up yet" }
        var parts: [String] = []
        if let tile = sec.ndMainTile, sec.walls.isEmpty { parts.append(tile.ndSummary) }
        switch area {
        case .shower:
            if !sec.walls.isEmpty { parts.append("\(sec.walls.count) walls") }
            else if sec.measurements.showerWallsSqft > 0 { parts.append("\(ND.number(sec.measurements.showerWallsSqft)) sq ft walls") }
            if sec.showerFloorTile != nil { parts.append("own floor tile") }
        case .tub:
            if !sec.walls.isEmpty { parts.append("\(sec.walls.count) walls") }
            else if sec.measurements.sqft > 0 { parts.append("\(ND.number(sec.measurements.sqft)) sq ft") }
        default:
            if sec.measurements.sqft > 0 { parts.append("\(ND.number(sec.measurements.sqft)) sq ft") }
        }
        let f = sec.features
        let builtIns = area == .floor ? 0 : f.niches + f.shelves + f.benches + f.footrests
        if builtIns > 0 { parts.append("\(builtIns) built-in\(builtIns == 1 ? "" : "s")") }
        if sec.radiantHeat != nil, area == .floor || area == .shower { parts.append("radiant heat") }
        for kind in DecorativeKind.allCases {
            let n = sec.decoratives.filter { $0.kind == kind }.count
            if n > 0 { parts.append("\(n) \(kind.rawValue.lowercased())\(n == 1 ? "" : "s")") }
        }
        return parts.isEmpty ? "Not measured yet" : parts.joined(separator: " · ")
    }
}

// MARK: - Saving and loading (the same fields the classic design uses)

enum NDEstimateActions {
    static func save(store: Store, saved: SavedEstimatesStore, totals: EstimateTotals) {
        let d = UserDefaults.standard
        func s(_ k: String) -> String { d.string(forKey: k) ?? "" }
        let custName = s("cust.name")
        let firstTitle: String = {
            if let room = store.doc.rooms.first, let area = room.sections.first?.area?.rawValue {
                let name = room.name.isEmpty ? "Room 1" : room.name
                return "\(custName.isEmpty ? "Untitled" : custName) – \(name) \(area)"
            }
            return custName.isEmpty ? "Untitled Estimate" : custName
        }()
        saved.add(SavedEstimate(
            title: firstTitle,
            estimateNumber: d.integer(forKey: "estimate.counter"),
            biz: PartyInfo(name: s("biz.name"), address: s("biz.address"), address2: s("biz.address2"),
                           cityStateZip: s("biz.cityStateZip"), phone: s("biz.phone"), email: s("biz.email")),
            cust: PartyInfo(name: custName, address: s("cust.address"), address2: s("cust.address2"),
                            cityStateZip: s("cust.cityStateZip"), phone: s("cust.phone"), email: s("cust.email")),
            shipping: totals.shipping,
            taxPercent: d.double(forKey: "export.taxPercent"),
            forceSinglePage: d.bool(forKey: "export.forceSinglePage"),
            document: store.doc,
            rates: store.pricingRates,
            total: totals.grandTotal,
            templateID: EstimateTemplate.chosenID
        ))
    }

    static func load(_ e: SavedEstimate, into store: Store) {
        let d = UserDefaults.standard
        let parties: [(String, PartyInfo)] = [("biz", e.biz), ("cust", e.cust)]
        for (prefix, p) in parties {
            d.set(p.name, forKey: "\(prefix).name")
            d.set(p.address, forKey: "\(prefix).address")
            d.set(p.address2, forKey: "\(prefix).address2")
            d.set(p.cityStateZip, forKey: "\(prefix).cityStateZip")
            d.set(p.phone, forKey: "\(prefix).phone")
            d.set(p.email, forKey: "\(prefix).email")
        }
        d.set(e.shipping, forKey: "export.shipping")
        d.set(e.taxPercent, forKey: "export.taxPercent")
        d.set(e.forceSinglePage, forKey: "export.forceSinglePage")
        d.set(e.shipping > 0, forKey: "additions.shippingEnabled")
        store.open(e)
        store.state.stepIndex = 0
    }
}

// MARK: - Sheets

struct NDCustomerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cust.name") private var name: String = ""
    @AppStorage("cust.address") private var address: String = ""
    @AppStorage("cust.address2") private var address2: String = ""
    @AppStorage("cust.cityStateZip") private var cityStateZip: String = ""
    @AppStorage("cust.phone") private var phone: String = ""
    @AppStorage("cust.email") private var email: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $name).textContentType(.name)
                    TextField("Address", text: $address).textContentType(.streetAddressLine1)
                    TextField("Address line 2", text: $address2).textContentType(.streetAddressLine2)
                    TextField("City, State, Zip", text: $cityStateZip)
                }
                Section("Contact") {
                    TextField("Phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("Email", text: $email).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .navigationTitle("Customer details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct NDSavedEstimatesSheet: View {
    @ObservedObject var saved: SavedEstimatesStore
    let onLoad: (SavedEstimate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var toLoad: SavedEstimate? = nil

    var body: some View {
        NavigationStack {
            List {
                if let problem = saved.loadProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if saved.items.isEmpty && saved.loadProblem == nil {
                    Text("No saved estimates yet.").foregroundStyle(.secondary)
                }
                ForEach(saved.items) { e in
                    Button { toLoad = e } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.title).font(.headline)
                                Spacer()
                                Text("#\(e.estimateNumber)").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(e.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                if let total = e.total { Text(currencyString(total)) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { saved.delete(at: $0) }
            }
            .navigationTitle("Saved estimates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !saved.items.isEmpty { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            }
            .confirmationDialog("Open \(toLoad?.title ?? "estimate")?",
                                isPresented: Binding(get: { toLoad != nil }, set: { if !$0 { toLoad = nil } }),
                                titleVisibility: .visible) {
                Button("Open and replace current estimate") { if let e = toLoad { onLoad(e) } }
            } message: {
                Text("The estimate you're working on will be replaced. Save it first if you want to keep it.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
