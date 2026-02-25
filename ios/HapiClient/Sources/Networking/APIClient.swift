import Foundation

// MARK: - Errors

enum APIError: LocalizedError {
    case unauthorized(String?)
    case badStatus(Int, Data)
    case decodingFailed(Error)
    case networkError(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized(let detail):
            if let detail { return "Unauthorized: \(detail)" }
            return "Unauthorized — check your access token"
        case .badStatus(let code, let data):
            let body = String(data: data, encoding: .utf8) ?? ""
            return "Server returned HTTP \(code): \(body)"
        case .decodingFailed(let e): return "Failed to decode response: \(e)"
        case .networkError(let e): return e.localizedDescription
        case .invalidURL: return "Invalid URL"
        }
    }
}

// MARK: - API Client

@MainActor
final class APIClient: ObservableObject {
    let baseURL: URL
    private var token: String

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    func updateToken(_ newToken: String) {
        self.token = newToken
    }

    // MARK: - Core request

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.httpBody = try encoder.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode == 401 {
            let detail = String(data: data, encoding: .utf8)
            throw APIError.unauthorized(detail)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    func requestVoid(
        _ path: String,
        method: String = "POST",
        body: (any Encodable)? = nil
    ) async throws {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            req.httpBody = try encoder.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 {
            let detail = String(data: data, encoding: .utf8)
            throw APIError.unauthorized(detail)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, data)
        }
    }

    // MARK: - Auth

    /// Exchange an access token for a short-lived JWT
    static func authenticate(baseURL: URL, accessToken: String) async throws -> AuthResponse {
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "api/auth", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AuthRequest(accessToken: trimmedToken))

        #if DEBUG
        print("[Auth] URL: \(url.absoluteString)")
        print("[Auth] Token length: \(trimmedToken.count), raw length: \(accessToken.count)")
        if let body = req.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
            print("[Auth] Body: \(bodyStr)")
        }
        #endif

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 {
            let detail = String(data: data, encoding: .utf8)
            throw APIError.unauthorized(detail)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, data)
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // MARK: - Sessions

    func fetchSessions() async throws -> [Session] {
        let response: SessionsResponse = try await request("api/sessions")
        return response.sessions
    }

    func fetchSession(id: String) async throws -> Session {
        let response: SessionResponse = try await request("api/sessions/\(id)")
        return response.session
    }

    func renameSession(id: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        try await requestVoid("api/sessions/\(id)", method: "PATCH", body: Body(name: name))
    }

    func deleteSession(id: String) async throws {
        try await requestVoid("api/sessions/\(id)", method: "DELETE")
    }

    func abortSession(id: String) async throws {
        try await requestVoid("api/sessions/\(id)/abort")
    }

    func archiveSession(id: String) async throws {
        try await requestVoid("api/sessions/\(id)/archive")
    }

    // MARK: - Machines

    func fetchMachines() async throws -> [Machine] {
        let response: MachinesResponse = try await request("api/machines")
        return response.machines
    }

    func spawnSession(machineId: String, body: SpawnRequest) async throws -> SpawnResponse {
        return try await request("api/machines/\(machineId)/spawn", method: "POST", body: body)
    }

    // MARK: - Messages

    func fetchMessages(sessionId: String, limit: Int = 50, beforeSeq: Int? = nil) async throws -> MessagesResponse {
        var path = "api/sessions/\(sessionId)/messages?limit=\(limit)"
        if let beforeSeq { path += "&beforeSeq=\(beforeSeq)" }
        return try await request(path)
    }

    func sendMessage(sessionId: String, text: String) async throws {
        // The API expects content as a string or structured blocks.
        // Sending as plain string for simplicity; adjust if server requires blocks.
        struct Body: Encodable { let content: String }
        try await requestVoid("api/sessions/\(sessionId)/messages", method: "POST", body: Body(content: text))
    }

    // MARK: - Permissions

    func approvePermission(sessionId: String, requestId: String) async throws {
        try await requestVoid("api/sessions/\(sessionId)/permissions/\(requestId)/approve")
    }

    func denyPermission(sessionId: String, requestId: String) async throws {
        try await requestVoid("api/sessions/\(sessionId)/permissions/\(requestId)/deny")
    }
}
