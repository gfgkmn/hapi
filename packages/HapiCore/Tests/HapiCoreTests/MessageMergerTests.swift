import XCTest
@testable import HapiCore

final class MessageMergerTests: XCTestCase {

    // MARK: - Helpers

    /// Create a server message (has seq, no localId match on self).
    private func serverMsg(
        id: String,
        seq: Int,
        role: String = "agent",
        text: String = "hello",
        createdAt: TimeInterval = 1000,
        localId: String? = nil
    ) -> DecryptedMessage {
        let content: [String: Any] = ["role": role, "content": text]
        return DecryptedMessage(
            id: id, seq: seq, localId: localId,
            content: AnyCodable(content),
            createdAt: createdAt, status: nil
        )
    }

    /// Create an optimistic message (no seq, id == localId).
    private func optimisticMsg(
        localId: String,
        role: String = "user",
        text: String = "hi",
        createdAt: TimeInterval = 1000,
        status: MessageStatus = .sending
    ) -> DecryptedMessage {
        let content: [String: Any] = ["role": role, "content": text]
        return DecryptedMessage(
            id: localId, seq: nil, localId: localId,
            content: AnyCodable(content),
            createdAt: createdAt, status: status
        )
    }

    // MARK: - Basic Merge

    func testMergeEmptyExistingWithIncoming() {
        let incoming = [serverMsg(id: "a", seq: 1)]
        let result = MessageMerger.merge(existing: [], incoming: incoming)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "a")
    }

    func testMergeExistingWithEmptyIncoming() {
        let existing = [serverMsg(id: "a", seq: 1)]
        let result = MessageMerger.merge(existing: existing, incoming: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "a")
    }

    func testMergeBothEmpty() {
        let result = MessageMerger.merge(existing: [], incoming: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testMergeDeduplicatesById() {
        let existing = [serverMsg(id: "a", seq: 1, text: "old")]
        let incoming = [serverMsg(id: "a", seq: 1, text: "new")]
        let result = MessageMerger.merge(existing: existing, incoming: incoming)
        XCTAssertEqual(result.count, 1)
        // Server version (incoming) wins
        let content = result[0].content?.value as? [String: Any]
        XCTAssertEqual(content?["content"] as? String, "new")
    }

    func testMergeAddsNewMessages() {
        let existing = [serverMsg(id: "a", seq: 1, createdAt: 1000)]
        let incoming = [serverMsg(id: "b", seq: 2, createdAt: 2000)]
        let result = MessageMerger.merge(existing: existing, incoming: incoming)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "a")
        XCTAssertEqual(result[1].id, "b")
    }

    // MARK: - Optimistic Resolution (localId matching)

    func testOptimisticResolvedByLocalId() {
        let opt = optimisticMsg(localId: "local-1", text: "hello", createdAt: 1000)
        let srv = serverMsg(id: "server-1", seq: 5, text: "hello", createdAt: 1001, localId: "local-1")
        let result = MessageMerger.merge(existing: [opt], incoming: [srv])
        // Should have only the server message; optimistic is dropped
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "server-1")
        XCTAssertEqual(result[0].seq, 5)
    }

    func testOptimisticNotResolvedWhenLocalIdMissing() {
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let srv = serverMsg(id: "server-1", seq: 5, role: "user", text: "hello", createdAt: 1001)
        // No localId on server message — localId matching won't fire,
        // but content-based dedup should still catch it (same role + text + time)
        let result = MessageMerger.merge(existing: [opt], incoming: [srv])
        // Content-based dedup: same role + same text + within 10s → drops optimistic
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "server-1")
    }

    // MARK: - Content-Based Dedup

    func testContentDedupMatchesSameRoleAndText() {
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let srv = serverMsg(id: "srv-1", seq: 1, role: "user", text: "hello", createdAt: 1002)
        let result = MessageMerger.merge(existing: [opt], incoming: [srv])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "srv-1")
    }

    func testContentDedupDoesNotMatchDifferentText() {
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let srv = serverMsg(id: "srv-1", seq: 1, role: "user", text: "goodbye", createdAt: 1002)
        let result = MessageMerger.merge(existing: [opt], incoming: [srv])
        // Different text → no dedup → both remain
        XCTAssertEqual(result.count, 2)
    }

    func testContentDedupDoesNotMatchDifferentRole() {
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let srv = serverMsg(id: "srv-1", seq: 1, role: "agent", text: "hello", createdAt: 1002)
        let result = MessageMerger.merge(existing: [opt], incoming: [srv])
        // Different role → no dedup → both remain
        XCTAssertEqual(result.count, 2)
    }

    func testContentDedupDoesNotMatchOutsideTimeWindow() {
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let srv = serverMsg(id: "srv-1", seq: 1, role: "user", text: "hello", createdAt: 12000)
        let result = MessageMerger.merge(existing: [opt], incoming: [srv])
        // Time delta > 10000ms → no dedup → both remain
        XCTAssertEqual(result.count, 2)
    }

    func testContentDedupConsumesOnlyOneOptimistic() {
        // Two optimistic messages with same role+text sent rapidly
        let opt1 = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let opt2 = optimisticMsg(localId: "local-2", role: "user", text: "hello", createdAt: 1001)
        // One server echo
        let srv = serverMsg(id: "srv-1", seq: 1, role: "user", text: "hello", createdAt: 1002)
        let result = MessageMerger.merge(existing: [opt1, opt2], incoming: [srv])
        // Only ONE optimistic should be consumed, leaving server msg + one optimistic
        XCTAssertEqual(result.count, 2)
        XCTAssert(result.contains { $0.id == "srv-1" })
    }

    func testContentDedupPrefersClosestTimestamp() {
        let opt1 = optimisticMsg(localId: "local-1", role: "user", text: "hello", createdAt: 1000)
        let opt2 = optimisticMsg(localId: "local-2", role: "user", text: "hello", createdAt: 1005)
        let srv = serverMsg(id: "srv-1", seq: 1, role: "user", text: "hello", createdAt: 1006)
        let result = MessageMerger.merge(existing: [opt1, opt2], incoming: [srv])
        // srv at 1006 is closest to opt2 at 1005 (delta=1) vs opt1 at 1000 (delta=6)
        // So opt2 should be consumed, opt1 should remain
        XCTAssertEqual(result.count, 2)
        XCTAssert(result.contains { $0.id == "local-1" })
        XCTAssert(result.contains { $0.id == "srv-1" })
    }

    // MARK: - Agent responses should NOT dedup user messages

    func testAgentResponseDoesNotDedupUserOptimistic() {
        let userOpt = optimisticMsg(localId: "local-1", role: "user", text: "what is 2+2?", createdAt: 1000)
        let agentResp = serverMsg(id: "srv-1", seq: 2, role: "agent", text: "4", createdAt: 2000)
        let result = MessageMerger.merge(existing: [userOpt], incoming: [agentResp])
        // Different roles → both should remain
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Sorting

    func testSortedBySeq() {
        let a = serverMsg(id: "a", seq: 3, createdAt: 1000)
        let b = serverMsg(id: "b", seq: 1, createdAt: 2000)
        let c = serverMsg(id: "c", seq: 2, createdAt: 3000)
        let result = MessageMerger.sorted([a, b, c])
        XCTAssertEqual(result.map(\.id), ["b", "c", "a"])
    }

    func testSortedByCreatedAtWhenNoSeq() {
        let a = optimisticMsg(localId: "a", createdAt: 3000)
        let b = optimisticMsg(localId: "b", createdAt: 1000)
        let c = optimisticMsg(localId: "c", createdAt: 2000)
        let result = MessageMerger.sorted([a, b, c])
        XCTAssertEqual(result.map(\.id), ["b", "c", "a"])
    }

    func testSortedInterleavesOptimisticByTimestamp() {
        let srv1 = serverMsg(id: "s1", seq: 1, createdAt: 1000)
        let opt = optimisticMsg(localId: "opt", createdAt: 1500)
        let srv2 = serverMsg(id: "s2", seq: 2, createdAt: 2000)
        let result = MessageMerger.sorted([srv2, opt, srv1])
        // srv1 (seq 1) < opt (timestamp 1500, between seq 1 and 2) < srv2 (seq 2)
        // Both have seq → seq wins for srv1 vs srv2
        // opt has no seq → falls back to createdAt
        XCTAssertEqual(result.map(\.id), ["s1", "opt", "s2"])
    }

    func testSortedServerBeforeOptimisticAtSameTimestamp() {
        let srv = serverMsg(id: "s1", seq: 1, createdAt: 1000)
        let content: [String: Any] = ["role": "user", "content": "hi"]
        let opt = DecryptedMessage(
            id: "opt", seq: nil, localId: "opt",
            content: AnyCodable(content),
            createdAt: 1000, status: .sending
        )
        let result = MessageMerger.sorted([opt, srv])
        XCTAssertEqual(result[0].id, "s1") // Server first
        XCTAssertEqual(result[1].id, "opt")
    }

    // MARK: - Trim

    func testTrimKeepsLastN() {
        let msgs = (1...10).map { serverMsg(id: "\($0)", seq: $0, createdAt: TimeInterval($0 * 1000)) }
        let trimmed = MessageMerger.trim(msgs, limit: 3)
        XCTAssertEqual(trimmed.count, 3)
        XCTAssertEqual(trimmed.map(\.id), ["8", "9", "10"])
    }

    func testTrimNoopWhenUnderLimit() {
        let msgs = [serverMsg(id: "a", seq: 1)]
        let trimmed = MessageMerger.trim(msgs, limit: 10)
        XCTAssertEqual(trimmed.count, 1)
    }

    // MARK: - Real-world scenario: full send cycle

    func testFullSendCycleWithLocalIdResolution() {
        // Step 1: User sends message → optimistic message in store
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "Hello Claude", createdAt: 1000)
        var store = [opt]

        // Step 2: Server echoes user message with localId
        let userEcho = serverMsg(id: "msg-101", seq: 10, role: "user", text: "Hello Claude", createdAt: 1001, localId: "local-1")
        store = MessageMerger.merge(existing: store, incoming: [userEcho])
        XCTAssertEqual(store.count, 1, "Optimistic should be replaced by server echo")
        XCTAssertEqual(store[0].id, "msg-101")

        // Step 3: Agent responds
        let agentResp = serverMsg(id: "msg-102", seq: 11, role: "agent", text: "Hello! How can I help?", createdAt: 2000)
        store = MessageMerger.merge(existing: store, incoming: [agentResp])
        XCTAssertEqual(store.count, 2, "Should have user message + agent response")
        XCTAssertEqual(store[0].id, "msg-101") // user
        XCTAssertEqual(store[1].id, "msg-102") // agent
    }

    func testFullSendCycleWithoutLocalId() {
        // Fallback path: server echo doesn't carry localId
        let opt = optimisticMsg(localId: "local-1", role: "user", text: "Hello Claude", createdAt: 1000)
        var store = [opt]

        // Server echo without localId — content-based dedup should handle it
        let userEcho = serverMsg(id: "msg-101", seq: 10, role: "user", text: "Hello Claude", createdAt: 1001)
        store = MessageMerger.merge(existing: store, incoming: [userEcho])
        XCTAssertEqual(store.count, 1, "Content-based dedup should match and replace optimistic")
        XCTAssertEqual(store[0].id, "msg-101")

        // Agent responds
        let agentResp = serverMsg(id: "msg-102", seq: 11, role: "agent", text: "Hello!", createdAt: 2000)
        store = MessageMerger.merge(existing: store, incoming: [agentResp])
        XCTAssertEqual(store.count, 2)
    }

    func testRapidFireMessagesNotEaten() {
        // User sends 3 messages rapidly — server echoes shouldn't cross-consume
        let opt1 = optimisticMsg(localId: "l1", role: "user", text: "msg1", createdAt: 1000)
        let opt2 = optimisticMsg(localId: "l2", role: "user", text: "msg2", createdAt: 1001)
        let opt3 = optimisticMsg(localId: "l3", role: "user", text: "msg3", createdAt: 1002)
        var store = [opt1, opt2, opt3]

        // Server echoes all three with localIds
        let echo1 = serverMsg(id: "s1", seq: 1, role: "user", text: "msg1", createdAt: 1000, localId: "l1")
        let echo2 = serverMsg(id: "s2", seq: 2, role: "user", text: "msg2", createdAt: 1001, localId: "l2")
        let echo3 = serverMsg(id: "s3", seq: 3, role: "user", text: "msg3", createdAt: 1002, localId: "l3")
        store = MessageMerger.merge(existing: store, incoming: [echo1, echo2, echo3])

        XCTAssertEqual(store.count, 3, "All 3 messages should remain")
        XCTAssertEqual(store.map(\.id), ["s1", "s2", "s3"])
    }

    func testRapidFireSameTextNotCrossConsumed() {
        // User sends identical text twice rapidly (e.g., "yes" "yes")
        let opt1 = optimisticMsg(localId: "l1", role: "user", text: "yes", createdAt: 1000)
        let opt2 = optimisticMsg(localId: "l2", role: "user", text: "yes", createdAt: 1001)
        var store = [opt1, opt2]

        // Server echoes only the first one (without localId)
        let echo1 = serverMsg(id: "s1", seq: 1, role: "user", text: "yes", createdAt: 1000)
        store = MessageMerger.merge(existing: store, incoming: [echo1])

        // Only one optimistic should be consumed (closest timestamp)
        XCTAssertEqual(store.count, 2, "One optimistic consumed, one remains + server msg")
        XCTAssert(store.contains { $0.id == "s1" })
        // The remaining optimistic should be l2 (further from server timestamp)
        XCTAssert(store.contains { $0.id == "l2" })
    }
}
