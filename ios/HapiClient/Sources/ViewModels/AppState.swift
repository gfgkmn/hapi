import Foundation
import SwiftUI

/// Root application state. Holds the API client and coordinates auth.
@MainActor
final class AppState: ObservableObject {
    @Published var apiClient: APIClient?
    @Published var tokenManager = TokenManager()
    @Published var authError: String?
    @Published var localStore: LocalStore?
    @Published var syncCoordinator: SyncCoordinator?

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

            // Set up local store and sync coordinator
            let store = LocalStore()
            localStore = store
            let coordinator = SyncCoordinator(
                api: client,
                store: store,
                tokenProvider: { [weak self] in self?.tokenManager.jwt ?? "" }
            )
            syncCoordinator = coordinator
            coordinator.start()
        } catch {
            authError = error.localizedDescription
        }
    }

    func logout() {
        syncCoordinator?.stop()
        if let store = localStore {
            Task { await store.clearAll() }
        }
        syncCoordinator = nil
        localStore = nil
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

    /// Handle scene phase changes (foreground resume).
    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        Task {
            await refreshTokenIfNeeded()
            await syncCoordinator?.resume()
        }
    }

    /// Re-authenticate to get a fresh JWT if current one is expired or close to expiry.
    private func refreshTokenIfNeeded() async {
        // Check if token expires within the next 5 minutes
        let needsRefresh: Bool
        if tokenManager.jwt.isEmpty {
            needsRefresh = true
        } else if let expiry = TokenManager.expiry(of: tokenManager.jwt),
                  expiry.timeIntervalSinceNow < 300 {
            needsRefresh = true
        } else {
            needsRefresh = false
        }

        guard needsRefresh,
              let baseURLString = savedBaseURL,
              let accessToken = savedAccessToken else { return }

        let normalized = baseURLString.hasSuffix("/") ? baseURLString : baseURLString + "/"
        guard let baseURL = URL(string: normalized) else { return }
        do {
            let authResponse = try await APIClient.authenticate(baseURL: baseURL, accessToken: accessToken)
            tokenManager.store(jwt: authResponse.token)
            // Update API client with fresh token
            let client = APIClient(baseURL: baseURL, token: authResponse.token)
            apiClient = client
            syncCoordinator?.updateAPI(client)
            #if DEBUG
            print("[Auth] Token refreshed, new expiry: \(TokenManager.expiry(of: authResponse.token)?.description ?? "unknown")")
            #endif
        } catch {
            #if DEBUG
            print("[Auth] Token refresh failed: \(error.localizedDescription)")
            #endif
        }
    }
}
