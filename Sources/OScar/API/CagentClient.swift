import Foundation

/// HTTP client for the cagent REST API.
/// Connects to the cagent server started with `cagent serve api <agent.yaml>`.
actor CagentClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(host: String = "127.0.0.1", port: Int = 8080) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Health

    func healthCheck() async -> Bool {
        guard let url = URL(string: "/api/sessions", relativeTo: baseURL) else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Sessions

    func listSessions() async throws -> [SessionSummary] {
        let url = baseURL.appendingPathComponent("api/sessions")
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try decoder.decode([SessionSummary].self, from: data)
    }

    func createSession(_ request: CreateSessionRequest) async throws -> SessionSummary {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/sessions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response)
        return try decoder.decode(SessionSummary.self, from: data)
    }

    func deleteSession(id: String) async throws {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/sessions/\(id)"))
        urlRequest.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: urlRequest)
        try validate(response)
    }

    func updateTitle(sessionId: String, title: String) async throws {
        var urlRequest = URLRequest(
            url: baseURL.appendingPathComponent("api/sessions/\(sessionId)/title")
        )
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(["title": title])
        let (_, response) = try await session.data(for: urlRequest)
        try validate(response)
    }

    // MARK: - Streaming Chat

    /// Sends messages to the agent and returns an AsyncStream of events via SSE.
    /// - Parameters:
    ///   - sessionId: The session to send messages to.
    ///   - agentName: The agent name defined in the YAML config (default: "root").
    ///   - messages: The messages to send (typically just the new user message).
    nonisolated func chat(
        sessionId: String,
        agentName: String = "root",
        messages: [ChatMessage]
    ) -> AsyncStream<CagentEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    let url = URL(
                        string: "/api/sessions/\(sessionId)/agent/\(agentName)",
                        relativeTo: self.baseURL
                    )!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 300
                    request.httpBody = try JSONEncoder().encode(messages)

                    let (asyncBytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in asyncBytes.lines {
                        if let event = SSEParser.parse(line: line) {
                            continuation.yield(event)
                            if case .streamStopped = event { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(message: error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Private

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CagentError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw CagentError.httpError(http.statusCode)
        }
    }
}

enum CagentError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "HTTP error \(code)"
        case .serverNotRunning: return "cagent server is not running"
        }
    }
}
