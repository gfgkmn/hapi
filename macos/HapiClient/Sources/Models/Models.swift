import Foundation
import SwiftUI

// MARK: - Auth

struct AuthRequest: Encodable {
    let accessToken: String
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct User: Codable {
    let id: Int
    let username: String?
    let firstName: String?
    let lastName: String?
}

// MARK: - Session

typealias PermissionMode = String  // "default"|"acceptEdits"|"bypassPermissions"|"plan"|"read-only"|"safe-yolo"|"yolo"
typealias ModelMode = String       // "default"|"sonnet"|"opus"

enum PermissionModeOption: String, CaseIterable, Identifiable {
    case `default`, acceptEdits, bypassPermissions, plan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .default: "Default"
        case .acceptEdits: "Accept Edits"
        case .bypassPermissions: "Yolo"
        case .plan: "Plan Mode"
        }
    }
}

enum ModelModeOption: String, CaseIterable, Identifiable {
    case `default`, sonnet, opus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .default: "Default"
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        }
    }
}

// MARK: - Attachments

struct AttachmentMetadata: Codable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
    let path: String
}

struct UploadFileResponse: Decodable {
    let success: Bool
    let path: String
}

struct PendingAttachment: Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
    var path: String?
    var isUploading: Bool
    var error: String?
    var previewData: Data?
}

struct Session: Codable, Identifiable, Hashable {
    let id: String
    let active: Bool
    let thinking: Bool
    let activeAt: TimeInterval
    let updatedAt: TimeInterval
    let metadata: SessionMetadata?
    let modelMode: ModelMode?
    let pendingRequestsCount: Int?
    let todoProgress: TodoProgress?

    // Full session fields (present in GET /sessions/:id but not in list)
    let namespace: String?
    let seq: Int?
    let createdAt: TimeInterval?
    let metadataVersion: Int?
    let agentState: AgentState?
    let agentStateVersion: Int?
    let thinkingAt: TimeInterval?
    let todos: [TodoItem]?
    let permissionMode: PermissionMode?

    /// Convenience: returns the display name for the session
    var displayName: String {
        metadata?.name ?? metadata?.path ?? id
    }

    /// Convenience: path shown in subtitle
    var path: String? { metadata?.path }

    /// Pending permission requests that need user decision
    var pendingRequests: [String: AgentStateRequest] {
        agentState?.requests ?? [:]
    }

    // MARK: - Hashable

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TodoProgress: Codable {
    let completed: Int
    let total: Int
}

struct SessionMetadata: Codable {
    let path: String?
    let name: String?
    let machineId: String?
    let flavor: String?
    // Full session fields (not in summary)
    let host: String?
    let version: String?
    let os: String?
    let lifecycleState: String?
    let lifecycleStateSince: TimeInterval?
}

struct AgentState: Codable {
    let controlledByUser: Bool?
    let requests: [String: AgentStateRequest]?
    let completedRequests: [String: AgentStateCompletedRequest]?
}

struct AgentStateRequest: Codable {
    let tool: String
    let arguments: AnyCodable?
    let createdAt: TimeInterval?
}

struct AgentStateCompletedRequest: Codable {
    let tool: String
    let arguments: AnyCodable?
    let createdAt: TimeInterval?
    let completedAt: TimeInterval?
    let status: String  // "canceled"|"denied"|"approved"
    let reason: String?
    let decision: String?  // "approved"|"approved_for_session"|"denied"|"abort"
}

struct TodoItem: Codable, Identifiable {
    let id: String
    let content: String
    let status: String   // "pending"|"in_progress"|"completed"
    let priority: String // "high"|"medium"|"low"
}

// MARK: - Messages

struct DecryptedMessage: Codable, Identifiable {
    let id: String
    let seq: Int?
    let localId: String?
    let content: AnyCodable?
    let createdAt: TimeInterval
    var status: MessageStatus?

    var isOptimistic: Bool { localId != nil && id == localId }

    // Derived from content — excluded from Codable via CodingKeys
    var parsedContent: MessageContent? {
        guard let raw = content?.value else { return nil }
        return MessageContent.parse(from: raw)
    }

    enum CodingKeys: String, CodingKey {
        case id, seq, localId, content, createdAt, status
    }
}

/// Simplified representation of Claude message content
enum MessageContent {
    case userText(String)
    case assistantBlocks([ContentBlock])
    case unknown(Any)

    static func parse(from raw: Any) -> MessageContent {
        guard let dict = raw as? [String: Any],
              let role = dict["role"] as? String,
              let content = dict["content"] else {
            return .unknown(raw)
        }

        // User messages: { role: "user", content: "text" } or { role: "user", content: { type: "text", text: "..." } }
        if role == "user" {
            if let text = content as? String {
                return .userText(text)
            }
            if let obj = content as? [String: Any],
               let text = obj["text"] as? String {
                return .userText(text)
            }
            if let blocks = content as? [[String: Any]],
               let first = blocks.first,
               let text = first["text"] as? String {
                return .userText(text)
            }
            return .unknown(raw)
        }

        // Agent messages: { role: "agent", content: { type: "output", data: { type: "assistant"|"user", message: { content: ... } } } }
        if role == "agent" {
            guard let contentDict = content as? [String: Any],
                  let contentType = contentDict["type"] as? String else {
                return .unknown(raw)
            }

            // Event messages: { type: "event", data: { type: "message", message: "..." } }
            // Sent by CLI for /status, /cost, /plan responses via sendSessionEvent
            // Event messages: { type: "event", data: { type: "message", message: "..." } }
            // Sent by CLI for /status, /cost, /plan responses via sendSessionEvent
            if contentType == "event" {
                if let data = contentDict["data"] as? [String: Any],
                   let dataType = data["type"] as? String,
                   dataType == "message",
                   let message = data["message"] as? String {
                    return .assistantBlocks([.text(message)])
                }
                return .unknown(raw)
            }

            if contentType == "output" {
                guard let data = contentDict["data"] as? [String: Any],
                      let dataType = data["type"] as? String else {
                    return .unknown(raw)
                }

                // Summary messages
                if dataType == "summary", let summary = data["summary"] as? String {
                    return .assistantBlocks([.text(summary)])
                }

                // System messages (skip)
                if dataType == "system" {
                    return .unknown(raw)
                }

                // Assistant or user output: { message: { content: ... } }
                guard let message = data["message"] as? [String: Any] else {
                    return .unknown(raw)
                }
                let msgContent = message["content"]

                if dataType == "assistant" {
                    if let blocks = msgContent as? [[String: Any]] {
                        let parsed = blocks.compactMap(ContentBlock.init)
                        return parsed.isEmpty ? .unknown(raw) : .assistantBlocks(parsed)
                    }
                    if let text = msgContent as? String {
                        return .assistantBlocks([.text(text)])
                    }
                }

                if dataType == "user" {
                    if let text = msgContent as? String {
                        return .userText(text)
                    }
                    // Tool results from user turns (agent output)
                    if let blocks = msgContent as? [[String: Any]] {
                        let parsed = blocks.compactMap(ContentBlock.init)
                        if !parsed.isEmpty {
                            return .assistantBlocks(parsed)
                        }
                    }
                    return .unknown(raw)
                }
            }

            return .unknown(raw)
        }

        // Fallback for role == "assistant" (direct Claude API format, if any)
        if role == "assistant" {
            if let blocks = content as? [[String: Any]] {
                return .assistantBlocks(blocks.compactMap(ContentBlock.init))
            }
            if let text = content as? String {
                return .assistantBlocks([.text(text)])
            }
        }

        return .unknown(raw)
    }
}

enum ContentBlock {
    case text(String)
    case toolUse(id: String, name: String, input: Any)
    case toolResult(toolUseId: String, content: Any)
    case reasoning(String)

    /// Look up a key trying both snake_case and camelCase variants.
    /// Handles JSONDecoder.convertFromSnakeCase mangling keys inside AnyCodable.
    private static func flexKey(_ dict: [String: Any], _ snakeKey: String) -> Any? {
        if let v = dict[snakeKey] { return v }
        let parts = snakeKey.split(separator: "_")
        guard parts.count > 1 else { return nil }
        let camelKey = String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return dict[camelKey]
    }

    init?(_ dict: [String: Any]) {
        guard let type_ = dict["type"] as? String else { return nil }
        switch type_ {
        case "text":
            guard let text = dict["text"] as? String else { return nil }
            self = .text(text)
        case "tool_use":
            let id = dict["id"] as? String ?? ""
            let name = dict["name"] as? String ?? ""
            let input = dict["input"] ?? [:]
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = Self.flexKey(dict, "tool_use_id") as? String ?? ""
            let content = dict["content"] ?? ""
            self = .toolResult(toolUseId: toolUseId, content: content)
        case "thinking":
            let text = dict["thinking"] as? String ?? ""
            self = .reasoning(text)
        default:
            return nil
        }
    }
}

// MARK: - Machine

struct Machine: Codable, Identifiable {
    let id: String
    let active: Bool
    let metadata: MachineMetadata?

    var displayLabel: String {
        metadata?.displayName ?? metadata?.host ?? id
    }
}

struct MachineMetadata: Codable {
    let host: String
    let platform: String?
    let happyCliVersion: String?
    let displayName: String?
}

struct MachinesResponse: Codable {
    let machines: [Machine]
}

// MARK: - Spawn

struct SpawnRequest: Encodable {
    let directory: String
    var agent: String?
    var model: String?
    var yolo: Bool?
    var sessionType: String?
    var worktreeName: String?
}

struct SpawnResponse: Decodable {
    let type: String           // "success" | "error"
    let sessionId: String?     // present when type == "success"
    let message: String?       // present when type == "error"
}

// MARK: - API Response Wrappers

struct SessionsResponse: Codable {
    let sessions: [Session]
}

struct SessionResponse: Codable {
    let session: Session
}

struct MessagesResponse: Codable {
    let messages: [DecryptedMessage]
    let page: MessagePage
}

struct MessagePage: Codable {
    let limit: Int
    let beforeSeq: Int?
    let nextBeforeSeq: Int?
    let hasMore: Bool
}

struct SendMessageRequest: Encodable {
    let text: String
    let localId: String?
    let attachments: [AttachmentMetadata]?
}

// MARK: - Slash Commands

struct SlashCommand: Codable, Identifiable {
    let name: String
    let description: String?
    let source: String          // "builtin" | "user" | "plugin"
    let content: String?
    let pluginName: String?
    let routing: String?        // "local" | "remote" — nil defaults to "remote"
    var id: String { name }
}

struct SlashCommandsResponse: Codable {
    let success: Bool
    let commands: [SlashCommand]?
}

// MARK: - SSE Events

enum SyncEvent {
    case sessionAdded(sessionId: String)
    case sessionUpdated(sessionId: String)
    case sessionRemoved(sessionId: String)
    case messageReceived(sessionId: String, message: DecryptedMessage)
    case machineUpdated(machineId: String)
    case toast(title: String, body: String, sessionId: String, url: String)
    case connectionChanged(status: String, subscriptionId: String?)
    case unknown(type: String)

    static func parse(from data: Data) -> SyncEvent? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = dict["type"] as? String else { return nil }

        switch type_ {
        case "session-added":
            guard let sessionId = dict["sessionId"] as? String else { return nil }
            return .sessionAdded(sessionId: sessionId)
        case "session-updated":
            guard let sessionId = dict["sessionId"] as? String else { return nil }
            return .sessionUpdated(sessionId: sessionId)
        case "session-removed":
            guard let sessionId = dict["sessionId"] as? String else { return nil }
            return .sessionRemoved(sessionId: sessionId)
        case "message-received":
            guard let sessionId = dict["sessionId"] as? String,
                  let msgDict = dict["message"],
                  let msgData = try? JSONSerialization.data(withJSONObject: msgDict)
            else { return nil }
            let msgDecoder = JSONDecoder()
            msgDecoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let msg = try? msgDecoder.decode(DecryptedMessage.self, from: msgData)
            else { return nil }
            return .messageReceived(sessionId: sessionId, message: msg)
        case "machine-updated":
            guard let machineId = dict["machineId"] as? String else { return nil }
            return .machineUpdated(machineId: machineId)
        case "toast":
            if let data = dict["data"] as? [String: Any],
               let title = data["title"] as? String,
               let body = data["body"] as? String,
               let sessionId = data["sessionId"] as? String,
               let url = data["url"] as? String {
                return .toast(title: title, body: body, sessionId: sessionId, url: url)
            }
            return nil
        case "connection-changed":
            let data = dict["data"] as? [String: Any]
            let status = data?["status"] as? String ?? "connected"
            let subscriptionId = data?["subscriptionId"] as? String
            return .connectionChanged(status: status, subscriptionId: subscriptionId)
        default:
            return .unknown(type: type_)
        }
    }
}

// MARK: - Utility: AnyCodable

/// Type-erased Codable wrapper for unknown JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = NSNull() }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let s = try? container.decode(String.self) { value = s }
        else if let a = try? container.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let o = try? container.decode([String: AnyCodable].self) {
            value = o.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let a as [Any]: try container.encode(a.map { AnyCodable($0) })
        case let o as [String: Any]: try container.encode(o.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
