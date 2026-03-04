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

    func delete(_ session: Session) async {
        do { try await api.deleteSession(id: session.id) } catch {}
        await store.removeSession(id: session.id)
        sessions.removeAll { $0.id == session.id }
    }

    // MARK: - Private

    private func reloadFromStore() async {
        sessions = await store.loadSessions()
    }
}
