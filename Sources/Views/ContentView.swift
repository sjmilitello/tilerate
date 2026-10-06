

//
//  ContentView.swift
//  TileRate Installation Estimator
//
//  Created by Salvatore Militello on 8/20/25.
//
//  SwiftUI view composition for the estimator UI.
//

import SwiftUI
import Foundation
import UIKit
import Photos


// === Shared style for step texts (Rooms, Areas, Buttons) ===
enum StepTextStyle {
    static let font: Font = .headline        // ~17pt semibold, scales with Dynamic Type
    static let color: Color = .primary       // Black in Light Mode, White in Dark Mode
}
private struct StepTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(StepTextStyle.font)
            .foregroundColor(StepTextStyle.color)
    }
}

extension View {
    func stepTextStyle() -> some View {
        self.modifier(StepTextModifier())
    }
}

// MARK: - Activity (Share) Sheet
// ===== Share presenter (imperative UIKit) =====
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}


// MARK: - Robust Share Presenter (Main-Actor + no data races)
@MainActor
private func presentSystemShareSheet(for url: URL, pdfData: Data? = nil) {
    // Build the items array: PDF URL + (optional) rendered image
    var items: [Any] = [url]
    if let data = pdfData, let img = pdfToImage(data: data) {
        items.append(img)
    }

    // Resolve active scene, key window, and its root VC once (on main actor)
    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let window = scene.windows.first(where: { $0.isKeyWindow }),
        let root   = window.rootViewController
    else { return }

    // Poll on the main actor until the SwiftUI sheet is fully dismissed
    Task { @MainActor in
        var presenter: UIViewController = root

        // Try for ~1.5s (30 * 50ms)
        for _ in 0..<30 {
            if root.presentedViewController == nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        presenter = root.presentedViewController ?? root

        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // iPad popover (harmless on iPhone)
        avc.popoverPresentationController?.sourceView = window
        avc.popoverPresentationController?.sourceRect = CGRect(
            x: window.bounds.midX, y: window.bounds.maxY - 1, width: 1, height: 1
        )

        presenter.present(avc, animated: true)
    }
}
@MainActor
func presentPDFShareSheet(url: URL) {
    guard
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
        let window = scene.windows.first(where: { $0.isKeyWindow }),
        let root   = window.rootViewController
    else { return }

    Task { @MainActor in
        for _ in 0..<30 {
            if root.presentedViewController == nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let presenter = root.presentedViewController ?? root
        let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        avc.popoverPresentationController?.sourceView = window
        avc.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.maxY - 1, width: 1, height: 1)
        presenter.present(avc, animated: true)
    }
}

// MARK: - File-scope helpers
private func intFormatter() -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .none
    f.minimum = 0
    f.maximum = 999
    return f
}

extension Array {
    /// Split array into consecutive chunks of a given size.
    /// If `size <= 0`, returns `[self]`.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var i = 0
        while i < count {
            let end = Swift.min(i + size, count)
            chunks.append(Array(self[i..<end]))
            i = end
        }
        return chunks
    }
}

/// Checkbox + numeric field row
private func quantityRow(_ title: String, value: Binding<Int>, enabled: Bool = true) -> some View {
    let isOn = Binding<Bool>(
        get: { value.wrappedValue > 0 },
        set: { on in
            if on {
                if value.wrappedValue == 0 { value.wrappedValue = 1 }
            } else {
                value.wrappedValue = 0
            }
        }
    )

    return VStack(alignment: .leading, spacing: 8) {
        Toggle("\(title)?", isOn: isOn)
        TextField("0", value: value, formatter: intFormatter())
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .disabled(!isOn.wrappedValue)
            .opacity(isOn.wrappedValue ? 1 : 0.5)
    }
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
}

// Rounded, full‑width numeric field with a title above it
private func measurementField(_ title: String,
                              value: Binding<Double>,
                              enabled: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline).fontWeight(.semibold)
        TextField("0", value: value, formatter: decimalFormatter())
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .disabled(!enabled)
    }
}


/// Toggle + field below it for ceiling input, bound to whether the value > 0.
private func ceilingBlock(title: String,
                          ceilingValue: Binding<Double>,
                          ceilingLabel: String) -> some View {
    let isOn = Binding<Bool>(
        get: { ceilingValue.wrappedValue > 0 },
        set: { on in
            if on {
                if ceilingValue.wrappedValue <= 0 { ceilingValue.wrappedValue = 1 }
            } else {
                ceilingValue.wrappedValue = 0
            }
        }
    )

    return VStack(alignment: .leading, spacing: 8) {
        Toggle(title, isOn: isOn)
        measurementField(ceilingLabel, value: ceilingValue, enabled: isOn.wrappedValue)
            .opacity(isOn.wrappedValue ? 1 : 0.5)
    }
}

/// Simple decimal formatter for sqft fields
private func decimalFormatter() -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    f.minimum = 0
    return f
}
// Used by several places in the UI
private func numberField(_ title: String, value: Binding<Double>) -> some View {
    HStack {
        Text(title)
        Spacer()
        TextField("0", value: value, format: .number)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 140)
    }
}






// MARK: - UI

struct ContentView: View {
    @Binding var rates: Rates
    @Binding var taxDefault: Double
    @StateObject private var store = Store()
    @State private var showAdmin = false
    @State private var showShare = false
    @State private var showShareChoice = false
    @State private var lastTappedPDF: PDFPayload? = nil    // NEW: Export form state
    @State private var showExportForm = false
    @State private var exportPDFURL: URL?
    @State private var pdfData: Data? = nil
    @State private var pendingPDFData: Data? = nil      // ADD
    @State private var pendingPDFURL: URL? = nil
    @State private var showLaborList: Bool = false
    @State private var showSalesList: Bool = false
    @State private var showSaveAlert = false
    @State private var saveAlertMessage = "Saved."
    // === Multi-room selection state ===
    @State private var currentRoomIndex: Int = 0
    @State private var currentSectionIndex: Int = 0
    // --- Rooms selection state (adjust names if yours differ) ---
    
    // --- Room naming / renaming sheet state ---
    @State private var showRoomNameSheet = false
    @State private var isRenamingExistingRoom = false
    @State private var editingRoomIndex: Int? = nil
    @State private var roomNameBuffer: String = ""
    @StateObject private var saved = SavedEstimatesStore()
    @State private var showSavedList = false
    
    
    // === Rooms bar ===
    @ViewBuilder
    private var roomsBar: some View {
        if store.doc.rooms.isEmpty {
            // First room CTA
            HStack {
                Text("Rooms").font(.headline)
                Spacer()
                Button {
                    addRoomPrompt()
                } label: { Text("Add Room") }
                    .buttonStyle(.bordered)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rooms").font(.headline)
                    Spacer()
                    Button {
                        addRoomPrompt()
                    } label: { Text("Add Room") }
                        .buttonStyle(.bordered)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.doc.rooms.indices, id: \.self) { i in
                            let isSel = (i == currentRoomIndex)
                            
                            Button {
                                // SHORT TAP: switch room
                                currentRoomIndex = i
                                currentSectionIndex = 0
                                store.state.stepIndex = 0                             } label: {
                                    HStack(spacing: 6) {
                                        Text(store.doc.rooms[i].name.isEmpty ? "Room \(i+1)" : store.doc.rooms[i].name)
                                            .lineLimit(1)
                                        if isSel { Image(systemName: "checkmark.circle.fill") }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(isSel ? Color.blue : Color(.systemBackground))
                                    .foregroundStyle(isSel ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color(.separator), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            // LONG PRESS: show context menu
                                .contextMenu {
                                    Button("Rename", systemImage: "pencil") {
                                        renameRoomPrompt(index: i)
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        deleteRoom(index: i)
                                    }
                                }
                        }
                    }             .padding(.vertical, 2)
                }
            }
        }
    }
    
    // === Areas bar (sections inside the current room) ===
    @ViewBuilder
    private var areasBar: some View {
        if store.doc.rooms.indices.contains(currentRoomIndex) {
            let sections = store.doc.rooms[currentRoomIndex].sections
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Areas").font(.headline)
                    Spacer()
                    Button("Add Area") { addAreaToCurrentRoom() }
                        .buttonStyle(.bordered)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sections.indices, id: \.self) { j in
                            let sec   = sections[j]
                            let title = sec.area?.rawValue ?? "Area \(j + 1)"
                            let isSel = (j == currentSectionIndex)
                            
                            Button {
                                // SHORT TAP: switch to this area
                                currentSectionIndex = j
                                store.state.stepIndex = 0
                            } label: {
                                HStack(spacing: 6) {
                                    Text(title).lineLimit(1)
                                    if isSel { Image(systemName: "checkmark.circle.fill") }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isSel ? Color.blue : Color(.systemBackground))
                                .foregroundStyle(isSel ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deleteArea(index: j)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            EmptyView()
        }
    }
    // Create a new room and focus it
    private func addRoom(named name: String) {
        store.doc.rooms.append(EstimateRoom(name: name, sections: [EstimateSection()]))
        currentRoomIndex = store.doc.rooms.count - 1
        currentSectionIndex = 0
        store.state.stepIndex = 0
    }
    // Create → prompt for name
    private func addRoomPrompt() {
        roomNameBuffer = "Room \( (store.doc.rooms.count + 1) )"
        isRenamingExistingRoom = false
        editingRoomIndex = nil
        showRoomNameSheet = true
    }
    
    
    // Start rename flow
    private func renameRoomPrompt(index: Int) {
        guard store.doc.rooms.indices.contains(index) else { return }
        roomNameBuffer = store.doc.rooms[index].name
        isRenamingExistingRoom = true
        editingRoomIndex = index
        showRoomNameSheet = true
    }
    
    // Commit rename
    private func commitRename() {
        guard isRenamingExistingRoom,
              let idx = editingRoomIndex,
              store.doc.rooms.indices.contains(idx) else { return }
        store.doc.rooms[idx].name = roomNameBuffer.isEmpty ? "Room \(idx+1)" : roomNameBuffer
    }
    
    // Optional: delete a room
    private func deleteRoom(index: Int) {
        guard store.doc.rooms.indices.contains(index) else { return }
        store.doc.rooms.remove(at: index)
        currentRoomIndex = min(currentRoomIndex, max(0, store.doc.rooms.count - 1))
        // (Optional) also reset currentSectionIndex if you track it per room
        store.state.stepIndex = 0
    }
    // Add a new area/section to current room
    private func addAreaToCurrentRoom() {
        guard store.doc.rooms.indices.contains(currentRoomIndex) else { return }
        store.doc.rooms[currentRoomIndex].sections.append(EstimateSection())
        currentSectionIndex = store.doc.rooms[currentRoomIndex].sections.count - 1
        store.state.stepIndex = 0
    }
    
    private func deleteArea(index j: Int) {
        guard store.doc.rooms.indices.contains(currentRoomIndex),
              store.doc.rooms[currentRoomIndex].sections.indices.contains(j) else { return }
        store.doc.rooms[currentRoomIndex].sections.remove(at: j)
        currentSectionIndex = min(currentSectionIndex, max(0, store.doc.rooms[currentRoomIndex].sections.count - 1))
        store.state.stepIndex = 0
    }
    /// Returns a Binding to the *currently selected* section, resilient to index drift.
    /// Uses stable IDs to re-locate the room/section on each access.
    func currentSectionBinding() -> Binding<EstimateSection>? {
        // Early guards: must have a valid selection right now
        guard store.doc.rooms.indices.contains(currentRoomIndex) else { return nil }
        let selectedRoom = store.doc.rooms[currentRoomIndex]
        guard selectedRoom.sections.indices.contains(currentSectionIndex) else { return nil }
        let selectedSection = selectedRoom.sections[currentSectionIndex]

        // Capture stable IDs so the binding can re-find items safely later
        let roomID = selectedRoom.id
        let sectionID = selectedSection.id

        return Binding<EstimateSection>(
            get: {
                // Re-find room & section by ID (indices may have changed)
                guard
                    let rIdx = store.doc.rooms.firstIndex(where: { $0.id == roomID }),
                    let sIdx = store.doc.rooms[rIdx].sections.firstIndex(where: { $0.id == sectionID })
                else {
                    // If it no longer exists, return a benign placeholder
                    return EstimateSection()
                }
                return store.doc.rooms[rIdx].sections[sIdx]
            },
            set: { newValue in
                // Re-find and update only if the targets still exist
                guard
                    let rIdx = store.doc.rooms.firstIndex(where: { $0.id == roomID }),
                    let sIdx = store.doc.rooms[rIdx].sections.firstIndex(where: { $0.id == sectionID })
                else {
                    return
                }
                var updated = newValue
                updated.syncAreaQuantities()
                store.doc.rooms[rIdx].sections[sIdx] = updated
            }
        )
    }
    
    // Reset fields when Area changes within a section
    private func resetForAreaChange(_ sec: inout EstimateSection) {
        sec.features = Features()
        sec.measurements = Measurements()
        sec.additionsLabor = []
        sec.additionsMaterials = []
        sec.tileWidthIn = 0
        sec.tileLengthIn = 0
        sec.showerFloorTile = nil
        sec.ceilingTile = nil
        sec.walls = []
        sec.decoratives = []
        sec.radiantHeat = nil
    }
    
    private func missingSizeWarnings(_ sec: EstimateSection) -> [String] {
        TileRate_Installation_Estimator.missingSizeWarnings(sec)
    }

    // Build the required sentence for PDF/summary
    private func sentence(for room: EstimateRoom, section: EstimateSection) -> String {
        estimateSentence(room: room, section: section)
    }
    private func saveImageToPhotos(_ image: UIImage) {
        // iOS 14+: request add-only access if possible (falls back below)
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                switch status {
                case .authorized, .limited:
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    DispatchQueue.main.async {
                        saveAlertMessage = "Saved to Photos."
                        showSaveAlert = true
                    }
                case .denied, .restricted, .notDetermined:
                    DispatchQueue.main.async {
                        saveAlertMessage = "Permission needed to save to Photos. Enable in Settings > Privacy > Photos."
                        showSaveAlert = true
                    }
                @unknown default:
                    DispatchQueue.main.async {
                        saveAlertMessage = "Couldn’t save image."
                        showSaveAlert = true
                    }
                }
            }
        } else {
            // iOS 13 and below
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    DispatchQueue.main.async {
                        saveAlertMessage = "Saved to Photos."
                        showSaveAlert = true
                    }
                } else {
                    DispatchQueue.main.async {
                        saveAlertMessage = "Permission needed to save to Photos. Enable in Settings > Privacy > Photos."
                        showSaveAlert = true
                    }
                }
            }
        }
    }
    private struct PDFPayload: Identifiable {
        let id = UUID()
        let data: Data
        let url: URL
    }
    @State private var pdfPayload: PDFPayload? = nil;
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
    @AppStorage("estimate.counter") private var estimateCounter: Int = 1400;
    @AppStorage("export.shipping") private var exportShipping: Double = 0.0
    @AppStorage("export.taxPercent") private var exportTaxPercent: Double = 0.0
    @AppStorage("additions.shippingEnabled") private var additionsShippingEnabled: Bool = false
    @AppStorage("export.forceSinglePage") private var exportForceSinglePage: Bool = false
    var body: some View {
        NavigationStack {
            // Header pinned at top, no extra top padding beyond safe area
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    headerLeftGroup
                    Spacer(minLength: 12)
                    headerRightButtons
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 20)
                // Make the entire content below scrollable vertically
                ScrollView {
                    card {
                        roomsBar
                        areasBar
                        stepBar
                        VStack(alignment: .leading, spacing: 12) {
                            if currentSectionBinding() == nil {
                                Text("Add a Room to Begin")
                                    .stepTextStyle()
                            } else {
                                switch store.state.stepIndex {
                                case 0: areaStep
                                case 1: tileTypeStep
                                case 2: sizeStep
                                case 3: layoutStep
                                case 4: featuresStep
                                case 5: measurementsStep
                                case 6: additionsStep
                                default: summaryStep
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12) // breathing room at the bottom
                }
                .scrollIndicators(.visible)
                .scrollDismissesKeyboard(.immediately)
                
                // (Optional) remove Spacer; ScrollView handles space
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAdmin) {
                AdminGate(rates: $store.rates, taxDefault: $exportTaxPercent)
                    .presentationDetents([.medium, .large])
            }
            // NEW: Export form sheet
            .sheet(isPresented: $showExportForm) {
                ExportFormView(
                    // Business
                    bizName: $bizName,
                    bizAddress: $bizAddress,
                    bizAddress2: $bizAddress2,
                    bizCityStateZip: $bizCityStateZip,
                    bizPhone: $bizPhone,
                    bizEmail: $bizEmail,
                    // Customer
                    custName: $custName,
                    custAddress: $custAddress,
                    custAddress2: $custAddress2,
                    custCityStateZip: $custCityStateZip,
                    custPhone: $custPhone,
                    custEmail: $custEmail,
                    // Charges
                    shipping: $exportShipping,
                    taxPercent: $exportTaxPercent,
                    // PDF option
                    forceSinglePage: $exportForceSinglePage,
                    // Action
                    onCreatePDF: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        createPDFAndPresent()
                    },
                    onSave: {
                        // Save the current estimate (same behavior as your header Save button)
                        saveCurrentEstimate()
                    }
                )
                .presentationDetents([.large])
                .applyGlobalTapToDismiss() }
            .sheet(isPresented: $showSavedList) {
                SavedEstimatesListView(
                    items: saved.items,
                    onLoad: { loadEstimate($0); showSavedList = false },
                    onDelete: { indexSet in saved.delete(at: indexSet) }
                ).applyGlobalTapToDismiss()             }
            // Share sheet for PDF URL
            .onChange(of: showExportForm) { _, isShowing in
                guard !isShowing else { return }
                guard let data = pendingPDFData, let url = pendingPDFURL else { return }
                
                // clear the stash first
                self.pendingPDFData = nil
                self.pendingPDFURL  = nil
                
                // Present via item once the first sheet is really gone
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.pdfPayload = PDFPayload(data: data, url: url)
                }
            }
            .sheet(item: $pdfPayload) { payload in
                PDFKitPreview(data: payload.data, onTap: {
                    // Keep the payload so we can choose how to share
                    lastTappedPDF = payload
                    showShareChoice = true
                })
                .ignoresSafeArea()
                .presentationDetents([PresentationDetent.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRoomNameSheet) {
                NavigationStack {
                    Form {
                        Section(isRenamingExistingRoom ? "Rename Room" : "New Room") {
                            TextField("Room name", text: $roomNameBuffer)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                        }
                    }
                    .navigationTitle(isRenamingExistingRoom ? "Rename Room" : "Add Room")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showRoomNameSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if isRenamingExistingRoom {
                                    commitRename()
                                } else {
                                    addRoom(named: roomNameBuffer.isEmpty ? "Room \(store.doc.rooms.count + 1)" : roomNameBuffer)
                                }
                                showRoomNameSheet = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }.applyGlobalTapToDismiss()             }
            
            .confirmationDialog("Share", isPresented: $showShareChoice, titleVisibility: .visible) {
                Button("Share PDF") {
                    guard let p = lastTappedPDF else { return }
                    // Dismiss the preview first
                    pdfPayload = nil
                    presentPDFShareSheet(url: p.url)
                }
                Button("Save to Photos") {
                    guard let p = lastTappedPDF,
                          let img = pdfToImage(data: p.data) else { return }
                    // Dismiss the preview first so UI is clean
                    pdfPayload = nil
                    // Give SwiftUI a tick to fully dismiss the sheet/dialog
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        saveImageToPhotos(img)
                    }
                }
                
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: store.state.area) { _, _ in
                // Reset ALL Features whenever Area changes
                store.state.features.mosaicBand = false
                store.state.features.shelves = 0
                store.state.features.niches = 0
                store.state.features.footrests = 0
                store.state.features.benches = 0
                
                // Always reset ceiling on ANY area change (including Shower/Tub)
                store.state.measurements.ceilingSqft = 0
                // Reset ALL measurements to 0 on ANY Area change
                store.state.measurements = Measurements()
                // 🔹 Reset ALL additions (Labor + Materials + Shipping)
                store.state.additionsLabor.removeAll()
                store.state.additionsMaterials.removeAll()
                additionsShippingEnabled = false
                exportShipping = 0.0
            }
            // Reset Shipping whenever Sales list becomes empty
            .onChange(of: store.state.additionsMaterials) { _, materials in
                if materials.isEmpty {
                    additionsShippingEnabled = false
                    exportShipping = 0.0
                }
            }
            
            // Also enforce the same rule on first load / when returning to the screen
            .onAppear {
                if store.state.additionsMaterials.isEmpty {
                    additionsShippingEnabled = false
                    exportShipping = 0.0
                }
            }            .alert("Save Image", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveAlertMessage)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        
    }
    
    
    // MARK: Header
    private var headerLeftGroup: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AppLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                // --- TileRate (gradient on T & R, light blue for the rest)
                let titleFont = Font.system(size: 22, weight: .black, design: .default)  // <-- changed
                let lightBlue = Color(red: 28/255, green: 117/255, blue: 188/255)
                let gradTop   = Color(red: 163/255, green: 255/255, blue: 111/255)
                let gradBot   = Color(red:   5/255, green: 183/255, blue: 198/255)

                HStack(spacing: 0) {
                    Text("T")
                        .font(titleFont)
                        .overlay(
                            LinearGradient(colors: [gradTop, gradBot], startPoint: .top, endPoint: .bottom)
                                .mask(Text("T").font(titleFont))
                        )
                        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 1)

                    Text("ile")
                        .font(titleFont)
                        .foregroundColor(lightBlue)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 1)

                    Text("R")
                        .font(titleFont)
                        .overlay(
                            LinearGradient(colors: [gradTop, gradBot], startPoint: .top, endPoint: .bottom)
                                .mask(Text("R").font(titleFont))
                        )
                        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 1)

                    Text("ate")
                        .font(titleFont)
                        .foregroundColor(lightBlue)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 1)
                }

                // Installation
                Text("Installation")
                    .font(.system(size: 14, weight: .black, design: .default))  // <-- changed
                    .foregroundColor(lightBlue)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 1)

                // Estimator
                Text("Estimator")
                    .font(.system(size: 14, weight: .black, design: .default))  // <-- changed
                    .foregroundColor(lightBlue)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 1)
            }
        }
    }
    
    private var headerRightButtons: some View {
        VStack(spacing: 6) {
            // Top row: Admin + Reset
            HStack(spacing: 8) {
                Button("Admin") { showAdmin = true }
                    .buttonStyle(.bordered)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                
                Button("Reset", action: resetAll)
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            
            // Bottom row: Export + Saved
            HStack(spacing: 8) {
                Button("Export") { showExportForm = true }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                
                Button("Files", action: { showSavedList = true })
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 160) // keeps column width reasonable
    }
    // MARK: Step bar (1–8)
    
    private var stepBar: some View {
        let stepsTop = ["1. Area Type","2. Tile Type","3. Tile Size","4. Layout"]
        let stepsBottom = ["5. Features","6. Measure","7. Additions","8. Summary"]
        let stepsEnabled = !store.doc.rooms.isEmpty   // ⬅️ NEW
        
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(stepsTop.indices, id: \.self) { i in
                    stepButton(title: stepsTop[i], index: i)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                ForEach(stepsBottom.indices, id: \.self) { j in
                    let idx = j + stepsTop.count
                    stepButton(title: stepsBottom[j], index: idx)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .opacity(stepsEnabled ? 1 : 0.4)              // ⬅️ NEW (visual hint disabled)
        .padding(.bottom, 4)
    }
    @ViewBuilder
    private func stepButton(title: String, index: Int) -> some View {
        let stepsEnabled = !store.doc.rooms.isEmpty
        let isSelected = stepsEnabled && (store.state.stepIndex == index)   // ⬅️ only highlight when enabled
        
        Button {
            if stepsEnabled {                                              // ⬅️ ignore taps when no room yet
                store.state.stepIndex = index
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.blue : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
        )
        .foregroundStyle(isSelected ? .white : .primary)
        .disabled(!stepsEnabled)                                           // ⬅️ disable interaction
    }
    
    // MARK: - Option grid (Floor/Wall/etc.)
    
    private func gridOptions<T: Identifiable & RawRepresentable>(
        _ items: [T],
        selection: Binding<T?>,
        columns: Int = 3,
        hSpacing: CGFloat = 8,
        vSpacing: CGFloat = 8
    ) -> some View where T.RawValue == String {
        let rows = items.chunked(into: columns)
        return VStack(alignment: .leading, spacing: vSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                let rowItems = rows[rowIndex]
                OptionRow(
                    titles: rowItems.map { $0.rawValue },
                    isSelecteds: rowItems.map { selection.wrappedValue?.id == $0.id },
                    onTaps: rowItems.map { item in
                        { selection.wrappedValue = item }
                    }
                )
            }
        }
    }
    
    private struct OptionRow: View {
        let titles: [String]
        let isSelecteds: [Bool]
        let onTaps: [() -> Void]

        @State private var rowHeight: CGFloat = 32

        // Keep the count outside the body to simplify type-checking
        private var safeCount: Int {
            let c = min(titles.count, isSelecteds.count, onTaps.count)
            #if DEBUG
            if !(titles.count == isSelecteds.count && isSelecteds.count == onTaps.count) {
                // Non-fatal: helps you spot mismatches during development
                print("⚠️ OptionRow length mismatch:",
                      "titles:", titles.count, "selected:", isSelecteds.count, "taps:", onTaps.count)
            }
            #endif
            return c
        }

        var body: some View {
            Group {
                if safeCount == 0 {
                    // Nothing to show (keeps SwiftUI from building an empty ForEach)
                    EmptyView()
                } else {
                    HStack(spacing: 8) {
                        ForEach(0..<safeCount, id: \.self) { i in
                            OptionButton(
                                title: titles[i],
                                isSelected: isSelecteds[i],
                                rowHeight: $rowHeight,
                                onTap: onTaps[i]
                            )
                        }
                    }
                }
            }
            .onPreferenceChange(OptionRowHeightPreferenceKey.self) { measured in
                if measured > 0, abs(measured - rowHeight) > 0.5 {
                    rowHeight = measured
                }
            }
        }
    }
    
    private struct OptionButton: View {
        let title: String
        let isSelected: Bool
        @Binding var rowHeight: CGFloat
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: OptionRowHeightPreferenceKey.self,
                                            value: geo.size.height)
                        }
                    )
            }
            .buttonStyle(.plain)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
    }
    
    private struct OptionRowHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
    
    // MARK: Card wrapper
    
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
    
    // MARK: Steps
    
    private var areaStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Choose the Installation Area") .font(StepTextStyle.font)
                .foregroundColor(StepTextStyle.color)
            if let sec {
                gridOptions(Area.allCases, selection: Binding(
                    get: { sec.wrappedValue.area },
                    set: { newVal in
                        var s = sec.wrappedValue
                        let old = s.area
                        s.area = newVal
                        if newVal?.rawValue != old?.rawValue {
                            resetForAreaChange(&s)
                        }
                        sec.wrappedValue = s
                    }
                ))
                
            }
        }
    }
    private var tileTypeStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Select the Tile Type")
                .font(StepTextStyle.font)
                .foregroundColor(StepTextStyle.color)
            if let sec {
                gridOptions(TileType.allCases, selection: Binding(
                    get: { sec.wrappedValue.tileType },
                    set: { sec.wrappedValue.tileType = $0 }
                ))
                
            }
        }
    }
    private var sizeStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Choose the Tile Size").font(StepTextStyle.font)
                .foregroundColor(StepTextStyle.color)
            
            if let sec {
                // The grid of size choices
                gridOptions(TileSize.allCases, selection: Binding(
                    get: { sec.wrappedValue.tileSize },
                    set: { sec.wrappedValue.tileSize = $0 }
                ))

                if sec.wrappedValue.tileSize == .mosaic {
                    Text("Mosaic Style").font(.headline)
                    gridOptions(MosaicStyle.allCases, selection: Binding(
                        get: { sec.wrappedValue.mosaicStyle },
                        set: { sec.wrappedValue.mosaicStyle = $0 }
                    ))
                    if sec.wrappedValue.mosaicStyle == .square || sec.wrappedValue.mosaicStyle == .rectangular {
                        Text("Enter the piece size below. It shows on the estimate.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // --- Width / Length inline editors (write to optionals) ---
                VStack(spacing: 8) {
                    HStack {
                        Text("Width (inches)")
                        Spacer()
                        TextField("0", value: Binding<Double>(
                            get: { sec.wrappedValue.tileWidthIn ?? 0 },
                            set: { newVal in
                                var s = sec.wrappedValue
                                s.tileWidthIn = newVal > 0 ? newVal : nil
                                sec.wrappedValue = s
                            }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                    }
                    
                    HStack {
                        Text("Length (inches)")
                        Spacer()
                        TextField("0", value: Binding<Double>(
                            get: { sec.wrappedValue.tileLengthIn ?? 0 },
                            set: { newVal in
                                var s = sec.wrappedValue
                                s.tileLengthIn = newVal > 0 ? newVal : nil
                                sec.wrappedValue = s
                            }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                    }
                }

                sizeStepNote(size: sec.wrappedValue.tileSize,
                             lengthIn: sec.wrappedValue.tileLengthIn,
                             widthIn: sec.wrappedValue.tileWidthIn)
            }
        }
    }

    /// Under a square/rectangle tile's width and length: how it compares with
    /// the standard tile and what that adds, or a warning when a dimension is
    /// missing.
    @ViewBuilder
    private func sizeStepNote(size: TileSize?, lengthIn: Double?, widthIn: Double?) -> some View {
        if isMissingTileDimensions(size: size, lengthIn: lengthIn, widthIn: widthIn) {
            Label("Enter the width and length. Without them no size adder is charged.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if let note = sizeAdderNote(size: size, lengthIn: lengthIn, widthIn: widthIn, rates: store.rates) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Toggle for giving one surface its own tile, with pickers for it when on.
    /// Off means the surface uses the section's main tile.
    @ViewBuilder
    private func separateTileEditor(_ title: String,
                                    tile: Binding<TileChoice?>,
                                    main sec: EstimateSection) -> some View {
        let isOn = Binding<Bool>(
            get: { tile.wrappedValue != nil },
            set: { tile.wrappedValue = $0 ? mainTileChoice(sec) : nil }
        )
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: isOn)
            if let current = tile.wrappedValue {
                tileChoiceFields(Binding(get: { tile.wrappedValue ?? current },
                                         set: { tile.wrappedValue = $0 }))
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// The section's main tile, as the starting point for a separate one.
    private func mainTileChoice(_ sec: EstimateSection) -> TileChoice {
        TileChoice(tileType: sec.tileType ?? .ceramic,
                   tileSize: sec.tileSize ?? .square,
                   layout: sec.layout ?? .straightStacked,
                   tileWidthIn: sec.tileWidthIn,
                   tileLengthIn: sec.tileLengthIn,
                   mosaicStyle: sec.mosaicStyle,
                   pieces: sec.multiTilePieces)
    }

    /// Type, size, layout and dimensions of one tile choice.
    @ViewBuilder
    private func tileChoiceFields(_ tile: Binding<TileChoice>) -> some View {
        LabeledContent("Tile Type") {
            Picker("Tile Type", selection: tile.tileType) {
                ForEach(TileType.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
        }
        LabeledContent("Tile Size") {
            Picker("Tile Size", selection: tile.tileSize) {
                ForEach(TileSize.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
        }
        if tile.wrappedValue.tileSize == .mosaic {
            LabeledContent("Mosaic Style") {
                Picker("Mosaic Style", selection: tile.mosaicStyle) {
                    Text("Choose").tag(MosaicStyle?.none)
                    ForEach(MosaicStyle.allCases) { Text($0.rawValue).tag(MosaicStyle?.some($0)) }
                }
                .fixedSize()
            }
        }
        if tile.wrappedValue.tileSize != .mosaic {
            LabeledContent("Layout") {
                Picker("Layout", selection: tile.layout) {
                    ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
            }
        }
        numberField("Width (inches)", value: inches(tile.tileWidthIn))
        numberField("Length (inches)", value: inches(tile.tileLengthIn))
        sizeStepNote(size: tile.wrappedValue.tileSize,
                     lengthIn: tile.wrappedValue.tileLengthIn,
                     widthIn: tile.wrappedValue.tileWidthIn)
    }

    /// An optional width or length as a number field; 0 or less clears it.
    private func inches(_ value: Binding<Double?>) -> Binding<Double> {
        Binding(get: { value.wrappedValue ?? 0 },
                set: { value.wrappedValue = $0 > 0 ? $0 : nil })
    }

    /// Shower or tub-surround walls: "All walls the same" with one area field,
    /// or, when off, a named, measured card with its own tile for every wall.
    @ViewBuilder
    private func wallsEditor(_ sec: Binding<EstimateSection>,
                             title: String,
                             allSameSqft: WritableKeyPath<Measurements, Double>) -> some View {
        let allSame = Binding<Bool>(
            get: { sec.wrappedValue.walls.isEmpty },
            set: { same in
                var s = sec.wrappedValue
                if same {
                    // Keep the measured area as the single walls figure.
                    let total = s.walls.reduce(0) { $0 + $1.sqft }
                    if total > 0 { s.measurements[keyPath: allSameSqft] = total }
                    s.walls = []
                } else {
                    let tile = mainTileChoice(s)
                    s.walls = ["Back Wall", "Left Wall", "Right Wall"]
                        .map { TiledWall(name: $0, tile: tile) }
                }
                sec.wrappedValue = s
            }
        )

        VStack(alignment: .leading, spacing: 10) {
            Toggle("All walls the same tile", isOn: allSame)

            if allSame.wrappedValue {
                measurementField(title, value: Binding(
                    get: { sec.wrappedValue.measurements[keyPath: allSameSqft] },
                    set: { sec.wrappedValue.measurements[keyPath: allSameSqft] = $0 }
                ))
            } else {
                ForEach(sec.wrappedValue.walls) { wall in
                    let w = wallBinding(sec, wall.id)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Wall name", text: w.name)
                                .font(.headline)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                sec.wrappedValue.walls.removeAll { $0.id == wall.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(sec.wrappedValue.walls.count <= 1)
                        }
                        numberField("Area (sqft)", value: w.sqft)
                        tileChoiceFields(w.tile)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    var s = sec.wrappedValue
                    let tile = s.walls.last?.tile ?? mainTileChoice(s)
                    s.walls.append(TiledWall(name: "Wall \(s.walls.count + 1)", tile: tile))
                    sec.wrappedValue = s
                } label: {
                    Label("Add Wall", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                let total = sec.wrappedValue.walls.reduce(0) { $0 + $1.sqft }
                Text("Walls total: \(total.formatted()) sqft")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Electric radiant heat under a floor or shower floor.
    @ViewBuilder
    private func radiantHeatEditor(_ sec: Binding<EstimateSection>) -> some View {
        let systems = store.rates.heatingSystems
        if !systems.isEmpty {
            let isOn = Binding<Bool>(
                get: { sec.wrappedValue.radiantHeat != nil },
                set: { sec.wrappedValue.radiantHeat = $0 ? RadiantHeatChoice(systemID: systems.first?.id) : nil }
            )
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Electric Radiant Heat?", isOn: isOn)
                if let choice = sec.wrappedValue.radiantHeat {
                    if systems.count > 1 {
                        Picker("System", selection: Binding(
                            get: { choice.systemID ?? systems[0].id },
                            set: { sec.wrappedValue.radiantHeat?.systemID = $0 })) {
                            ForEach(systems) { Text($0.name).tag($0.id) }
                        }
                    }
                    numberField("Heated sq ft (blank = whole floor)", value: Binding(
                        get: { sec.wrappedValue.radiantHeat?.heatedSqft ?? 0 },
                        set: { sec.wrappedValue.radiantHeat?.heatedSqft = $0 > 0 ? $0 : nil }))
                    if let r = radiantHeatPrice(for: sec.wrappedValue, rates: store.rates) {
                        Text("Kit \(currency(r.materials)) · Installation \(currency(r.labor))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Bands, borders and inlays: any number of each, each with its own tile.
    @ViewBuilder
    private func decorativesEditor(_ sec: Binding<EstimateSection>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bands, Borders & Inlays").font(.headline)
            ForEach(sec.wrappedValue.decoratives) { item in
                let d = decorativeBinding(sec, item.id)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.kind.rawValue).font(.subheadline.weight(.semibold))
                        TextField("Name (optional)", text: d.name)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            sec.wrappedValue.decoratives.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    numberField(item.kind == .inlay ? "Square feet" : "Linear feet", value: d.quantity)
                    let options = decorativeLocationOptions(sec.wrappedValue)
                    if !options.isEmpty {
                        Text(item.kind == .inlay ? "Location" : "Locations").font(.subheadline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(options, id: \.key) { opt in
                                    let on = item.isAt(opt)
                                    Button(opt.label) { d.wrappedValue.toggleLocation(opt) }
                                        .buttonStyle(.bordered)
                                        .tint(on ? .blue : .gray)
                                        .fontWeight(on ? .semibold : .regular)
                                }
                            }
                        }
                    }
                    tileChoiceFields(d.tile)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                ForEach(DecorativeKind.allCases) { kind in
                    Button {
                        let s = sec.wrappedValue
                        sec.wrappedValue.decoratives.append(DecorativeItem(kind: kind, tile: defaultDecorativeTile(for: s)))
                    } label: {
                        Label(kind.rawValue, systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Bands and borders are priced per linear foot, inlays per square foot.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func decorativeBinding(_ sec: Binding<EstimateSection>, _ id: UUID) -> Binding<DecorativeItem> {
        Binding(
            get: { sec.wrappedValue.decoratives.first { $0.id == id } ?? DecorativeItem() },
            set: { newValue in
                guard let i = sec.wrappedValue.decoratives.firstIndex(where: { $0.id == id }) else { return }
                sec.wrappedValue.decoratives[i] = newValue
            }
        )
    }

    /// A binding to one shower wall, found by id so removing another wall
    /// cannot leave it pointing at the wrong one.
    private func wallBinding(_ sec: Binding<EstimateSection>, _ id: UUID) -> Binding<TiledWall> {
        Binding(
            get: { sec.wrappedValue.walls.first { $0.id == id } ?? TiledWall() },
            set: { newValue in
                guard let i = sec.wrappedValue.walls.firstIndex(where: { $0.id == id }) else { return }
                sec.wrappedValue.walls[i] = newValue
            }
        )
    }

    private var layoutStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Select a Layout").font(StepTextStyle.font)
                .foregroundColor(StepTextStyle.color)
            if let sec {
                if sec.wrappedValue.tileSize == .mosaic {
                    Text("Not needed for mosaics. They come on sheets, so no layout is chosen or charged.")
                        .foregroundStyle(.secondary)
                } else {
                    gridOptions(Layout.allCases, selection: Binding(
                        get: { sec.wrappedValue.layout },
                        set: { sec.wrappedValue.layout = $0 }
                    ))
                }
            }
        }
    }
    // REPLACE your current `featuresStep` with this scrollable version
    private var featuresStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            if let sec {
                decorativesEditor(sec)
                
                // Shelves, niches, footrests and benches don't go on a floor
                let unitsAllowed = sec.wrappedValue.area != .floor
                quantityRow("Shelves",   value: Binding(
                    get: { sec.wrappedValue.features.shelves },
                    set: { sec.wrappedValue.features.shelves = $0 }
                ), enabled: unitsAllowed)
                quantityRow("Niches",    value: Binding(
                    get: { sec.wrappedValue.features.niches },
                    set: { sec.wrappedValue.features.niches = $0 }
                ), enabled: unitsAllowed)
                quantityRow("Footrests", value: Binding(
                    get: { sec.wrappedValue.features.footrests },
                    set: { sec.wrappedValue.features.footrests = $0 }
                ), enabled: unitsAllowed)
                quantityRow("Benches",   value: Binding(
                    get: { sec.wrappedValue.features.benches },
                    set: { sec.wrappedValue.features.benches = $0 }
                ), enabled: unitsAllowed)
                if !unitsAllowed {
                    Text("Shelves, niches, footrests and benches aren't available for floors.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
        }
    }
    // REPLACE your current `measurementsStep` with this scrollable version
    private var measurementsStep: some View {
        let sec = currentSectionBinding()
        return VStack(alignment: .leading, spacing: 14) {
            Text("Enter Measurements")
                .font(StepTextStyle.font)
                .foregroundColor(StepTextStyle.color)
            if let sec {
                switch sec.wrappedValue.area {
                case .shower:
                    wallsEditor(sec, title: "Shower Walls (sqft)", allSameSqft: \.showerWallsSqft)
                    measurementField("Shower Floor (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.showerFloorSqft },
                        set: { sec.wrappedValue.measurements.showerFloorSqft = $0 }
                    ))
                    if sec.wrappedValue.measurements.showerFloorSqft > 0 {
                        separateTileEditor("Different tile on the shower floor",
                                           tile: sec.showerFloorTile,
                                           main: sec.wrappedValue)
                        radiantHeatEditor(sec)
                    }
                    ceilingBlock(title: "Tile the Ceiling?",
                                 ceilingValue: Binding(
                                    get: { sec.wrappedValue.measurements.ceilingSqft },
                                    set: { sec.wrappedValue.measurements.ceilingSqft = $0 }
                                 ),
                                 ceilingLabel: "Ceiling Area (sqft)")
                    if sec.wrappedValue.measurements.ceilingSqft > 0 {
                        separateTileEditor("Different tile on the ceiling",
                                           tile: sec.ceilingTile,
                                           main: sec.wrappedValue)
                    }

                case .tub:
                    wallsEditor(sec, title: "Tub Surround (sqft)", allSameSqft: \.sqft)
                    ceilingBlock(title: "Tile the Ceiling?",
                                 ceilingValue: Binding(
                                    get: { sec.wrappedValue.measurements.ceilingSqft },
                                    set: { sec.wrappedValue.measurements.ceilingSqft = $0 }
                                 ),
                                 ceilingLabel: "Ceiling Area (sqft)")
                    if sec.wrappedValue.measurements.ceilingSqft > 0 {
                        separateTileEditor("Different tile on the ceiling",
                                           tile: sec.ceilingTile,
                                           main: sec.wrappedValue)
                    }

                case .wall:
                    measurementField("Wall Area (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))
                    
                case .backsplash:
                    measurementField("Backsplash (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))
                    
                case .fireplace:
                    measurementField("Fireplace (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))
                    
                case .floor:
                    measurementField("Floor (sqft)", value: Binding(
                        get: { sec.wrappedValue.measurements.sqft },
                        set: { sec.wrappedValue.measurements.sqft = $0 }
                    ))
                    if sec.wrappedValue.measurements.sqft > 0 {
                        radiantHeatEditor(sec)
                    }
                    
                case .none:
                    Text("Pick an Area First")
                        .foregroundStyle(.secondary)
                }
                
                
            }
        }
    }
    // === Summary (per-area with additions under each area) ===
    private var summaryStep: some View {
        // If no rooms yet, show a gentle hint
        if store.doc.rooms.isEmpty {
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    Text("No rooms added yet. Use 'Add Room' to begin.")
                        .font(StepTextStyle.font)
                        .foregroundColor(StepTextStyle.color)
                }
            )
        }

        // The same totals the PDF uses
        let totals = estimateTotals()
        let perSection = totals.sections
        let hasAnySales: Bool = perSection.contains { !$0.materialItems.isEmpty }
        let preTaxSubtotal = totals.subtotal
        let taxableBase = totals.taxableBase
        let shipping = totals.shipping
        let taxPercent = totals.taxPercent
        let taxAmount = totals.tax
        let grandTotal = totals.grandTotal

        // 4) Build the view using only lightweight bindings/loops
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Group by room for display
                ForEach(store.doc.rooms, id: \.id) { room in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(room.name).font(.headline)

                        // sections for this room (pre-filtered array)
                        let sectionsForRoom = perSection.filter { $0.room.id == room.id }

                        ForEach(sectionsForRoom, id: \.section.id) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                // Area description line
                                Text(sentence(for: item.room, section: item.section))
                                    .font(.subheadline)

                                ForEach(missingSizeWarnings(item.section), id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }

                                // Base installation line (the computed core total for this area)
                                HStack {
                                    Text("Installation")
                                    Spacer()
                                    Text(currencyString(item.core.total))
                                        .fontWeight(.semibold)
                                }

                                // --- Additions for this area ---

                                // Additional Labor
                                if !item.laborItems.isEmpty {
                                    ForEach(item.laborItems) { row in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text("Additional Labor")
                                                Spacer()
                                                Text(currencyString(row.amount))
                                            }
                                            if !row.activity.isEmpty {
                                                Text(row.activity)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }

                                // Additional Sales (Materials)
                                if !item.materialItems.isEmpty {
                                    ForEach(item.materialItems) { row in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text("Sales")
                                                Spacer()
                                                if row.taxable {
                                                    Text("T")
                                                        .font(.caption2)
                                                        .padding(.trailing, 4)
                                                }
                                                Text(currencyString(row.amount))
                                            }
                                            if !row.activity.isEmpty {
                                                Text(row.activity)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }

                                // Section subtotal (base + additions)
                                Divider().padding(.vertical, 4)
                                HStack {
                                    Text("Section Total")
                                    Spacer()
                                    Text(currencyString(item.subtotal))
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Footer totals
                Divider().padding(.vertical, 8)

                // Subtotal
                HStack {
                    Text("Subtotal").font(.headline.weight(.heavy))
                    Spacer()
                    Text(currencyString(preTaxSubtotal)).font(.headline.weight(.heavy))
                }
                .padding(.top, 4)

                // Shipping (only when there are Sales)
                if hasAnySales {
                    HStack {
                        Text("Shipping")
                        Spacer()
                        Text(currencyString(shipping))
                    }
                    .padding(.vertical, 4)
                }

                // Tax (only when there is a taxable base)
                if hasAnySales && taxableBase > 0 {
                    HStack {
                        Text("Tax (\(taxPercent, specifier: "%.2f")%)")
                        Spacer()
                        Text(currencyString(taxAmount))
                    }
                    .padding(.bottom, 6)
                }

                Divider()

                // Grand Total
                HStack {
                    Text("Total").font(.title3.weight(.black))
                    Spacer()
                    Text(currencyString(grandTotal)).font(.title3.weight(.black))
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 8)
        )
    }

    // Simple action used by the Reset button
    private func resetAll() { store.reset() }
    private func saveCurrentEstimate() {
        guard !store.doc.rooms.isEmpty else { return }
        
        let firstRoom = store.doc.rooms.first!
        let firstTitle: String = {
            if let sec = firstRoom.sections.first, let area = sec.area?.rawValue {
                let name = firstRoom.name.isEmpty ? "Room 1" : firstRoom.name
                return "\(custName.isEmpty ? "Untitled" : custName) – \(name) \(area)"
            } else {
                return custName.isEmpty ? "Untitled Estimate" : custName
            }
        }()
        
        let e = SavedEstimate(
            title: firstTitle,
            estimateNumber: estimateCounter,
            biz: PartyInfo(name: bizName, address: bizAddress, address2: bizAddress2,
                           cityStateZip: bizCityStateZip, phone: bizPhone, email: bizEmail),
            cust: PartyInfo(name: custName, address: custAddress, address2: custAddress2,
                            cityStateZip: custCityStateZip, phone: custPhone, email: custEmail),
            shipping: estimateTotals().shipping,
            taxPercent: exportTaxPercent,
            forceSinglePage: exportForceSinglePage,
            document: store.doc
        )
        
        saved.add(e)
        saveAlertMessage = "Estimate saved."
        showSaveAlert = true
    }
    
    private func loadEstimate(_ e: SavedEstimate) {
        bizName = e.biz.name; bizAddress = e.biz.address; bizAddress2 = e.biz.address2
        bizCityStateZip = e.biz.cityStateZip; bizPhone = e.biz.phone; bizEmail = e.biz.email
        
        custName = e.cust.name; custAddress = e.cust.address; custAddress2 = e.cust.address2
        custCityStateZip = e.cust.cityStateZip; custPhone = e.cust.phone; custEmail = e.cust.email
        
        exportShipping = e.shipping
        exportTaxPercent = e.taxPercent
        exportForceSinglePage = e.forceSinglePage
        additionsShippingEnabled = (e.shipping > 0)
        
        store.doc = e.document
        
        currentRoomIndex = 0
        currentSectionIndex = 0
        store.state.stepIndex = 0
    }
    
    private func buildEstimateDescription(from section: EstimateSection) -> String {
        describeSection(section)
    }
    // MARK: - Adapter for legacy calls that still pass EstimatorState
    @inline(__always)
    private func buildDescription(fromState state: EstimatorState) -> String {
        var tmp = EstimateSection()
        tmp.area         = state.area
        tmp.tileType     = state.tileType
        tmp.tileSize     = state.tileSize
        tmp.layout       = state.layout
        tmp.features     = state.features
        tmp.measurements = state.measurements
        tmp.tileWidthIn  = state.tileWidthIn
        tmp.tileLengthIn = state.tileLengthIn
        tmp.mosaicStyle  = state.mosaicStyle
        tmp.multiTilePieces = state.multiTilePieces
        tmp.showerFloorTile = state.showerFloorTile
        tmp.ceilingTile  = state.ceilingTile
        tmp.walls  = state.walls
        tmp.additionsLabor = state.additionsLabor
        tmp.additionsMaterials = state.additionsMaterials
        return buildEstimateDescription(from: tmp)
    }
    // ----- Step-style button label reused in Additions -----
    @ViewBuilder
    private func stepStyleButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
    }
    // MARK: - Additions UI pieces (compact style)
    
    private struct AdditionsHeaderRow: View {
        let showTaxable: Bool
        var body: some View {
            HStack(spacing: 6) {
                Text("Description").font(.caption2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").font(.caption2.bold())
                    .frame(width: 50, alignment: .trailing)
                Text("Rate").font(.caption2.bold())
                    .frame(width: 60, alignment: .trailing)
                Text("Amount").font(.caption2.bold())
                    .frame(width: 70, alignment: .trailing)
                if showTaxable {
                    Text("Tax").font(.caption2.bold())
                        .frame(width: 40, alignment: .center)
                }
            }
            .padding(.vertical, 2)
        }
    }
    
    private struct AdditionsEntryRow: View {
        @Binding var item: AdditionItem
        let showTaxable: Bool
        let onDelete: () -> Void
        
        var body: some View {
            HStack(spacing: 6) {
                // Delete button
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                
                // Description
                TextField("Desc", text: $item.activity)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Qty (typing one stops a price-list line following the area)
                TextField("0", value: Binding(
                    get: { item.qty },
                    set: { v in
                        guard v != item.qty else { return }
                        item.qty = v
                        item.followsAreaSqft = false
                    }), format: .number)
                    .font(.caption)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50, alignment: .leading)
                
                // Rate
                TextField("0", value: $item.rate, format: .number)
                    .font(.caption)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60, alignment: .leading)
                
                // Amount (read-only)
                Text(currencyString(item.amount))
                    .font(.caption).fontWeight(.semibold)
                    .frame(width: 70, alignment: .trailing)
                
                // Optional taxable toggle
                if showTaxable {
                    Toggle("", isOn: $item.taxable)
                        .labelsHidden()
                        .frame(width: 40, alignment: .center)
                }
            }
            .padding(.vertical, 2)
        }
    }
    // MARK: Additions (headers appear only after first add)
    private var additionsStep: some View {
        let sec = currentSectionBinding()
        
        func stepStyleButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .foregroundStyle(.primary)
        }
        
        func listHeader(_ title: String) -> some View {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
            }
            .padding(.top, 10)
        }
        
        // ⬇️ Changed from `return ScrollView {` to a plain VStack
        return VStack(alignment: .leading, spacing: 12) {
            Text("Enter Additional Labor & Materials")
                .font(StepTextStyle.font)
                .foregroundColor(StepTextStyle.color)
            if let sec {
                // Top add buttons for this section
                HStack(spacing: 8) {
                    stepStyleButton("Add Labor") {
                        var s = sec.wrappedValue
                        s.additionsLabor.append(AdditionItem())
                        sec.wrappedValue = s
                    }
                    stepStyleButton("Add Sales") {
                        var s = sec.wrappedValue
                        s.additionsMaterials.append(AdditionItem()) // taxable false by default
                        sec.wrappedValue = s
                    }
                }
                if !store.rates.priceList.isEmpty {
                    Menu {
                        PriceListMenuItems(items: store.rates.priceList) { sec.wrappedValue.add($0) }
                    } label: {
                        Label("Add From Price List", systemImage: "list.bullet")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                }
                
                // -------- Additional Labor --------
                if !sec.wrappedValue.additionsLabor.isEmpty {
                    listHeader("Additional Labor")
                    AdditionsHeaderRow(showTaxable: false)
                    ForEach(sec.wrappedValue.additionsLabor) { item in
                        let binding = Binding<AdditionItem>(
                            get: {
                                sec.wrappedValue.additionsLabor.first(where: { $0.id == item.id }) ?? item
                            },
                            set: { newValue in
                                var s = sec.wrappedValue
                                if let i = s.additionsLabor.firstIndex(where: { $0.id == item.id }) {
                                    s.additionsLabor[i] = newValue
                                }
                                sec.wrappedValue = s
                            }
                        )
                        AdditionsEntryRow(item: binding, showTaxable: false) {
                            var s = sec.wrappedValue
                            s.additionsLabor.removeAll { $0.id == item.id }
                            sec.wrappedValue = s
                        }
                    }
                }
                
                // -------- Sale of Materials --------
                if !sec.wrappedValue.additionsMaterials.isEmpty {
                    listHeader("Sale of Materials")
                    AdditionsHeaderRow(showTaxable: true)
                    
                    ForEach(sec.wrappedValue.additionsMaterials) { item in
                        let binding = Binding<AdditionItem>(
                            get: {
                                sec.wrappedValue.additionsMaterials.first(where: { $0.id == item.id }) ?? item
                            },
                            set: { newValue in
                                var s = sec.wrappedValue
                                if let i = s.additionsMaterials.firstIndex(where: { $0.id == item.id }) {
                                    s.additionsMaterials[i] = newValue
                                }
                                sec.wrappedValue = s
                            }
                        )
                        AdditionsEntryRow(item: binding, showTaxable: true) {
                            var s = sec.wrappedValue
                            s.additionsMaterials.removeAll { $0.id == item.id }
                            sec.wrappedValue = s
                        }
                    }
                    
                    // === Shipping (section UI; enabled only if this section has Sales) ===
                    let hasSales = !sec.wrappedValue.additionsMaterials.isEmpty
                    Divider().padding(.vertical, 4)
                    
                    HStack(spacing: 8) {
                        Toggle("Shipping", isOn: Binding<Bool>(
                            get: { additionsShippingEnabled && hasSales },
                            set: { newValue in
                                additionsShippingEnabled = newValue && hasSales
                                if !additionsShippingEnabled {
                                    exportShipping = 0
                                }
                            }
                        ))
                        .font(.caption)
                        .disabled(!hasSales)                 // No Sales → can’t enable
                        .opacity(hasSales ? 1 : 0.4)
                        
                        Spacer()
                        
                        TextField("0", value: $exportShipping, format: .number)
                            .font(.caption)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .disabled(!(additionsShippingEnabled && hasSales))
                            .opacity((additionsShippingEnabled && hasSales) ? 1 : 0.4)
                    }
                    .padding(.horizontal, 2)
                }
                
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .onChange(of: sec?.wrappedValue.additionsMaterials.count ?? 0) { _, count in
            if count == 0 {
                additionsShippingEnabled = false
                exportShipping = 0
            }
        }
    }
    // MARK: Reusable UI bits
    private func stepperRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 10) {
                Text("\(value.wrappedValue)")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 24, alignment: .trailing)
                Stepper("", value: value, in: 0...50)
                    .labelsHidden()
            }
        }
    }
    
    // MARK: Actions
    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
    // MARK: - PDF helpers (the PDF itself is built by EstimatePDF)

    /// The one place the estimate's totals come from, for the screen and the PDF.
    private func estimateTotals() -> EstimateTotals {
        computeTotals(document: store.doc,
                      rates: store.rates,
                      shippingEnabled: additionsShippingEnabled,
                      shipping: exportShipping,
                      taxPercent: exportTaxPercent)
    }

    private func createPDFAndPresent() {
        // 1) Gather data
        let totals = estimateTotals()

        // 2) Parties from AppStorage
        let biz = PartyInfo(
            name: bizName, address: bizAddress, address2: bizAddress2,
            cityStateZip: bizCityStateZip, phone: bizPhone, email: bizEmail
        )
        let cust = PartyInfo(
            name: custName, address: custAddress, address2: custAddress2,
            cityStateZip: custCityStateZip, phone: custPhone, email: custEmail
        )

        // 3) Admin-selected logo
        let dynamicLogo = decodeBase64Image(bizLogoBase64)

        // 4) Estimate number
        let nextNumber = estimateCounter + 1
        estimateCounter = nextNumber

        // 5) Build and render the PDF
        do {
            let (data, url) = try EstimatePDF.make(
                document: store.doc,
                totals: totals,
                biz: biz,
                cust: cust,
                logo: dynamicLogo,
                estimateNumber: nextNumber,
                forceSinglePage: exportForceSinglePage,
                fallbackDescription: buildDescription(fromState: store.state)
            )

            self.showExportForm = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.pdfPayload = PDFPayload(data: data, url: url)
            }
        } catch {
            print("PDF generation failed:", error)
            self.showExportForm = false
        }
    }
}

// MARK: - Export Form
private struct ExportFormView: View {
    @Binding var bizName: String
    @Binding var bizAddress: String
    @Binding var bizAddress2: String
    @Binding var bizCityStateZip: String
    @Binding var bizPhone: String
    @Binding var bizEmail: String
    
    @Binding var custName: String
    @Binding var custAddress: String
    @Binding var custAddress2: String
    @Binding var custCityStateZip: String
    @Binding var custPhone: String
    @Binding var custEmail: String
    
    // Charges
    @Binding var shipping: Double
    @Binding var taxPercent: Double
    @Binding var forceSinglePage: Bool
    var onCreatePDF: () -> Void
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Business Info") {
                    TextField("Business Name", text: $bizName)
                    TextField("Address", text: $bizAddress)
                    TextField("Address Line 2", text: $bizAddress2)
                    TextField("City, State, Zip", text: $bizCityStateZip)
                    TextField("Phone #", text: $bizPhone)
                    TextField("Email", text: $bizEmail)
                        .keyboardType(.emailAddress)
                }
                
                Section("Customer Info") {
                    TextField("Customer Name", text: $custName)
                    TextField("Address", text: $custAddress)
                    TextField("Address Line 2", text: $custAddress2)
                    TextField("City, State, Zip", text: $custCityStateZip)
                    TextField("Phone #", text: $custPhone)
                    TextField("Email", text: $custEmail)
                        .keyboardType(.emailAddress)
                }
                
                Toggle("Force Single Page PDF", isOn: $forceSinglePage)
                
                
                Section {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(todayString).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Export Details")
            .toolbar {
                // Left side
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                // Right side (left-to-right = Save, then Create PDF)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // commit any in-progress edits first
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                        DispatchQueue.main.async {
                            onSave()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create PDF") {
                        // commit in-progress edits first
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                        DispatchQueue.main.async {
                            onCreatePDF()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private var todayString: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: Date())
    }
}

    private struct SavedEstimatesListView: View {
        let items: [SavedEstimate]
        let onLoad: (SavedEstimate) -> Void
        let onDelete: (IndexSet) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    if items.isEmpty {
                        Text("No saved estimates yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { e in
                            Button {
                                onLoad(e)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(e.title).font(.headline)
                                        Spacer()
                                        Text("#\(e.estimateNumber)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(dateString(e.createdAt))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(e.cust.name).font(.subheadline)
                                }
                            }
                        }
                        .onDelete(perform: onDelete)
                    }
                }
                .navigationTitle("Saved Estimates")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if !items.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) { EditButton() }
                    }
                }
            }
        }

        private func dateString(_ d: Date) -> String {
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
            return df.string(from: d)
        }
    }
    // MARK: - Preview
#Preview("Content (en_US)") {
    ContentView(
        rates: .constant(Rates()),
        taxDefault: .constant(0.0)
    )
    .environment(\.locale, .init(identifier: "en_US"))
}

    // --- Compatibility shim ---
    // Minimal SwiftData model so any existing
    // `.modelContainer(for: [AdminSettingsEntity.self])` in your App file compiles.
    // This model is not used by the ContentView.
#if false
import SwiftData
@Model
final class AdminSettingsEntity {
    init() {}
}
#endif
