import XCTest
@testable import HapiCore

final class SyncEventParseTests: XCTestCase {

    // MARK: - Helpers

    private func json(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Connection Changed

    func testParseConnectionChanged() {
        let data = json([
            "type": "connection-changed",
            "data": ["status": "connected", "subscriptionId": "sub-1"]
        ])
        guard case .connectionChanged(let status, let subId) = SyncEvent.parse(from: data) else {
            XCTFail("Expected connectionChanged"); return
        }
        XCTAssertEqual(status, "connected")
        XCTAssertEqual(subId, "sub-1")
    }

    func testParseConnectionChangedDefaultsToConnected() {
        let data = json(["type": "connection-changed"])
        guard case .connectionChanged(let status, _) = SyncEvent.parse(from: data) else {
            XCTFail("Expected connectionChanged"); return
        }
        XCTAssertEqual(status, "connected")
    }

    // MARK: - Session Events

    func testParseSessionAdded() {
        let data = json(["type": "session-added", "sessionId": "sess-1"])
        guard case .sessionAdded(let sid) = SyncEvent.parse(from: data) else {
            XCTFail("Expected sessionAdded"); return
        }
        XCTAssertEqual(sid, "sess-1")
    }

    func testParseSessionUpdated() {
        let data = json(["type": "session-updated", "sessionId": "sess-2"])
        guard case .sessionUpdated(let sid) = SyncEvent.parse(from: data) else {
            XCTFail("Expected sessionUpdated"); return
        }
        XCTAssertEqual(sid, "sess-2")
    }

    func testParseSessionRemoved() {
        let data = json(["type": "session-removed", "sessionId": "sess-3"])
        guard case .sessionRemoved(let sid) = SyncEvent.parse(from: data) else {
            XCTFail("Expected sessionRemoved"); return
        }
        XCTAssertEqual(sid, "sess-3")
    }

    func testParseSessionAddedMissingId() {
        let data = json(["type": "session-added"])
        XCTAssertNil(SyncEvent.parse(from: data))
    }

    // MARK: - Message Received

    func testParseMessageReceived() {
        let data = json([
            "type": "message-received",
            "sessionId": "sess-1",
            "message": [
                "id": "msg-1",
                "seq": 5,
                "localId": "local-1",
                "content": ["role": "user", "content": "hello"],
                "createdAt": 1709900000000
            ] as [String: Any]
        ])
        guard case .messageReceived(let sid, let msg) = SyncEvent.parse(from: data) else {
            XCTFail("Expected messageReceived"); return
        }
        XCTAssertEqual(sid, "sess-1")
        XCTAssertEqual(msg.id, "msg-1")
        XCTAssertEqual(msg.seq, 5)
        XCTAssertEqual(msg.localId, "local-1")
        XCTAssertEqual(msg.createdAt, 1709900000000)
    }

    func testParseMessageReceivedWithNullLocalId() {
        let data = json([
            "type": "message-received",
            "sessionId": "sess-1",
            "message": [
                "id": "msg-1",
                "seq": 5,
                "content": ["role": "agent", "content": ["type": "text", "text": "hi"]],
                "createdAt": 1709900000000
            ] as [String: Any]
        ])
        guard case .messageReceived(_, let msg) = SyncEvent.parse(from: data) else {
            XCTFail("Expected messageReceived"); return
        }
        XCTAssertNil(msg.localId)
        XCTAssertEqual(msg.seq, 5)
    }

    func testParseMessageReceivedWithNestedContent() {
        // Agent event message format from CLI's sendSessionEvent
        let data = json([
            "type": "message-received",
            "sessionId": "sess-1",
            "message": [
                "id": "msg-2",
                "seq": 10,
                "content": [
                    "role": "agent",
                    "content": [
                        "id": "event-uuid",
                        "type": "event",
                        "data": [
                            "type": "message",
                            "message": "Session cost: $0.0042"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "createdAt": 1709900000000
            ] as [String: Any]
        ])
        guard case .messageReceived(_, let msg) = SyncEvent.parse(from: data) else {
            XCTFail("Expected messageReceived — nested content decode failed"); return
        }
        XCTAssertEqual(msg.id, "msg-2")
        // Verify the nested content is preserved
        let content = msg.content?.value as? [String: Any]
        XCTAssertEqual(content?["role"] as? String, "agent")
    }

    func testParseMessageReceivedWithAssistantOutput() {
        // Full Claude response format
        let data = json([
            "type": "message-received",
            "sessionId": "sess-1",
            "message": [
                "id": "msg-3",
                "seq": 15,
                "content": [
                    "role": "agent",
                    "content": [
                        "type": "output",
                        "data": [
                            "type": "assistant",
                            "message": [
                                "content": [
                                    ["type": "text", "text": "Hello! How can I help?"]
                                ]
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "createdAt": 1709900000000
            ] as [String: Any]
        ])
        guard case .messageReceived(_, let msg) = SyncEvent.parse(from: data) else {
            XCTFail("Expected messageReceived — assistant output decode failed"); return
        }
        XCTAssertEqual(msg.id, "msg-3")
    }

    func testParseMessageReceivedMissingSessionId() {
        let data = json([
            "type": "message-received",
            "message": [
                "id": "msg-1", "seq": 1,
                "content": ["role": "user", "content": "hi"],
                "createdAt": 1000
            ] as [String: Any]
        ])
        XCTAssertNil(SyncEvent.parse(from: data))
    }

    func testParseMessageReceivedMissingMessage() {
        let data = json(["type": "message-received", "sessionId": "sess-1"])
        XCTAssertNil(SyncEvent.parse(from: data))
    }

    func testParseMessageReceivedMalformedMessage() {
        // message is a valid JSON object but missing required fields for DecryptedMessage
        let data = json([
            "type": "message-received",
            "sessionId": "sess-1",
            "message": ["garbage": true] as [String: Any]
        ])
        XCTAssertNil(SyncEvent.parse(from: data))
    }

    // MARK: - Machine Updated

    func testParseMachineUpdated() {
        let data = json(["type": "machine-updated", "machineId": "m-1"])
        guard case .machineUpdated(let mid) = SyncEvent.parse(from: data) else {
            XCTFail("Expected machineUpdated"); return
        }
        XCTAssertEqual(mid, "m-1")
    }

    // MARK: - Toast

    func testParseToast() {
        let data = json([
            "type": "toast",
            "data": [
                "title": "Done",
                "body": "Task finished",
                "sessionId": "sess-1",
                "url": "https://example.com"
            ] as [String: Any]
        ])
        guard case .toast(let title, let body, let sid, let url) = SyncEvent.parse(from: data) else {
            XCTFail("Expected toast"); return
        }
        XCTAssertEqual(title, "Done")
        XCTAssertEqual(body, "Task finished")
        XCTAssertEqual(sid, "sess-1")
        XCTAssertEqual(url, "https://example.com")
    }

    // MARK: - MessageContent Parsing

    func testEventMessageParsesAsAssistantText() {
        // This is the exact format CLI sends via sendSessionEvent for /status, /cost, /plan
        let content: [String: Any] = [
            "role": "agent",
            "content": [
                "id": "event-uuid",
                "type": "event",
                "data": [
                    "type": "message",
                    "message": "Session: test-123\nPath: /some/path\nMode: remote"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let parsed = MessageContent.parse(from: content)
        guard case .assistantBlocks(let blocks) = parsed else {
            XCTFail("Expected .assistantBlocks, got \(parsed)"); return
        }
        XCTAssertEqual(blocks.count, 1)
        if case .text(let text) = blocks[0] {
            XCTAssertTrue(text.contains("Session: test-123"))
            XCTAssertTrue(text.contains("Path: /some/path"))
        } else {
            XCTFail("Expected .text block")
        }
    }

    func testEventMessageWithNonMessageTypeIsUnknown() {
        // Event type "switch" or "ready" should not render as text
        let content: [String: Any] = [
            "role": "agent",
            "content": [
                "id": "event-uuid",
                "type": "event",
                "data": [
                    "type": "switch",
                    "mode": "remote"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let parsed = MessageContent.parse(from: content)
        guard case .unknown = parsed else {
            XCTFail("Expected .unknown for non-message event type, got \(parsed)"); return
        }
    }

    func testEventMessageWithMissingDataIsUnknown() {
        let content: [String: Any] = [
            "role": "agent",
            "content": [
                "id": "event-uuid",
                "type": "event"
            ] as [String: Any]
        ]
        let parsed = MessageContent.parse(from: content)
        guard case .unknown = parsed else {
            XCTFail("Expected .unknown for event without data"); return
        }
    }

    func testOutputMessageStillParsesCorrectly() {
        // Ensure the existing "output" path still works after adding "event" handling
        let content: [String: Any] = [
            "role": "agent",
            "content": [
                "type": "output",
                "data": [
                    "type": "assistant",
                    "message": ["content": [["type": "text", "text": "Hello!"]]]
                ] as [String: Any]
            ] as [String: Any]
        ]
        let parsed = MessageContent.parse(from: content)
        guard case .assistantBlocks(let blocks) = parsed else {
            XCTFail("Expected .assistantBlocks"); return
        }
        if case .text(let t) = blocks[0] {
            XCTAssertEqual(t, "Hello!")
        } else {
            XCTFail("Expected .text block")
        }
    }

    func testSlashCommandRoutingField() {
        // Verify SlashCommand decodes with routing field
        let json = """
        {"name":"status","description":"Show session status","source":"builtin","routing":"remote"}
        """.data(using: .utf8)!
        let cmd = try? JSONDecoder().decode(SlashCommand.self, from: json)
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.routing, "remote")
    }

    func testSlashCommandRoutingFieldNilWhenMissing() {
        // Routing is optional — missing field should decode as nil
        let json = """
        {"name":"custom","description":"A custom command","source":"user"}
        """.data(using: .utf8)!
        let cmd = try? JSONDecoder().decode(SlashCommand.self, from: json)
        XCTAssertNotNil(cmd)
        XCTAssertNil(cmd?.routing)
    }

    // MARK: - Unknown

    func testParseUnknownType() {
        let data = json(["type": "some-future-event", "data": "whatever"])
        guard case .unknown(let type) = SyncEvent.parse(from: data) else {
            XCTFail("Expected unknown"); return
        }
        XCTAssertEqual(type, "some-future-event")
    }

    func testParseInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(SyncEvent.parse(from: data))
    }

    func testParseMissingType() {
        let data = json(["sessionId": "sess-1"])
        XCTAssertNil(SyncEvent.parse(from: data))
    }

    // MARK: - Decoder key strategy verification

    func testMessageDecodesWithCamelCaseKeys() {
        // Server sends camelCase — verify convertFromSnakeCase doesn't break it
        let msgDict: [String: Any] = [
            "id": "msg-1",
            "seq": 5,
            "localId": "local-1",        // camelCase
            "createdAt": 1709900000000,   // camelCase
            "content": ["role": "user", "content": "test"]
        ]
        let msgData = try! JSONSerialization.data(withJSONObject: msgDict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let msg = try? decoder.decode(DecryptedMessage.self, from: msgData)
        XCTAssertNotNil(msg, "camelCase keys should decode with convertFromSnakeCase")
        XCTAssertEqual(msg?.localId, "local-1")
        XCTAssertEqual(msg?.createdAt, 1709900000000)
    }

    func testMessageDecodesWithSnakeCaseKeys() {
        // If server ever sends snake_case — verify it also works
        let msgDict: [String: Any] = [
            "id": "msg-1",
            "seq": 5,
            "local_id": "local-1",         // snake_case
            "created_at": 1709900000000,    // snake_case
            "content": ["role": "user", "content": "test"]
        ]
        let msgData = try! JSONSerialization.data(withJSONObject: msgDict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let msg = try? decoder.decode(DecryptedMessage.self, from: msgData)
        XCTAssertNotNil(msg, "snake_case keys should decode with convertFromSnakeCase")
        XCTAssertEqual(msg?.localId, "local-1")
    }
}
