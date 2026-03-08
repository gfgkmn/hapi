import Foundation
import Combine

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api: APIClient
    private let store: LocalStore
    private let syncCoordinator: SyncCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(api: APIClient, store: LocalStore, syncCoordinator: SyncCoordinator) {
        self.api = api
        self.store = store
        self.syncCoordinator = syncCoordinator

        syncCoordinator.events
            .filter { if case .sessionsChanged = $0 { return true }; return false }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reloadFromStore() }
            }
            .store(in: &cancellables)
    }

    func load() async {
        guard !isLoading else { return }

        // Show cached immediately
        let cached = await store.loadSessions()
        if !cached.isEmpty {
            sessions = cached
        }

        // Fetch fresh
        isLoading = sessions.isEmpty
        error = nil
        do {
            let fresh = try await api.fetchSessions()
            await store.storeSessions(fresh)
            sessions = fresh
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Session actions

    func abort(_ session: Session) async {
        do { try await api.abortSession(id: session.id) } catch {}
        await load()
    }

    func archive(_ session: Session) async {
        do { try await api.archiveSession(id: session.id) } catch {}
        await load()
    }

    /// IDs of sessions that are being deleted — suppresses SSE re-adding them.
    private var deletingIds = Set<String>()

    func delete(_ session: Session) async {
        deletingIds.insert(session.id)
        sessions.removeAll { $0.id == session.id }
        await store.removeSession(id: session.id)
        do {
            // Active sessions return 409 — abort first, then delete
            if session.active {
                try? await api.abortSession(id: session.id)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            try await api.deleteSession(id: session.id)
        } catch let apiError as APIError {
            // 409 = still active, try archive instead
            if case .badStatus(409, _) = apiError {
                do {
                    try await api.archiveSession(id: session.id)
                    try await api.deleteSession(id: session.id)
                } catch {
                    print("[Sessions] Delete after archive failed: \(error)")
                    self.error = "Could not delete session — try archiving first"
                    await load()
                }
            } else {
                print("[Sessions] Delete failed: \(apiError)")
                self.error = apiError.localizedDescription
                await load()
            }
        } catch {
            print("[Sessions] Delete failed: \(error)")
            self.error = error.localizedDescription
            await load()
        }
        // Suppress SSE re-adding for a few seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            deletingIds.remove(session.id)
        }
    }

    // MARK: - Private

    private func reloadFromStore() async {
        var loaded = await store.loadSessions()
        if !deletingIds.isEmpty {
            loaded.removeAll { deletingIds.contains($0.id) }
        }
        sessions = loaded
    }
}
