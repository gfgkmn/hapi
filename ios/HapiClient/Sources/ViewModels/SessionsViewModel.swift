import Foundation

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api: APIClient
    private var sseTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    deinit {
        sseTask?.cancel()
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            sessions = try await api.fetchSessions()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func startSSE() {
        sseTask?.cancel()
        let client = SSEClient(baseURL: api.baseURL, token: /* pass JWT */ "")
        sseTask = Task { [weak self] in
            for await event in client.events() {
                guard let self else { break }
                await self.handle(event: event)
            }
        }
    }

    func stopSSE() {
        sseTask?.cancel()
        sseTask = nil
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
        sessions.removeAll { $0.id == session.id }
    }

    // MARK: - SSE handling

    private func handle(event: SyncEvent) async {
        switch event {
        case .sessionAdded, .sessionUpdated, .sessionRemoved:
            await load()
        default:
            break
        }
    }
}
