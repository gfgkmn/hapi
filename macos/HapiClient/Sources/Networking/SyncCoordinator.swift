import Foundation
import Combine

/// Events published by SyncCoordinator for ViewModels to observe.
enum StoreEvent {
    case sessionsChanged
    case messagesChanged(sessionId: String)
    case sessionDetailChanged(sessionId: String)
    case connectionStatusChanged(connected: Bool)
}

/// Owns SSE connections, routes events to LocalStore, and publishes
/// changes for ViewModels via Combine.
///
/// Two SSE connections:
/// 1. **Global** (`all=true`) — receives session-level events (added/updated/removed)
/// 2. **Session** (`sessionId=X`) — receives `message-received` events for the active chat
///
/// The server only sends `message-received` to connections subscribed with matching `sessionId`.
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published var isConnected = false

    let events = PassthroughSubject<StoreEvent, Never>()

    private(set) var api: APIClient
    private let store: LocalStore
    private let tokenProvider: () -> String

    // Global SSE (session-level events)
    private var globalSSETask: Task<Void, Never>?

    // Session-specific SSE (message events)
    private var sessionSSETask: Task<Void, Never>?
    private var activeSessionId: String?

    init(api: APIClient, store: LocalStore, tokenProvider: @escaping () -> String) {
        self.api = api
        self.store = store
        self.tokenProvider = tokenProvider
    }

    func updateAPI(_ newAPI: APIClient) {
        self.api = newAPI
    }

    // MARK: - Lifecycle

    func start() {
        stopGlobal()
        let token = tokenProvider()
        guard !token.isEmpty else {
            print("[Sync] No token, skipping SSE")
            return
        }
        print("[Sync] Starting global SSE")
        let provider = tokenProvider
        let client = SSEClient(baseURL: api.baseURL, tokenProvider: { provider() })
        globalSSETask = Task { [weak self] in
            for await event in client.events() {
                guard let self, !Task.isCancelled else { break }
                await self.handleSSEEvent(event)
            }
            guard let self else { return }
            self.isConnected = false
            self.events.send(.connectionStatusChanged(connected: false))
        }
    }

    func stop() {
        stopGlobal()
        stopSessionSSE()
    }

    private func stopGlobal() {
        globalSSETask?.cancel()
        globalSSETask = nil
        isConnected = false
    }

    /// Subscribe to message events for a specific session (when user enters a chat).
    func subscribeToSession(_ sessionId: String) {
        guard activeSessionId != sessionId else { return }
        stopSessionSSE()
        activeSessionId = sessionId
        print("[Sync] Subscribing to messages for session \(sessionId.prefix(8))…")
        let provider = tokenProvider
        let client = SSEClient(baseURL: api.baseURL, tokenProvider: { provider() }, sessionId: sessionId)
        sessionSSETask = Task { [weak self] in
            for await event in client.events() {
                guard let self, !Task.isCancelled else { break }
                await self.handleSSEEvent(event)
            }
        }
    }

    /// Unsubscribe from session-specific messages (when user leaves a chat).
    func unsubscribeFromSession() {
        print("[Sync] Unsubscribing from session messages")
        stopSessionSSE()
    }

    private func stopSessionSSE() {
        sessionSSETask?.cancel()
        sessionSSETask = nil
        activeSessionId = nil
    }

    /// Reconnect SSE and refresh sessions (called on app foreground).
    func resume() async {
        stopGlobal()
        start()
        // Re-subscribe to active session if there was one
        if let sid = activeSessionId {
            let savedSid = sid
            stopSessionSSE()
            subscribeToSession(savedSid)
        }
        await refreshSessions()
    }

    // MARK: - Refresh

    func refreshSessions() async {
        do {
            let sessions = try await api.fetchSessions()
            await store.storeSessions(sessions)
            await store.pruneStaleMessageCaches()
            events.send(.sessionsChanged)
        } catch {}
    }

    func refreshMessages(for sessionId: String) async {
        do {
            let resp = try await api.fetchMessages(sessionId: sessionId, limit: 50)
            let _ = await store.ingestMessages(for: sessionId, messages: resp.messages)
            events.send(.messagesChanged(sessionId: sessionId))
        } catch {}
    }

    // MARK: - SSE Event Routing

    private func handleSSEEvent(_ event: SyncEvent) async {
        switch event {
        case .connectionChanged(let status, _):
            let connected = status == "connected"
            let wasDisconnected = !isConnected
            isConnected = connected
            events.send(.connectionStatusChanged(connected: connected))
            if connected && wasDisconnected {
                print("[Sync] ✅ SSE connected")
            }

        case .sessionAdded:
            events.send(.sessionsChanged)
            Task { [weak self] in await self?.refreshSessions() }

        case .sessionUpdated(let sessionId):
            events.send(.sessionsChanged)
            events.send(.sessionDetailChanged(sessionId: sessionId))
            Task { [weak self] in await self?.refreshSessions() }

        case .sessionRemoved(let sessionId):
            await store.removeSession(id: sessionId)
            events.send(.sessionsChanged)

        case .messageReceived(let sessionId, let message):
            print("[Sync] 💬 Message received for \(sessionId.prefix(8))…")
            let _ = await store.ingestMessage(for: sessionId, message: message)
            events.send(.messagesChanged(sessionId: sessionId))

        case .machineUpdated, .toast, .unknown:
            break
        }
    }
}
