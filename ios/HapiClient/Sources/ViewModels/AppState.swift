import Foundation
import SwiftUI

/// Root application state. Holds the API client and coordinates auth.
@MainActor
final class AppState: ObservableObject {
    @Published var apiClient: APIClient?
    @Published var tokenManager = TokenManager()
    @Published var authError: String?

    // Persisted credentials
    var savedAccessToken: String? { Keychain.loadAccessToken() }
    var savedBaseURL: String? { Keychain.loadBaseURL() }

    // MARK: - Login

    func login(baseURLString: String, accessToken: String) async {
        authError = nil
        let normalized = baseURLString.hasSuffix("/") ? baseURLString : baseURLString + "/"
        guard let baseURL = URL(string: normalized) else {
            authError = "Invalid server URL"
            return
        }
        do {
            let authResponse = try await APIClient.authenticate(baseURL: baseURL, accessToken: accessToken)
            let client = APIClient(baseURL: baseURL, token: authResponse.token)
            apiClient = client
            tokenManager.store(jwt: authResponse.token)
            Keychain.saveAccessToken(accessToken)
            Keychain.saveBaseURL(baseURLString)
        } catch {
            authError = error.localizedDescription
        }
    }

    func logout() {
        apiClient = nil
        tokenManager.clear()
        Keychain.deleteAccessToken()
    }

    /// Re-authenticate with stored credentials (called on launch or token expiry).
    func tryAutoLogin() async {
        guard let baseURLString = savedBaseURL,
              let accessToken = savedAccessToken else { return }
        await login(baseURLString: baseURLString, accessToken: accessToken)
    }
}
