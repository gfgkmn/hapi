import Foundation

/// Manages the short-lived JWT token: stores it in memory, parses expiry,
/// and provides a hook to refresh it before it expires.
@MainActor
final class TokenManager: ObservableObject {
    @Published private(set) var jwt: String = ""
    @Published private(set) var isAuthenticated: Bool = false

    private var refreshTask: Task<Void, Never>?

    func store(jwt: String) {
        self.jwt = jwt
        self.isAuthenticated = true
        scheduleRefresh(jwt: jwt)
    }

    func clear() {
        jwt = ""
        isAuthenticated = false
        refreshTask?.cancel()
    }

    /// Parse the `exp` Unix timestamp from the JWT payload.
    static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        // Pad base64url to standard base64
        let rem = base64.count % 4
        if rem != 0 { base64 += String(repeating: "=", count: 4 - rem) }
        base64 = base64.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Private

    /// Schedule a refresh 60 seconds before the token expires.
    private func scheduleRefresh(jwt: String) {
        refreshTask?.cancel()
        guard let expiry = TokenManager.expiry(of: jwt) else { return }
        let refreshIn = max(0, expiry.timeIntervalSinceNow - 60)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(refreshIn * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.tokenExpired()
        }
    }

    private func tokenExpired() {
        // Signal that re-auth is needed. Observers react to isAuthenticated = false.
        isAuthenticated = false
    }
}
