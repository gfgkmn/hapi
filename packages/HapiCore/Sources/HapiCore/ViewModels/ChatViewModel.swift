import Foundation
import SwiftUI
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [DecryptedMessage] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var hasMore = false
    @Published var isLoadingOlder = false
    @Published var error: String?
    @Published var session: Session?
    @Published var scrollToBottomTrigger = 0
    @Published var preserveScrollId: String?
    @Published var isAborting = false
    @Published var attachments: [PendingAttachment] = []
    @Published var slashCommands: [SlashCommand] = []

    var isConnected: Bool { syncCoordinator.isConnected }

    private let api: APIClient
    private let store: LocalStore
    let syncCoordinator: SyncCoordinator
    let sessionId: String

    private var oldestSeq: Int?
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    init(api: APIClient, store: LocalStore, syncCoordinator: SyncCoordinator, sessionId: String) {
        self.api = api
        self.store = store
        self.syncCoordinator = syncCoordinator
        self.sessionId = sessionId

        // Forward syncCoordinator changes so isConnected triggers view updates
        syncCoordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Subscribe to messages changes for this session
        syncCoordinator.events
            .filter { [sessionId] event in
                switch event {
                case .messagesChanged(let sid) where sid == sessionId: return true
                case .sessionDetailChanged(let sid) where sid == sessionId: return true
                default: return false
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .messagesChanged:
                    Task { @MainActor in
                        await self.reloadMessagesFromStore()
                    }
                case .sessionDetailChanged:
                    Task { @MainActor in
                        await self.reloadSessionDetail()
                        await self.loadSlashCommands()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }

        // Subscribe to message events for this session
        syncCoordinator.subscribeToSession(sessionId)

        // Show cached immediately
        let cached = await store.loadMessages(for: sessionId)
        if !cached.isEmpty {
            messages = cached
        }

        isLoading = messages.isEmpty
        error = nil
        async let sessionFetch = api.fetchSession(id: sessionId)
        async let messagesFetch = api.fetchMessages(sessionId: sessionId, limit: 50)
        do {
            let (s, resp) = try await (sessionFetch, messagesFetch)
            session = s
            let merged = await store.ingestMessages(for: sessionId, messages: resp.messages)
            messages = merged
            hasMore = resp.page.hasMore
            oldestSeq = resp.messages.first?.seq
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func unload() {
        syncCoordinator.unsubscribeFromSession()
        stopPolling()
    }

    func loadOlder() async {
        guard hasMore, !isLoadingOlder, let beforeSeq = oldestSeq else { return }
        isLoadingOlder = true

        // Remember the topmost message so we can scroll back to it
        let anchorId = messages.first?.id

        do {
            let resp = try await api.fetchMessages(sessionId: sessionId, limit: 50, beforeSeq: beforeSeq)
            let merged = await store.ingestMessages(for: sessionId, messages: resp.messages)
            messages = merged
            hasMore = resp.page.hasMore
            oldestSeq = resp.messages.first?.seq

            // Tell the view to restore scroll to the previous top message
            if let anchorId {
                preserveScrollId = anchorId
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingOlder = false
    }

    // MARK: - Send (optimistic)

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        isSending = true

        // Snapshot attachments to send
        let attachmentsToSend: [AttachmentMetadata]? = attachments.isEmpty ? nil : attachments.compactMap { a in
            guard let path = a.path else {
                print("[Send] Skipping attachment \(a.filename) — no upload path (upload failed?)")
                return nil
            }
            return AttachmentMetadata(id: a.id, filename: a.filename, mimeType: a.mimeType, size: a.size, path: path)
        }
        print("[Send] Sending with \(attachmentsToSend?.count ?? 0) attachments: \(attachmentsToSend?.map(\.filename) ?? [])")
        let sentAttachmentIds = Set(attachments.map(\.id))

        // Create optimistic message
        let localId = UUID().uuidString
        let userContent: [String: Any] = ["role": "user", "content": trimmed.isEmpty ? "(attachments)" : trimmed]
        let optimistic = DecryptedMessage(
            id: localId,
            seq: nil,
            localId: localId,
            content: AnyCodable(userContent),
            createdAt: Date().timeIntervalSince1970 * 1000,
            status: .sending
        )

        messages = await store.appendOptimisticMessage(for: sessionId, message: optimistic)
        scrollToBottomTrigger += 1

        do {
            try await api.sendMessage(sessionId: sessionId, text: trimmed.isEmpty ? "" : trimmed, localId: localId, attachments: attachmentsToSend)
            messages = await store.updateMessageStatus(for: sessionId, localId: localId, status: .sent)
            attachments.removeAll { sentAttachmentIds.contains($0.id) }
        } catch {
            messages = await store.updateMessageStatus(for: sessionId, localId: localId, status: .failed)
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

    // MARK: - Session Actions

    func abort() async {
        guard !isAborting else { return }
        isAborting = true
        do {
            try await api.abortSession(id: sessionId)
            session = try await api.fetchSession(id: sessionId)
        } catch {
            self.error = error.localizedDescription
        }
        isAborting = false
    }

    func setPermissionMode(_ mode: String) async {
        do {
            try await api.setPermissionMode(sessionId: sessionId, mode: mode)
            session = try await api.fetchSession(id: sessionId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setModelMode(_ model: String) async {
        do {
            try await api.setModelMode(sessionId: sessionId, model: model)
            session = try await api.fetchSession(id: sessionId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Attachments

    func addAttachment(url: URL) async {
        let filename = url.lastPathComponent
        let mimeType = Self.mimeType(for: url)
        let id = UUID().uuidString

        guard url.startAccessingSecurityScopedResource() || true else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            self.error = "Failed to read file"
            return
        }

        var pending = PendingAttachment(
            id: id,
            filename: filename,
            mimeType: mimeType,
            size: data.count,
            path: nil,
            isUploading: true,
            error: nil,
            previewData: mimeType.hasPrefix("image/") ? data : nil
        )
        attachments.append(pending)

        let base64 = data.base64EncodedString()
        print("[Attach] Uploading \(filename) (\(data.count) bytes, base64: \(base64.count) chars)")
        do {
            let resp = try await api.uploadFile(sessionId: sessionId, filename: filename, content: base64, mimeType: mimeType)
            print("[Attach] Upload success — path: \(resp.path)")
            if let idx = attachments.firstIndex(where: { $0.id == id }) {
                attachments[idx].path = resp.path
                attachments[idx].isUploading = false
            }
        } catch {
            if case APIError.badStatus(let code, let data) = error {
                print("[Attach] Upload FAILED: HTTP \(code) — \(String(data: data, encoding: .utf8) ?? "?")")
            } else {
                print("[Attach] Upload FAILED: \(error)")
            }
            if let idx = attachments.firstIndex(where: { $0.id == id }) {
                attachments[idx].isUploading = false
                attachments[idx].error = error.localizedDescription
            }
        }
    }

    func removeAttachment(id: String) async {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = attachments[idx]
        attachments.remove(at: idx)
        if let path = attachment.path {
            try? await api.deleteUploadFile(sessionId: sessionId, path: path)
        }
    }

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "swift": return "text/x-swift"
        case "js": return "text/javascript"
        case "ts": return "text/typescript"
        case "json": return "application/json"
        case "md": return "text/markdown"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Slash Commands

    /// Offline fallback — covers core + commonly used CLI commands so the
    /// popup is useful even when the server is unreachable.
    private static let offlineFallback: [SlashCommand] = [
        SlashCommand(name: "agents", description: "Switch or list available agents", source: "builtin", content: nil, pluginName: nil, routing: "local"),
        SlashCommand(name: "clear", description: "Clear conversation history", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "compact", description: "Compact conversation context", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "cost", description: "Show session cost", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "fast", description: "Toggle fast output mode", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "fork", description: "Create a copy of the current session", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "hooks", description: "Show configured hook settings", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "insights", description: "Show project insights and observations", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "mcp", description: "Manage MCP server connections", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "memory", description: "View or edit CLAUDE.md memory files", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "plugins", description: "Manage installed plugins", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "resume", description: "Resume a previous session", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "rewind", description: "Undo the last message or turn", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "skills", description: "List available slash command skills", source: "builtin", content: nil, pluginName: nil, routing: "local"),
        SlashCommand(name: "status", description: "Show session status", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "task", description: "Manage background tasks", source: "builtin", content: nil, pluginName: nil, routing: "remote"),
        SlashCommand(name: "todos", description: "Show current task list and progress", source: "builtin", content: nil, pluginName: nil, routing: "local"),
    ]

    func loadSlashCommands() async {
        do {
            let remote = try await api.fetchSlashCommands(sessionId: sessionId)
            slashCommands = Self.merge(remote: remote, fallback: Self.offlineFallback)
        } catch {
            slashCommands = Self.offlineFallback
        }
    }

    /// Merge server commands with the offline fallback so every fallback
    /// command is always present.  Server versions win when names overlap;
    /// any extra server commands (user/plugin) are appended at the end.
    private static func merge(remote: [SlashCommand], fallback: [SlashCommand]) -> [SlashCommand] {
        let remoteByName = Dictionary(remote.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        // Start with fallback list, replacing with server version when available
        var merged = fallback.map { cmd in remoteByName[cmd.name] ?? cmd }
        let fallbackNames = Set(fallback.map(\.name))
        // Append any server-only commands not in the fallback
        for cmd in remote where !fallbackNames.contains(cmd.name) {
            merged.append(cmd)
        }
        return merged
    }

    // MARK: - Command Routing

    /// Single entry point for slash commands and regular messages.
    /// Routes local commands to client-side handling; everything else goes to the server.
    func executeCommand(_ text: String) async {
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if resolveRouting(cmd) {
            // Show user bubble locally (status: .sent, no server round-trip)
            let localId = UUID().uuidString
            let userContent: [String: Any] = ["role": "user", "content": text]
            let optimistic = DecryptedMessage(
                id: localId, seq: nil, localId: localId,
                content: AnyCodable(userContent),
                createdAt: Date().timeIntervalSince1970 * 1000,
                status: .sent
            )
            messages = await store.appendOptimisticMessage(for: sessionId, message: optimistic)
            handleLocalCommand(text)
            scrollToBottomTrigger += 1
        } else {
            await send(text: text)
        }
    }

    /// Returns true if the command should be handled locally (not sent to server).
    private func resolveRouting(_ cmd: String) -> Bool {
        guard cmd.hasPrefix("/") else { return false }
        let name = String(cmd.dropFirst().split(separator: " ").first ?? "")
        if let command = slashCommands.first(where: { $0.name == name }) {
            return command.routing == "local"
        }
        return false  // unknown → remote
    }

    // MARK: - Local Command Handling

    /// Handles commands routed as "local" — injects a card into the chat.
    @discardableResult
    func handleLocalCommand(_ text: String) -> Bool {
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch cmd {
        case "/todos":
            injectLocalCard(title: "Todos", body: buildTodosBody())
            return true
        case "/skills":
            injectLocalCard(title: "Available Commands", body: buildSkillsBody())
            return true
        case "/agents":
            injectLocalCard(title: "Agent", body: buildAgentBody())
            return true
        default:
            return false
        }
    }

    // MARK: - Local card builders

    private func buildStatusBody() -> String {
        guard let s = session else { return "No session data available." }
        var lines: [String] = []
        if let flavor = s.metadata?.flavor { lines.append("Agent:       \(flavor)") }
        if let model = s.modelMode, model != "default" {
            lines.append("Model:       \(model)")
        } else {
            lines.append("Model:       default")
        }
        if let perm = s.permissionMode { lines.append("Mode:        \(perm)") }
        lines.append("Active:      \(s.active ? "yes" : "no")")
        if let path = s.metadata?.path { lines.append("Path:        \(path)") }
        if let host = s.metadata?.host { lines.append("Host:        \(host)") }
        if let ver = s.metadata?.version { lines.append("Version:     \(ver)") }
        if let os = s.metadata?.os { lines.append("OS:          \(os)") }
        if let todo = s.todoProgress { lines.append("Todos:       \(todo.completed)/\(todo.total)") }
        if let created = s.createdAt {
            let dur = Int(s.updatedAt - created)
            let mins = dur / 60; let secs = dur % 60
            lines.append("Duration:    \(mins)m \(secs)s")
        }
        return lines.isEmpty ? "No status data available." : lines.joined(separator: "\n")
    }

    private func buildTodosBody() -> String {
        guard let todos = session?.todos, !todos.isEmpty else {
            return "No todos in this session."
        }
        var lines: [String] = []
        if let prog = session?.todoProgress {
            lines.append("\(prog.completed)/\(prog.total) completed")
            lines.append("──────────────────────────")
        }
        for todo in todos {
            let icon: String
            switch todo.status {
            case "completed": icon = "[x]"
            case "in_progress": icon = "[~]"
            default: icon = "[ ]"
            }
            lines.append("\(icon) \(todo.content)")
        }
        return lines.joined(separator: "\n")
    }

    private func buildSkillsBody() -> String {
        if slashCommands.isEmpty { return "No commands loaded." }
        return slashCommands.map { cmd in
            let desc = cmd.description ?? ""
            return "/\(cmd.name)  \(desc)"
        }.joined(separator: "\n")
    }

    private func buildAgentBody() -> String {
        let flavor = session?.metadata?.flavor ?? "unknown"
        return "Current agent: \(flavor)"
    }

    // MARK: - Inject local message

    private func injectLocalCard(title: String, body: String) {
        let text = "\(title)\n──────────────────────────\n\(body)"
        let textBlock: [String: String] = ["type": "text", "text": text]
        let messageDict: [String: Any] = ["content": [textBlock]]
        let dataDict: [String: Any] = ["type": "assistant", "message": messageDict]
        let innerContent: [String: Any] = ["type": "output", "data": dataDict]
        let content: [String: Any] = ["role": "agent", "content": innerContent]

        let msg = DecryptedMessage(
            id: UUID().uuidString, seq: nil, localId: nil,
            content: AnyCodable(content),
            createdAt: Date().timeIntervalSince1970 * 1000 + 1,
            status: .sent
        )
        Task {
            messages = await store.appendOptimisticMessage(for: sessionId, message: msg)
            scrollToBottomTrigger += 1
        }
    }

    func filteredCommands(for query: String) -> [SlashCommand] {
        let term = query.lowercased()
        if term.isEmpty { return slashCommands }
        return slashCommands
            .compactMap { cmd -> (SlashCommand, Int)? in
                let name = cmd.name.lowercased()
                if name == term { return (cmd, 0) }
                if name.hasPrefix(term) { return (cmd, 1) }
                if name.contains(term) { return (cmd, 2) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    // MARK: - Polling Fallback

    /// Polls for new messages every 3s when SSE is not connected.
    /// Ensures real-time feel even without SSE.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard let self, !Task.isCancelled else { break }
                if !self.isConnected {
                    await self.pollForUpdates()
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollForUpdates() async {
        do {
            let resp = try await api.fetchMessages(sessionId: sessionId, limit: 50)
            let merged = await store.ingestMessages(for: sessionId, messages: resp.messages)
            let oldLastId = messages.last?.id
            messages = merged
            // Auto-scroll if newest message changed
            if merged.last?.id != oldLastId {
                scrollToBottomTrigger += 1
            }
            // Also refresh session state and slash commands
            session = try? await api.fetchSession(id: sessionId)
            await loadSlashCommands()
        } catch {}
    }

    // MARK: - Private

    private func reloadMessagesFromStore() async {
        let updated = await store.loadMessages(for: sessionId)
        let oldLastId = messages.last?.id
        messages = updated
        if updated.last?.id != oldLastId {
            scrollToBottomTrigger += 1
        }
    }

    private func reloadSessionDetail() async {
        session = try? await api.fetchSession(id: sessionId)
    }
}
