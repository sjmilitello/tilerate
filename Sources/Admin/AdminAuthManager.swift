import Foundation
import LocalAuthentication
import Security
import SwiftUI

final class AdminAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCreds = false
    @Published var supportsBiometrics = false
    @Published var biometricsAllowed = false
    @Published var username: String = ""
    @Published var error: String?

    private let kUsername          = "admin.username"
    private let kPassword          = "admin.password"
    private let kRecoveryEmail     = "admin.recoveryEmail"
    private let kBiometricsAllowed = "admin.biometrics.allowed"

    func resetLocalPassword(to newPassword: String) {
        KeychainHelper.shared.set(newPassword, for: kPassword)

        let usernameNow = KeychainHelper.shared.getString(for: kUsername) ?? ""
        self.username = usernameNow
        self.hasCreds = KeychainHelper.shared.hasValue(for: kPassword) && !usernameNow.isEmpty

        self.isAuthenticated = false
        self.error = nil
    }

    init() {
        self.username = KeychainHelper.shared.getString(for: kUsername) ?? ""
        self.hasCreds = KeychainHelper.shared.hasValue(for: kPassword) && !username.isEmpty
        self.biometricsAllowed = UserDefaults.standard.bool(forKey: kBiometricsAllowed)

        let ctx = LAContext()
        self.supportsBiometrics = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    @discardableResult
    func createOrUpdate(username: String, password: String, recoveryEmail: String) -> Bool {
        error = nil
        let userOK = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passOK = !password.isEmpty
        let mailOK = !recoveryEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.isValidEmail(recoveryEmail)

        guard userOK, passOK, mailOK else {
            error = "Username, password, and a valid recovery email are required."
            return false
        }

        KeychainHelper.shared.set(username, for: kUsername)
        KeychainHelper.shared.set(password, for: kPassword)
        UserDefaults.standard.set(recoveryEmail, forKey: kRecoveryEmail)

        self.username = username
        self.hasCreds = true
        self.isAuthenticated = true
        return true
    }

    func loginWithPassword(password: String) {
        error = nil
        guard let stored = KeychainHelper.shared.getString(for: kPassword), !stored.isEmpty else {
            error = "No admin account found."
            return
        }
        if stored == password {
            isAuthenticated = true
        } else {
            error = "Incorrect password."
        }
    }

    func loginWithBiometrics() {
        error = nil

        guard biometricsAllowed else {
            error = "Biometrics is disabled."
            return
        }
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            error = "This device does not support Face ID / Touch ID."
            return
        }

        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Authenticate to access admin settings.") { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.isAuthenticated = true
                } else {
                    self.error = "Face ID / Touch ID failed."
                }
            }
        }
    }

    func setBiometricsEnabled(_ enabled: Bool) {
        biometricsAllowed = enabled
        UserDefaults.standard.set(enabled, forKey: kBiometricsAllowed)
    }

    func setRecoveryEmail(_ email: String) {
        error = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.isValidEmail(trimmed) else {
            error = "Please enter a valid email."
            return
        }
        UserDefaults.standard.set(trimmed, forKey: kRecoveryEmail)
    }

    func signOut() {
        isAuthenticated = false
    }

    var recoveryEmail: String? {
        UserDefaults.standard.string(forKey: kRecoveryEmail)
    }

    private static func isValidEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        let rx = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return rx.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
}

final class KeychainHelper {
    static let shared = KeychainHelper()

    func set(_ value: String, for key: String) {
        let data = Data(value.utf8)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func getString(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    func hasValue(for key: String) -> Bool {
        getString(for: key) != nil
    }
}

extension AdminAuthManager {
    func passwordFallback() -> String {
        KeychainHelper.shared.getString(for: "admin.password") ?? ""
    }
}
