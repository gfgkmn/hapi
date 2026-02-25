import Foundation

/// Connects to the HAPI SSE endpoint and publishes parsed SyncEvents.
///
/// Usage:
///   let sse = SSEClient(baseURL: url, token: jwt)
///   for await event in sse.events() { ... }
///
final class SSEClient: NSObject {
    private let baseURL: URL
    private let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - Public AsyncStream API

    func events() -> AsyncStream<SyncEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.connect(continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func connect(continuation: AsyncStream<SyncEvent>.Continuation) async {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/events"),
                                       resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "visibility", value: "visible"),
            URLQueryItem(name: "all", value: "true")
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let session = URLSession(configuration: .default)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }

            var dataBuffer = ""
            var eventBuffer = ""

            for try await line in bytes.lines {
                if Task.isCancelled { break }

                if line.hasPrefix("data:") {
                    // Accumulate data lines
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    dataBuffer += (dataBuffer.isEmpty ? "" : "\n") + payload

                } else if line.isEmpty {
                    // Empty line = end of event
                    guard !dataBuffer.isEmpty else { continue }
                    if let data = dataBuffer.data(using: .utf8),
                       let event = SyncEvent.parse(from: data) {
                        continuation.yield(event)
                    }
                    dataBuffer = ""
                    eventBuffer = ""

                } else if line.hasPrefix("event:") {
                    eventBuffer = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                }
                // ":" lines are comments/heartbeats — ignore
            }
        } catch {
            // Stream ended or cancelled — caller decides whether to reconnect
        }
        continuation.finish()
    }
}
