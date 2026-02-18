import Foundation

/// HTTP client for communicating with the Python MLX server.
final class LLMClient {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = Configuration.llmBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Send a correction request and return the corrected text.
    func correct(text: String, tone: Tone) async throws -> LLMResponse {
        guard let body = PromptBuilder.correctionPayload(text: text, tone: tone) else {
            throw LLMClientError.invalidPayload
        }
        return try await post(endpoint: "/v1/correct", body: body)
    }

    /// Send an elaboration request and return the elaborated text.
    func elaborate(text: String, tone: Tone) async throws -> LLMResponse {
        guard let body = PromptBuilder.elaborationPayload(text: text, tone: tone) else {
            throw LLMClientError.invalidPayload
        }
        return try await post(endpoint: "/v1/elaborate", body: body)
    }

    /// Check if the server process is up (responds to /health).
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Check if the server is fully ready (model loaded, can serve inference).
    func readyCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/ready") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func post(endpoint: String, body: Data) async throws -> LLMResponse {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw LLMClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMClientError.serverError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(LLMResponse.self, from: data)
    }
}

// MARK: - Errors

enum LLMClientError: Error, CustomStringConvertible {
    case invalidURL
    case invalidPayload
    case invalidResponse
    case serverError(statusCode: Int, body: String)

    var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidPayload: return "Failed to build request payload"
        case .invalidResponse: return "Invalid response from server"
        case .serverError(let code, let body): return "Server error \(code): \(body)"
        }
    }
}
