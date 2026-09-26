import Foundation
import LocalAuthentication

/// Unlocks the Admin screen with the phone's own Face ID / Touch ID or passcode.
/// There is no separate admin password, so there is nothing to forget or recover.
@MainActor
final class AdminAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: String?

    func unlock() {
        error = nil
        let ctx = LAContext()
        var policyError: NSError?

        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // A phone with no passcode has nothing to check against; refusing
            // here would lock the owner out of their own rates.
            if (policyError as? LAError)?.code == .passcodeNotSet {
                isAuthenticated = true
            } else {
                error = policyError?.localizedDescription ?? "This phone can't verify its owner."
            }
            return
        }

        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "Unlock the Admin settings.") { success, evalError in
            Task { @MainActor in
                if success {
                    self.isAuthenticated = true
                } else if let code = (evalError as? LAError)?.code,
                          code == .userCancel || code == .appCancel || code == .systemCancel {
                    self.error = nil
                } else {
                    self.error = evalError?.localizedDescription ?? "Couldn't unlock."
                }
            }
        }
    }

    func lock() {
        isAuthenticated = false
    }
}
