import Foundation

/// Connects to the HAPI SSE endpoint using URLSessionDataDelegate for real-time
/// event delivery (equivalent to browser EventSource). Automatically reconnects
/// with exponential backoff on disconnection.
final class SSEClient: NSObject, URLSessionDataDelegate {
    private let baseURL: URL
    private let tokenProvider: () -> String
    private let sessionId: String?

    // Connection state
    private var continuation: AsyncStream<SyncEvent>.Continuation?
    private var dataTask: URLSessionDataTask?
    private var urlSession: URLSession?
    private var dataBuffer = ""
    private var didReceiveEvent = false
    private var isCancelled = false

    // Retry state
    private var retryDelay: TimeInterval = 1
    private let maxRetryDelay: TimeInterval = 30

    init(baseURL: URL, tokenProvider: @escaping () -> String, sessionId: String? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.sessionId = sessionId
    }

    // MARK: - Public AsyncStream API

    func events() -> AsyncStream<SyncEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.continuation = continuation
            self.isCancelled = false
            self.retryDelay = 1
            self.connect()

            continuation.onTermination = { [weak self] _ in
                self?.isCancelled = true
                self?.disconnect()
            }
        }
    }

    // MARK: - Connection management

    private func connect() {
        guard !isCancelled else {
            continuation?.finish()
            return
        }

        let token = tokenProvider()
        guard !token.isEmpty else {
            print("[SSE] ❌ Token is empty, retrying…")
            scheduleReconnect(wasConnected: false)
            return
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/events"),
            resolvingAgainstBaseURL: true
        ) else {
            print("[SSE] ❌ Invalid URL components from baseURL: \(baseURL)")
            return
        }

        var queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "visibility", value: "visible"),
        ]
        if let sessionId {
            queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
        } else {
            queryItems.append(URLQueryItem(name: "all", value: "true"))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            print("[SSE] ❌ Failed to build URL from components")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 300

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        dataBuffer = ""
        didReceiveEvent = false

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        dataTask = urlSession?.dataTask(with: request)
        dataTask?.resume()

        // Show host only (not full URL with token)
        print("[SSE] → Connecting to \(url.host ?? url.absoluteString)…")
    }

    private func disconnect() {
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    private func scheduleReconnect(wasConnected: Bool) {
        guard !isCancelled else {
            continuation?.finish()
            return
        }

        if wasConnected {
            retryDelay = 1
        }

        print("[SSE] ⏳ Reconnecting in \(retryDelay)s…")

        let delay = retryDelay
        retryDelay = min(retryDelay * 2, maxRetryDelay)

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.disconnect()
            self?.connect()
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            print("[SSE] ❌ Non-HTTP response")
            completionHandler(.cancel)
            return
        }

        if (200..<300).contains(http.statusCode) {
            print("[SSE] ✅ Connected (HTTP \(http.statusCode))")
            completionHandler(.allow)
        } else {
            print("[SSE] ❌ HTTP \(http.statusCode)")
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        dataBuffer += text

        while let range = dataBuffer.range(of: "\n\n") {
            let eventText = String(dataBuffer[dataBuffer.startIndex..<range.lowerBound])
            dataBuffer = String(dataBuffer[range.upperBound...])
            processSSEEvent(eventText)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[SSE] ⚠️ Stream error: \(error.localizedDescription)")
        } else {
            print("[SSE] ⚠️ Stream ended")
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return
        }

        scheduleReconnect(wasConnected: didReceiveEvent)
    }

    // MARK: - SSE Event Parsing

    private func processSSEEvent(_ text: String) {
        var dataLines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }

        guard !dataLines.isEmpty else { return }
        let payload = dataLines.joined(separator: "\n")
        if let data = payload.data(using: .utf8),
           let event = SyncEvent.parse(from: data) {
            didReceiveEvent = true
            continuation?.yield(event)
        }
    }
}
