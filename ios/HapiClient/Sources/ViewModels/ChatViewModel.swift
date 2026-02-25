import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [DecryptedMessage] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var hasMore = false
    @Published var error: String?
    @Published var session: Session?
    var isNearBottom = true

    private let api: APIClient
    let sessionId: String

    private var oldestSeq: Int?
    private var sseTask: Task<Void, Never>?

    init(api: APIClient, sessionId: String) {
        self.api = api
        self.sessionId = sessionId
    }

    deinit {
        sseTask?.cancel()
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        error = nil
        async let sessionFetch = api.fetchSession(id: sessionId)
        async let messagesFetch = api.fetchMessages(sessionId: sessionId, limit: 50)
        do {
            let (s, resp) = try await (sessionFetch, messagesFetch)
            session = s
            messages = resp.messages
            hasMore = resp.page.hasMore
            oldestSeq = resp.messages.first?.seq
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func loadOlder() async {
        guard hasMore, let beforeSeq = oldestSeq else { return }
        do {
            let resp = try await api.fetchMessages(sessionId: sessionId, limit: 50, beforeSeq: beforeSeq)
            messages = resp.messages + messages
            hasMore = resp.page.hasMore
            oldestSeq = resp.messages.first?.seq
        } catch {}
    }

    // MARK: - Send

    func send(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        do {
            try await api.sendMessage(sessionId: sessionId, text: text)
            // Optimistically reload – SSE will also deliver the message
            let resp = try await api.fetchMessages(sessionId: sessionId, limit: 50)
            messages = resp.messages
        } catch {
            self.error = error.localizedDescription
        }
        isSending = false
    }

    // MARK: - Permissions

    func approve(requestId: String) async {
        do {
            try await api.approvePermission(sessionId: sessionId, requestId: requestId)
            session = try await api.fetchSession(id: sessionId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deny(requestId: String) async {
        do {
            try await api.denyPermission(sessionId: sessionId, requestId: requestId)
            session = try await api.fetchSession(id: sessionId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - SSE

    func startSSE(token: String) {
        sseTask?.cancel()
        let client = SSEClient(baseURL: api.baseURL, token: token)
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

    private func handle(event: SyncEvent) async {
        switch event {
        case .messageReceived(let sid, let msg) where sid == sessionId:
            // Append only if not already present
            if !messages.contains(where: { $0.id == msg.id }) {
                messages.append(msg)
            }
        case .sessionUpdated(let sid) where sid == sessionId:
            session = try? await api.fetchSession(id: sessionId)
        default:
            break
        }
    }
}
