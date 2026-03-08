import Foundation

/// Thread-safe, file-backed cache for sessions and messages.
actor LocalStore {

    private let maxMessagesPerSession = 200
    private let maxCachedSessions = 100

    // In-memory caches
    private var sessionsCache: [Session]?
    private var messagesCache: [String: [DecryptedMessage]] = [:]

    // File system
    private let cacheDir: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("HapiStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Sessions

    func loadSessions() -> [Session] {
        if let cached = sessionsCache { return cached }
        guard let data = try? Data(contentsOf: sessionsFile),
              let sessions = try? decoder.decode([Session].self, from: data) else { return [] }
        sessionsCache = sessions
        return sessions
    }

    func storeSessions(_ sessions: [Session]) {
        let bounded = Array(sessions.prefix(maxCachedSessions))
        sessionsCache = bounded
        writeToDisk(bounded, file: sessionsFile)
    }

    func upsertSession(_ session: Session) {
        var sessions = loadSessions()
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        storeSessions(sessions)
    }

    func removeSession(id: String) {
        var sessions = loadSessions()
        sessions.removeAll { $0.id == id }
        storeSessions(sessions)
        // Remove associated message cache
        messagesCache.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: messagesFile(for: id))
    }

    // MARK: - Messages

    func loadMessages(for sessionId: String) -> [DecryptedMessage] {
        if let cached = messagesCache[sessionId] { return cached }
        guard let data = try? Data(contentsOf: messagesFile(for: sessionId)),
              let messages = try? decoder.decode([DecryptedMessage].self, from: data) else { return [] }
        messagesCache[sessionId] = messages
        return messages
    }

    func storeMessages(for sessionId: String, messages: [DecryptedMessage]) {
        let trimmed = MessageMerger.trim(messages, limit: maxMessagesPerSession)
        messagesCache[sessionId] = trimmed
        writeToDisk(trimmed, file: messagesFile(for: sessionId))
    }

    /// Merge a single SSE message into the cache.
    func ingestMessage(for sessionId: String, message: DecryptedMessage) -> [DecryptedMessage] {
        let existing = loadMessages(for: sessionId)
        let merged = MessageMerger.merge(existing: existing, incoming: [message])
        storeMessages(for: sessionId, messages: merged)
        return merged
    }

    /// Merge a batch of API-fetched messages into the cache.
    func ingestMessages(for sessionId: String, messages: [DecryptedMessage]) -> [DecryptedMessage] {
        let existing = loadMessages(for: sessionId)
        let merged = MessageMerger.merge(existing: existing, incoming: messages)
        storeMessages(for: sessionId, messages: merged)
        return merged
    }

    /// Append an optimistic message (pre-send).
    func appendOptimisticMessage(for sessionId: String, message: DecryptedMessage) -> [DecryptedMessage] {
        var existing = loadMessages(for: sessionId)
        existing.append(message)
        let sorted = MessageMerger.sorted(existing)
        storeMessages(for: sessionId, messages: sorted)
        return sorted
    }

    /// Update the status of an optimistic message.
    func updateMessageStatus(for sessionId: String, localId: String, status: MessageStatus) -> [DecryptedMessage] {
        var messages = loadMessages(for: sessionId)
        if let idx = messages.firstIndex(where: { $0.id == localId }) {
            messages[idx].status = status
        }
        storeMessages(for: sessionId, messages: messages)
        return messages
    }

    /// Delete all cached data (logout).
    func clearAll() {
        sessionsCache = nil
        messagesCache = [:]
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Remove message cache files for sessions no longer in the sessions list.
    func pruneStaleMessageCaches() {
        let sessionIds = Set(loadSessions().map(\.id))
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("messages-") {
            let name = file.deletingPathExtension().lastPathComponent
            let sessionId = String(name.dropFirst("messages-".count))
            if !sessionIds.contains(sessionId) {
                try? fm.removeItem(at: file)
                messagesCache.removeValue(forKey: sessionId)
            }
        }
    }

    // MARK: - Private helpers

    private var sessionsFile: URL {
        cacheDir.appendingPathComponent("sessions.json")
    }

    private func messagesFile(for sessionId: String) -> URL {
        cacheDir.appendingPathComponent("messages-\(sessionId).json")
    }

    private func writeToDisk<T: Encodable>(_ value: T, file: URL) {
        guard let data = try? encoder.encode(value) else { return }
        // Encode in-actor (fast), write in background (slow I/O off the actor)
        Task.detached(priority: .utility) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
