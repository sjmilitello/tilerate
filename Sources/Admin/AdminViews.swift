import PhotosUI
import SwiftUI
import UIKit

// MARK: - AdminGate

struct AdminGate: View {
    @Binding var rates: Rates
    @Binding var taxDefault: Double

    @StateObject private var auth = AdminAuthManager()

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAuthenticated {
                    AdminSheet(
                        rates: $rates,
                        taxPercentDefault: $taxDefault
                    )
                    .navigationTitle("Admin Settings")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Lock") { auth.lock() }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Admin settings are locked.")
                            .font(.headline)
                        Button("Unlock") { auth.unlock() }
                            .buttonStyle(.borderedProminent)
                        if let e = auth.error {
                            Text(e)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .navigationTitle("Admin")
                }
            }
        }
        .task { auth.unlock() }
    }
}

// MARK: - Admin Sheet

struct AdminSheet: View {
    @Binding var rates: Rates
    @Binding var taxPercentDefault: Double

    @AppStorage("biz.name")         private var bizName: String = ""
    @AppStorage("biz.address")      private var bizAddress: String = ""
    @AppStorage("biz.address2")     private var bizAddress2: String = ""
    @AppStorage("biz.cityStateZip") private var bizCityStateZip: String = ""
    @AppStorage("biz.phone")        private var bizPhone: String = ""
    @AppStorage("biz.email")        private var bizEmail: String = ""
    @AppStorage("biz.logoBase64")   private var bizLogoBase64: String = ""
    @AppStorage(DesignPreference.key) private var useNewDesign = false

    @State private var showPhotoPicker = false
    @State private var showFilePicker  = false
    @State private var showLogoSourceChoice = false
    @State private var pendingImage: CroppableImage? = nil
    @State private var logoViewRefresh = UUID()

    private struct CroppableImage: Identifiable {
        let id = UUID()
        let uiImage: UIImage
    }

    var body: some View {
        NavigationStack {
            contentUnlocked
                .navigationTitle("Admin Settings")
        }
        .confirmationDialog("Add Logo From",
                             isPresented: $showLogoSourceChoice,
                             titleVisibility: .visible) {
            Button("Photos") { showPhotoPicker = true }
            Button("Files")  { showFilePicker  = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker1 { img in
                guard let ui = img else {
                    showPhotoPicker = false
                    return
                }
                DispatchQueue.main.async {
                    pendingImage = CroppableImage(uiImage: ui)
                    showPhotoPicker = false
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            ImageFilePicker { picked in
                saveLogo(picked)
                showFilePicker = false
            }.applyGlobalTapToDismiss()
        }
        .sheet(item: $pendingImage) { item in
            LogoCropper(
                source: item.uiImage,
                cropAspect: 220.0 / 90.0,
                outputTargetSize: CGSize(width: 220, height: 90),
                onDone: { cropped in
                    if let png = cropped.pngData() {
                        bizLogoBase64 = png.base64EncodedString()
                    } else if let jpeg = cropped.jpegData(compressionQuality: 1.0) {
                        bizLogoBase64 = jpeg.base64EncodedString()
                    }
                    logoViewRefresh = UUID()
                    pendingImage = nil
                },
                onCancel: { pendingImage = nil }
            ).applyGlobalTapToDismiss()
        }
    }

    @ViewBuilder
    private var contentUnlocked: some View {
        ZStack {
            Form {
                Section("Business Info (Defaults for Export)") {
                    TextField("Business Name", text: $bizName)
                    TextField("Address", text: $bizAddress)
                    TextField("Address Line 2", text: $bizAddress2)
                    TextField("City, State, Zip", text: $bizCityStateZip)
                    TextField("Phone #", text: $bizPhone)
                    TextField("Email", text: $bizEmail)
                        .keyboardType(.emailAddress)

                    if let img = logoImageFromBase64(bizLogoBase64) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current Logo").font(.subheadline)
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220, maxHeight: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Button("Replace Logo") { showLogoSourceChoice = true }
                                Spacer()
                                Button("Remove Logo", role: .destructive) { bizLogoBase64 = "" }
                            }
                        }
                        .padding(.top, 6)
                    } else {
                        Button("Select Logo") { showLogoSourceChoice = true }
                    }

                    Text("These values pre-fill Export Details. You can still edit them per-estimate in Export.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Base Labor Rates ($/sqft)") {
                    baseRow("Floor", value: Binding(get: { rates.base[.floor] ?? 0 }, set: { rates.base[.floor] = $0 }))
                    baseRow("Wall", value: Binding(get: { rates.base[.wall] ?? 0 }, set: { rates.base[.wall] = $0 }))
                    baseRow("Tub Surround", value: Binding(get: { rates.base[.tub] ?? 0 }, set: { rates.base[.tub] = $0 }))
                    baseRow("Shower (walls)", value: Binding(get: { rates.base[.shower] ?? 0 }, set: { rates.base[.shower] = $0 }))
                    baseRow("Backsplash", value: Binding(get: { rates.base[.backsplash] ?? 0 }, set: { rates.base[.backsplash] = $0 }))
                    baseRow("Fireplace", value: Binding(get: { rates.base[.fireplace] ?? 0 }, set: { rates.base[.fireplace] = $0 }))
                    baseRow("Ceiling (tiled)", value: $rates.ceilingBase)
                    baseRow("Shower floor", value: $rates.showerFloorBase)
                }

                Section("Minimum Charges ($)") {
                    minRow("Floor", value: Binding(get: { rates.minimum[.floor] ?? 0 }, set: { rates.minimum[.floor] = $0 }))
                    minRow("Wall", value: Binding(get: { rates.minimum[.wall] ?? 0 }, set: { rates.minimum[.wall] = $0 }))
                    minRow("Tub Surround", value: Binding(get: { rates.minimum[.tub] ?? 0 }, set: { rates.minimum[.tub] = $0 }))
                    minRow("Shower (walls)", value: Binding(get: { rates.minimum[.shower] ?? 0 }, set: { rates.minimum[.shower] = $0 }))
                    minRow("Backsplash", value: Binding(get: { rates.minimum[.backsplash] ?? 0 }, set: { rates.minimum[.backsplash] = $0 }))
                    minRow("Fireplace", value: Binding(get: { rates.minimum[.fireplace] ?? 0 }, set: { rates.minimum[.fireplace] = $0 }))
                    minRow("Ceiling (tiled)", value: $rates.ceilingMinimum)
                    minRow("Shower floor", value: $rates.showerFloorMinimum)
                }

                Section("Tile Type Adders ($/sqft)") {
                    typeRow(.ceramic, "Ceramic")
                    typeRow(.porcelain, "Porcelain")
                    typeRow(.glass, "Glass")
                    typeRow(.marble, "Marble")
                    typeRow(.limestone, "Limestone/Travertine")
                    typeRow(.slate, "Slate")
                    typeRow(.granite, "Granite")
                    typeRow(.quartzite, "Quartzite")
                    typeRow(.cement, "Cement")
                    typeRow(.terracotta, "Terracotta")
                    typeRow(.zellige, "Zellige")
                    Picker("Units", selection: $rates.typeAdderUnit) {
                        ForEach(AdderUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Tile Size Adders ($/sqft)") {
                    sizeRow(.mosaic, "Mosaic")
                    DisclosureGroup("Mosaic style adders (on top of Mosaic)") {
                        ForEach(MosaicStyle.allCases) { m in
                            baseRow(m.rawValue, value: Binding(
                                get: { rates.mosaicStyleAdder[m] ?? 0 },
                                set: { rates.mosaicStyleAdder[m] = $0 }
                            ))
                        }
                    }
                    sizeRow(.starCross, "Star/Cross")
                    sizeRow(.arabesque, "Arabesque")
                    sizeRow(.hexagon, "Hexagon")

                    Text("Square/Rectangle Size").font(.subheadline)
                    NumericRow(title: "Standard tile size (sq in)", value: $rates.sizeBaseAreaSqIn, fractionDigits: 2)
                    baseRow("Adder per doubling (bigger)", value: $rates.sizeAdderPerDoubling)
                    baseRow("Adder per halving (smaller)", value: $rates.sizeAdderPerHalving)
                    Text("The standard tile (12×24 = 288 sq in) pays no size adder. Each time a tile's area doubles from it adds the doubling adder; each time it halves, the halving adder. Part steps count in proportion: 24×48 is 2 doublings, 3×12 is 3 halvings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker("Units", selection: $rates.sizeAdderUnit) {
                        ForEach(AdderUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Layout Adders ($/sqft)") {
                    layoutRow(.straightStacked, "Straight Stacked")
                    layoutRow(.runningBond, "Running Bond")
                    layoutRow(.diagonal, "Diagonal")
                    layoutRow(.herringbone, "Herringbone")
                    layoutRow(.multiTile, "Multi-Tile")
                    Picker("Units", selection: $rates.layoutAdderUnit) {
                        ForEach(AdderUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Bands, Borders & Inlays") {
                    baseRow("Band ($/lin ft)", value: $rates.bandRatePerLinFt)
                    baseRow("Border ($/lin ft)", value: $rates.borderRatePerLinFt)
                    baseRow("Inlay ($/sq ft)", value: $rates.mosaicInlayRate)
                }

                Section("Features") {
                    baseRow("Shelf (each)", value: $rates.unitShelf)
                    baseRow("Niche (each)", value: $rates.unitNiche)
                    baseRow("Footrest (each)", value: $rates.unitFootrest)
                    baseRow("Bench (each)", value: $rates.unitBench)
                }

                Section("Escalator Floors") {
                    NumericRow(title: "Lower Threshold (sqft)", value: Binding(
                        get: { Double(rates.floorEscThresholdLower) },
                        set: { rates.floorEscThresholdLower = Int($0) }
                    ), fractionDigits: 0)

                    NumericRow(title: "Upper Threshold (sqft)", value: Binding(
                        get: { Double(rates.floorEscThresholdUpper) },
                        set: { rates.floorEscThresholdUpper = Int($0) }
                    ), fractionDigits: 0)

                    baseRow("Escalator Adj ($/sqft)", value: $rates.floorEscAdjPerSqft)
                }

                Section("Tax Defaults") {
                    NumericRow(title: "Default Tax %", value: $taxPercentDefault, fractionDigits: 2)
                }

                Section {
                    Toggle("Use the new design (preview)", isOn: $useNewDesign)
                } header: {
                    Text("Design")
                } footer: {
                    Text("Both designs work on the same estimate, rates and saved estimates, so you can switch back and forth at any time.")
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func saveLogo(_ image: UIImage) {
        if let data = image.pngData() {
            bizLogoBase64 = data.base64EncodedString()
        } else if let jpeg = image.jpegData(compressionQuality: 0.95) {
            bizLogoBase64 = jpeg.base64EncodedString()
        }
    }

    private func logoImageFromBase64(_ b64: String) -> UIImage? {
        guard !b64.isEmpty, let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    private struct NumericRow: View {
        let title: String
        @Binding var value: Double
        var fractionDigits: Int = 2

        @State private var text: String = ""
        private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

        private func displayString(for v: Double) -> String {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = fractionDigits
            f.minimumFractionDigits = 0
            return f.string(from: NSNumber(value: v)) ?? "\(v)"
        }

        private func sanitize(_ s: String) -> String {
            var out = ""
            var hasSeparator = false
            for (i, ch) in s.enumerated() {
                if ch.isNumber {
                    out.append(ch)
                } else if String(ch) == decimalSeparator, !hasSeparator {
                    out.append(ch)
                    hasSeparator = true
                } else if ch == "-", i == 0 {
                    out.append(ch)
                }
            }
            return out
        }

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                TextField("0", text: Binding(
                    get: { text },
                    set: { newStr in
                        let cleaned = sanitize(newStr)
                        text = cleaned
                        let normalized = cleaned.replacingOccurrences(of: decimalSeparator, with: ".")
                        if let d = Double(normalized) {
                            value = d
                        }
                    })
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
                .onAppear { text = displayString(for: value) }
                .onChange(of: value) { _, newVal in
                    let str = displayString(for: newVal)
                    if str != text { text = str }
                }
            }
        }
    }

    private func baseRow(_ title: String, value: Binding<Double>) -> some View {
        NumericRow(title: title, value: value, fractionDigits: 2)
    }
    private func minRow(_ title: String, value: Binding<Double>) -> some View {
        NumericRow(title: title, value: value, fractionDigits: 2)
    }
    private func typeRow(_ t: TileType, _ label: String) -> some View {
        baseRow(label, value: Binding(
            get: { rates.typeAdder[t] ?? 0 },
            set: { rates.typeAdder[t] = $0 }
        ))
    }
    private func sizeRow(_ s: TileSize, _ label: String) -> some View {
        baseRow(label, value: Binding(
            get: { rates.sizeAdder[s] ?? 0 },
            set: { rates.sizeAdder[s] = $0 }
        ))
    }
    private func layoutRow(_ l: Layout, _ label: String) -> some View {
        baseRow(label, value: Binding(
            get: { rates.layoutAdder[l] ?? 0 },
            set: { rates.layoutAdder[l] = $0 }
        ))
    }
}
