
import Foundation

enum APIClient {
    // Use your custom domain for all API calls
    private static let BASE_URL = "https://tilerate.com"

    // MARK: - Public API

    static func sendUsername(to: String, username: String) async throws {
        let body = SendUsernameRequest(to: to, username: username)
        _ = try await post(path: "/api/send-username", body: body)
    }

    /// Starts reset; backend emails link and (optionally) returns { token }
    @discardableResult
    static func sendReset(to: String) async throws -> String? {
        let body = SendResetRequest(to: to)
        let data = try await post(path: "/api/send-reset", body: body)
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = dict["token"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }

    /// Finalize reset — best practice: no email included
    static func resetPassword(token: String, newPassword: String) async throws {
        let body = ResetPasswordRequest(token: token, newPassword: newPassword)
        _ = try await post(path: "/api/reset-password", body: body)
    }

    // MARK: - Requests (no appBaseUrl needed client-side)
    private struct SendUsernameRequest: Encodable {
        let to: String
        let username: String
    }
    private struct SendResetRequest: Encodable {
        let to: String
    }
    private struct ResetPasswordRequest: Encodable {
        let token: String
        let newPassword: String
    }

    // MARK: - Transport
    @discardableResult
    private static func post<T: Encodable>(path: String, body: T) async throws -> Data {
        guard let url = URL(string: BASE_URL + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let msg = String(data: data, encoding: .utf8), !msg.isEmpty {
                throw NSError(domain: "APIClient",
                              code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
            throw URLError(.badServerResponse)
        }
        return data
    }
}

