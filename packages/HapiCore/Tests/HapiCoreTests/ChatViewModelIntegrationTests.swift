import XCTest
import Combine
@testable import HapiCore

/// Integration tests that verify the real-time message delivery pipeline:
/// SyncCoordinator.events → Combine subscription → Task { @MainActor in } → @Published messages
///
/// These tests reproduce the exact bug pattern where messages were stored
/// but the UI didn't update because Task { } in a Combine .sink didn't
/// inherit @MainActor isolation.
@MainActor
final class ChatViewModelIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Create dependencies for testing the event pipeline.
    /// Uses a dummy API URL — no network calls are made in these tests.
    private func makeDeps() -> (APIClient, LocalStore, SyncCoordinator) {
        let api = APIClient(baseURL: URL(string: "http://127.0.0.1:0")!, token: "test")
        let store = LocalStore()
        let sync = SyncCoordinator(api: api, store: store, tokenProvider: { "test" })
        return (api, store, sync)
    }

    // MARK: - Tests

    func testSSEMessageUpdatesUIViaEvents() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"

        let vm = ChatViewModel(
            api: api, store: store, syncCoordinator: sync, sessionId: sessionId
        )

        // Verify initial state
        XCTAssertTrue(vm.messages.isEmpty)

        // Simulate what SSE does: ingest a message into the store and send event
        let content: [String: Any] = ["role": "agent", "content": [
            "type": "output",
            "data": [
                "type": "assistant",
                "message": ["content": [["type": "text", "text": "Hello!"]]]
            ] as [String: Any]
        ] as [String: Any]]
        let msg = DecryptedMessage(
            id: "msg-\(UUID().uuidString)",
            seq: 1,
            localId: nil,
            content: AnyCodable(content),
            createdAt: Date().timeIntervalSince1970 * 1000,
            status: nil
        )

        // This is exactly what SyncCoordinator.handleSSEEvent does:
        let _ = await store.ingestMessage(for: sessionId, message: msg)
        sync.events.send(StoreEvent.messagesChanged(sessionId: sessionId))

        // Give the Combine pipeline time to process:
        // .receive(on: DispatchQueue.main) + Task { @MainActor in } + await store.loadMessages
        // This needs a few run loop iterations.
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // THE CRITICAL ASSERTION: vm.messages should have the new message
        XCTAssertEqual(vm.messages.count, 1, "Message should appear via Combine → @MainActor Task pipeline")
        XCTAssertEqual(vm.messages.first?.id, msg.id)
    }

    func testMultipleSSEMessagesAllAppear() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"
        let vm = ChatViewModel(api: api, store: store, syncCoordinator: sync, sessionId: sessionId)

        // Send 5 messages via the event pipeline
        for i in 1...5 {
            let content: [String: Any] = ["role": "agent", "content": "Message \(i)"]
            let msg = DecryptedMessage(
                id: "msg-\(i)",
                seq: i,
                localId: nil,
                content: AnyCodable(content),
                createdAt: Double(i) * 1000,
                status: nil
            )
            let _ = await store.ingestMessage(for: sessionId, message: msg)
            sync.events.send(StoreEvent.messagesChanged(sessionId: sessionId))
        }

        try await Task.sleep(nanoseconds: 300_000_000) // 300ms

        XCTAssertEqual(vm.messages.count, 5, "All 5 messages should appear")
        XCTAssertEqual(vm.messages.map(\.id), ["msg-1", "msg-2", "msg-3", "msg-4", "msg-5"])
    }

    func testScrollTriggerFiresOnNewMessage() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"
        let vm = ChatViewModel(api: api, store: store, syncCoordinator: sync, sessionId: sessionId)

        let initialTrigger = vm.scrollToBottomTrigger

        let content: [String: Any] = ["role": "agent", "content": "response"]
        let msg = DecryptedMessage(
            id: "msg-1", seq: 1, localId: nil,
            content: AnyCodable(content),
            createdAt: Date().timeIntervalSince1970 * 1000,
            status: nil
        )
        let _ = await store.ingestMessage(for: sessionId, message: msg)
        sync.events.send(StoreEvent.messagesChanged(sessionId: sessionId))

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertGreaterThan(vm.scrollToBottomTrigger, initialTrigger, "Scroll trigger should fire when new message arrives")
    }

    func testOptimisticThenServerEchoShowsCorrectly() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"
        let vm = ChatViewModel(api: api, store: store, syncCoordinator: sync, sessionId: sessionId)

        // Step 1: Append optimistic message (simulates send())
        let localId = UUID().uuidString
        let userContent: [String: Any] = ["role": "user", "content": "hello"]
        let optimistic = DecryptedMessage(
            id: localId, seq: nil, localId: localId,
            content: AnyCodable(userContent),
            createdAt: Date().timeIntervalSince1970 * 1000,
            status: .sending
        )
        vm.messages = await store.appendOptimisticMessage(for: sessionId, message: optimistic)
        XCTAssertEqual(vm.messages.count, 1)

        // Step 2: Server echo arrives via SSE (with localId → resolves optimistic)
        let echo = DecryptedMessage(
            id: "server-msg-1", seq: 1, localId: localId,
            content: AnyCodable(userContent),
            createdAt: Date().timeIntervalSince1970 * 1000 + 100,
            status: nil
        )
        let _ = await store.ingestMessage(for: sessionId, message: echo)
        sync.events.send(StoreEvent.messagesChanged(sessionId: sessionId))

        try await Task.sleep(nanoseconds: 200_000_000)

        // Optimistic should be replaced by server version
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages[0].id, "server-msg-1")

        // Step 3: Agent response arrives
        let responseContent: [String: Any] = ["role": "agent", "content": "I can help!"]
        let response = DecryptedMessage(
            id: "server-msg-2", seq: 2, localId: nil,
            content: AnyCodable(responseContent),
            createdAt: Date().timeIntervalSince1970 * 1000 + 2000,
            status: nil
        )
        let _ = await store.ingestMessage(for: sessionId, message: response)
        sync.events.send(StoreEvent.messagesChanged(sessionId: sessionId))

        try await Task.sleep(nanoseconds: 200_000_000)

        // Both messages should be visible WITHOUT needing another send()
        XCTAssertEqual(vm.messages.count, 2, "Agent response should appear via SSE without another send()")
        XCTAssertEqual(vm.messages[0].id, "server-msg-1") // user
        XCTAssertEqual(vm.messages[1].id, "server-msg-2") // agent
    }

    // MARK: - Command Routing

    func testResolveRoutingLocalCommand() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"
        let vm = ChatViewModel(api: api, store: store, syncCoordinator: sync, sessionId: sessionId)

        // Load slash commands with routing metadata (simulates what loadSlashCommands does)
        // Use the offline fallback which has routing set
        await vm.loadSlashCommands()

        // /todos is local — executeCommand should NOT call send(), should inject local card
        let beforeCount = vm.messages.count
        await vm.executeCommand("/todos")

        // Should have user bubble + local card = 2 new messages
        // (user bubble from executeCommand + card from handleLocalCommand)
        try await Task.sleep(nanoseconds: 100_000_000) // let Task in injectLocalCard complete
        XCTAssertGreaterThan(vm.messages.count, beforeCount, "/todos should add messages locally")
        // isSending should NOT have been set (no server call)
        XCTAssertFalse(vm.isSending, "Local command should not trigger isSending")
    }

    func testResolveRoutingRemoteUnknownCommand() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"
        let vm = ChatViewModel(api: api, store: store, syncCoordinator: sync, sessionId: sessionId)

        await vm.loadSlashCommands()

        // /unknowncmd is not in the list → defaults to remote → calls send()
        // send() will fail (dummy API) but isSending should be set then cleared
        await vm.executeCommand("/unknowncmd")

        // After send completes (with error), isSending should be false
        XCTAssertFalse(vm.isSending)
        // Should have 1 optimistic message from send()
        XCTAssertEqual(vm.messages.count, 1, "Unknown slash command should be sent to server (remote)")
    }

    func testExecuteCommandNonSlashGoesRemote() async throws {
        let (api, store, sync) = makeDeps()
        let sessionId = "test-session-\(UUID().uuidString)"
        let vm = ChatViewModel(api: api, store: store, syncCoordinator: sync, sessionId: sessionId)

        // Regular text (not a slash command) should always go remote
        await vm.executeCommand("hello world")
        XCTAssertEqual(vm.messages.count, 1, "Regular text should be sent to server")
    }

    // MARK: - Cleanup

    override func tearDown() async throws {
        // Clean up any cached data
        // LocalStore uses Caches directory, which is fine to leave
    }
}
