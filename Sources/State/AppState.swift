
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var pendingResetToken: String?

    /// Accepts BOTH custom scheme (myapp://reset?token=...) and web links (https://tilerate.com/reset?token=...)
    func handleDeepLink(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // 1) Try to pull a token-like thing from common param names
        let token = Self.firstNonEmpty(
            from: comps.queryItems,
            keys: ["token", "code", "oobCode", "reset_token"]
        )

        // 2) Decide if this URL looks like a "reset" link
        //    - custom scheme: myapp://reset?...  -> host == "reset"
        //    - web link:      https://host/reset  -> path contains "reset"
        let hostIsReset = comps.host?.lowercased() == "reset"
        let pathContainsReset = comps.path
            .lowercased()
            .split(separator: "/")
            .contains(where: { $0 == "reset" })

        guard let token, (hostIsReset || pathContainsReset) else { return }

        // 3) Surface the token (triggers the sheet)
        pendingResetToken = token
    }

    private static func firstNonEmpty(from items: [URLQueryItem]?, keys: [String]) -> String? {
        guard let items else { return nil }
        for key in keys {
            if let v = items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
               !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v
            }
        }
        return nil
    }
}
