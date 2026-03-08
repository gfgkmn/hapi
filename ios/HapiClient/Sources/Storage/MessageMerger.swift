import Foundation

/// Pure-function message merge & dedup logic (ported from web's lib/messages.ts).
enum MessageMerger {

    /// Merge incoming messages into existing list.
    /// - Deduplicates by `id`.
    /// - Resolves optimistic messages: drops the optimistic copy when the server echoes
    ///   a message whose `localId` matches an existing optimistic message's `id`.
    /// - Falls back to time+role dedup for optimistic messages (any status, including
    ///   `.sending`) when the server echo doesn't carry `localId`.
    static func merge(existing: [DecryptedMessage], incoming: [DecryptedMessage]) -> [DecryptedMessage] {
        var byId: [String: DecryptedMessage] = [:]
        // Index existing messages
        for msg in existing {
            byId[msg.id] = msg
        }

        // Collect localIds from existing optimistic messages for resolution
        var optimisticIds: Set<String> = []
        for msg in existing where msg.isOptimistic {
            optimisticIds.insert(msg.id)
        }

        for msg in incoming {
            // If server message carries a localId that matches an optimistic message, drop the optimistic
            if let localId = msg.localId, optimisticIds.contains(localId) {
                byId.removeValue(forKey: localId)
                optimisticIds.remove(localId)
            }
            // Upsert by id (server version wins)
            byId[msg.id] = msg
        }

        // Content-based dedup: remove optimistic messages when a server message
        // with the same role AND same text content exists within 10s.
        // This is a safety fallback for when localId matching fails (e.g. SSE
        // delivers the echo before the API call returns without localId).
        // Each server message consumes at most ONE optimistic to prevent
        // rapid-fire messages from being incorrectly eaten.
        let serverMessages = byId.values.filter { !$0.isOptimistic }
        let remainingOptimistic = byId.values.filter { $0.isOptimistic }
        var consumedOptimisticIds: Set<String> = []
        for srv in serverMessages {
            let srvRole = extractRole(srv)
            let srvText = extractText(srv)
            guard srvRole != nil, srvText != nil else { continue }
            var bestId: String?
            var bestDelta: Double = .greatestFiniteMagnitude
            for opt in remainingOptimistic {
                guard !consumedOptimisticIds.contains(opt.id) else { continue }
                let delta = abs(srv.createdAt - opt.createdAt)
                if delta < 10000
                    && extractRole(opt) == srvRole
                    && extractText(opt) == srvText
                    && delta < bestDelta {
                    bestDelta = delta
                    bestId = opt.id
                }
            }
            if let matchedId = bestId {
                consumedOptimisticIds.insert(matchedId)
            }
        }
        for id in consumedOptimisticIds {
            byId.removeValue(forKey: id)
        }

        return sorted(Array(byId.values))
    }

    /// Extract the message role ("user" / "agent" / "assistant") for dedup matching.
    private static func extractRole(_ message: DecryptedMessage) -> String? {
        guard let dict = message.content?.value as? [String: Any] else { return nil }
        return dict["role"] as? String
    }

    /// Extract the text content for content-based dedup matching.
    private static func extractText(_ message: DecryptedMessage) -> String? {
        guard let dict = message.content?.value as? [String: Any] else { return nil }
        // User messages: { role: "user", content: "text" }
        if let text = dict["content"] as? String { return text }
        // User messages with structured content: { role: "user", content: { type: "text", text: "..." } }
        if let content = dict["content"] as? [String: Any], let text = content["text"] as? String { return text }
        return nil
    }

    /// Keep only the most recent `limit` messages.
    static func trim(_ messages: [DecryptedMessage], limit: Int) -> [DecryptedMessage] {
        guard messages.count > limit else { return messages }
        return Array(messages.suffix(limit))
    }

    /// Sort: both have seq → seq ascending; otherwise → createdAt → id.
    /// Optimistic messages (seq=nil) interleave by timestamp rather than sinking to the end.
    static func sorted(_ messages: [DecryptedMessage]) -> [DecryptedMessage] {
        messages.sorted { a, b in
            // If both have seq, use authoritative server ordering
            if let seqA = a.seq, let seqB = b.seq, seqA != seqB {
                return seqA < seqB
            }
            // Otherwise sort by createdAt (interleaves optimistic with server messages)
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            // At same timestamp, prefer server message before optimistic
            if a.seq != nil && b.seq == nil { return true }
            if a.seq == nil && b.seq != nil { return false }
            return a.id < b.id
        }
    }
}
