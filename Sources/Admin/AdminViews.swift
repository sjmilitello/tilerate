import PhotosUI
import SwiftUI
import UIKit

// MARK: - AdminGate

struct AdminGate: View {
    @Binding var rates: Rates
    @Binding var taxDefault: Double

    @StateObject private var auth = AdminAuthManager()

    @State private var newUser = ""
    @State private var newPass = ""
    @State private var newRecoveryEmail = ""

    @State private var loginPass = ""

    @State private var showCredsEditor = false
    @State private var updUser = ""
    @State private var updPass = ""
    @State private var updRecoveryEmail = ""

    @State private var showRecoverySheet = false
    @State private var tempRecoveryEmail = ""

    var body: some View {
        NavigationStack {
            Group {
                if auth.isAuthenticated {
                    AdminSheet(
                        rates: $rates,
                        unlocked: .constant(true),
                        password: .constant(""),
                        taxPercentDefault: $taxDefault
                    )
                    .navigationTitle("Admin Settings")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Account") {
                                updUser = auth.username
                                updPass = ""
                                updRecoveryEmail = auth.recoveryEmail ?? ""
                                showCredsEditor = true
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Sign Out") { auth.signOut() }
                        }
                    }
                    .sheet(isPresented: $showCredsEditor) {
                        AccountEditorView(
                            updUser: $updUser,
                            updPass: $updPass,
                            updRecoveryEmail: $updRecoveryEmail,
                            onSave: { user, pass, recovery in
                                auth.createOrUpdate(
                                    username: user,
                                    password: pass.isEmpty ? auth.passwordFallback() : pass,
                                    recoveryEmail: recovery
                                )
                                if auth.error == nil { showCredsEditor = false }
                            },
                            onCancel: { showCredsEditor = false },
                            errorText: auth.error
                        ).applyGlobalTapToDismiss()
                    }
                    .environmentObject(auth)
                } else if !auth.hasCreds {
                    Form {
                        Section("Create Admin Account") {
                            TextField("Username", text: $newUser)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $newPass)
                            TextField("Recovery Email", text: $newRecoveryEmail)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        if let e = auth.error {
                            Text(e).foregroundStyle(.red)
                        }

                        Section {
                            Button("Save") {
                                auth.createOrUpdate(
                                    username: newUser,
                                    password: newPass,
                                    recoveryEmail: newRecoveryEmail
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .navigationTitle("Admin Setup")
                } else {
                    Form {
                        Section(auth.username.isEmpty ? "Welcome" : "Welcome \(auth.username)") {
                            if auth.biometricsAllowed {
                                Button { auth.loginWithBiometrics() } label: {
                                    Label("Use Face ID / Touch ID", systemImage: "faceid")
                                }
                            }

                            SecureField("Password", text: $loginPass)

                            Button("Sign In") {
                                auth.loginWithPassword(password: loginPass)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Forgot my Username") {
                                Task {
                                    guard let to = auth.recoveryEmail, !to.isEmpty else {
                                        auth.error = "No recovery email on file."
                                        return
                                    }
                                    do {
                                        try await APIClient.sendUsername(to: to, username: auth.username)
                                        auth.error = "Username email sent."
                                    } catch {
                                        auth.error = error.localizedDescription
                                    }
                                }
                            }

                            Button("Forgot my Password") {
                                Task {
                                    guard let to = auth.recoveryEmail, !to.isEmpty else {
                                        auth.error = "No recovery email on file."
                                        return
                                    }
                                    do {
                                        _ = try await APIClient.sendReset(to: to)
                                        auth.error = "Password reset email sent."
                                    } catch {
                                        auth.error = error.localizedDescription
                                    }
                                }
                            }

                            if let e = auth.error {
                                Text(e).foregroundStyle(.red)
                            }
                        }

                        if auth.supportsBiometrics {
                            Toggle(
                                "Allow Face ID / Touch ID",
                                isOn: Binding(
                                    get: { auth.biometricsAllowed },
                                    set: { auth.setBiometricsEnabled($0) }
                                )
                            )
                        }
                    }
                    .navigationTitle("Admin Login")
                }
            }
        }
        .task {
            if auth.hasCreds, (auth.recoveryEmail?.isEmpty ?? true) {
                tempRecoveryEmail = ""
                showRecoverySheet = true
            }
        }
        .sheet(isPresented: $showRecoverySheet) {
            NavigationStack {
                Form {
                    Section("Add Recovery Email") {
                        TextField("you@example.com", text: $tempRecoveryEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if let e = auth.error {
                        Text(e).foregroundStyle(.red)
                    }
                }
                .navigationTitle("Required")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showRecoverySheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            auth.setRecoveryEmail(tempRecoveryEmail)
                            if auth.error == nil {
                                showRecoverySheet = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }.applyGlobalTapToDismiss()
        }
    }
}

private struct AccountEditorView: View {
    @Binding var updUser: String
    @Binding var updPass: String
    @Binding var updRecoveryEmail: String

    let onSave: (_ user: String, _ pass: String, _ recovery: String) -> Void
    let onCancel: () -> Void
    var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Change Credentials") {
                    TextField("Username", text: $updUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("New Password", text: $updPass)
                    TextField("Recovery Email", text: $updRecoveryEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let e = errorText {
                    Text(e).foregroundStyle(.red)
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(updUser, updPass, updRecoveryEmail) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - Reset Password

struct ResetPasswordSheet: View {
    let token: String
    var onDone: () -> Void
    @EnvironmentObject private var auth: AdminAuthManager
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reset Password") {
                    SecureField("New password", text: $newPassword)
                    SecureField("Confirm password", text: $confirm)
                }
                if let error { Text(error).foregroundColor(.red) }
                Button("Reset") {
                    Task { await submit() }
                }
                .disabled(isBusy || newPassword.isEmpty || newPassword != confirm)
            }
            .navigationTitle("Reset Password")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onDone() }
                }
            }
        }
    }

    private func submit() async {
        guard !token.isEmpty else { return }
        guard !newPassword.isEmpty, newPassword == confirm else { return }

        isBusy = true
        error = nil

        auth.resetLocalPassword(to: newPassword)

        isBusy = false
        if auth.error == nil {
            onDone()
        } else {
            error = auth.error
        }
    }
}

// MARK: - Admin Sheet

struct AdminSheet: View {
    @Binding var rates: Rates
    @Binding var unlocked: Bool
    @Binding var password: String
    @Binding var taxPercentDefault: Double

    @EnvironmentObject private var auth: AdminAuthManager

    @AppStorage("biz.name")         private var bizName: String = ""
    @AppStorage("biz.address")      private var bizAddress: String = ""
    @AppStorage("biz.address2")     private var bizAddress2: String = ""
    @AppStorage("biz.cityStateZip") private var bizCityStateZip: String = ""
    @AppStorage("biz.phone")        private var bizPhone: String = ""
    @AppStorage("biz.email")        private var bizEmail: String = ""
    @AppStorage("biz.logoBase64")   private var bizLogoBase64: String = ""

    @State private var showPhotoPicker = false
    @State private var showFilePicker  = false
    @State private var showLogoSourceChoice = false
    @State private var pendingImage: CroppableImage? = nil
    @State private var logoViewRefresh = UUID()
    @State private var updUser: String = ""
    @State private var updPass: String = ""
    @State private var updRecoveryEmail: String = ""
    @State private var saveOK: Bool = false

    private struct CroppableImage: Identifiable {
        let id = UUID()
        let uiImage: UIImage
    }

    var body: some View {
        NavigationStack {
            Group {
                if unlocked {
                    contentUnlocked
                        .navigationTitle("Admin Settings")
                } else {
                    contentLocked
                        .navigationTitle("Admin")
                }
            }
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

    private var changeCredentialsSection_UsingLocalState: some View {
        Section("Change Credentials") {
            TextField("New Username", text: $updUser)
                .textInputAutocapitalization(.never)

            SecureField("New Password", text: $updPass)

            TextField("Recovery Email (required)", text: $updRecoveryEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)

            Button("Update") {
                let recovery = updRecoveryEmail.isEmpty
                    ? (auth.recoveryEmail ?? "")
                    : updRecoveryEmail

                let ok: Bool
                if #available(iOS 9999, *) {
                    ok = auth.createOrUpdate(
                        username: updUser.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: updPass,
                        recoveryEmail: recovery
                    )
                } else {
                    auth.createOrUpdate(
                        username: updUser.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: updPass,
                        recoveryEmail: recovery
                    )
                    ok = (auth.error == nil)
                }

                if ok {
                    saveOK = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        saveOK = false
                    }

                    updPass = ""
                    if updRecoveryEmail.isEmpty {
                        updRecoveryEmail = recovery
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                if saveOK {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
                if let e = auth.error {
                    Text(e)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .animation(.default, value: saveOK)
            .animation(.default, value: auth.error)
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
                    Picker("Units", selection: $rates.typeAdderUnit) {
                        ForEach(AdderUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Tile Size Adders ($/sqft)") {
                    sizeRow(.mosaic, "Mosaic")
                    sizeRow(.starCross, "Star/Cross")
                    sizeRow(.arabesque, "Arabesque")
                    sizeRow(.hexagon, "Hexagon")

                    Text("Square/Rectangle Escalators").font(.subheadline)
                    NumericRow(title: "Over length (in)", value: $rates.rectSquareOverLengthIn, fractionDigits: 2)
                    NumericRow(title: "Over width (in)", value: $rates.rectSquareOverWidthIn, fractionDigits: 2)
                    baseRow("Over adder", value: $rates.rectSquareOverAdder)
                    NumericRow(title: "Under length (in)", value: $rates.rectSquareUnderLengthIn, fractionDigits: 2)
                    NumericRow(title: "Under width (in)", value: $rates.rectSquareUnderWidthIn, fractionDigits: 2)
                    baseRow("Under adder", value: $rates.rectSquareUnderAdder)

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

                Section("Mosaic + Features") {
                    baseRow("Mosaic inlay ($/sqft)", value: $rates.mosaicInlayRate)
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

                changeCredentialsSection_UsingLocalState
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    @ViewBuilder
    private var contentLocked: some View {
        VStack(spacing: 16) {
            Text("Enter Admin Password").font(.headline)
            SecureField("Password (default: TileRate)", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { check() }
            Button("Unlock", action: check)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func check() { unlocked = (password == "TileRate") }

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
