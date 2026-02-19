import Foundation

/// HTTP client for communicating with the Python MLX server.
/// Supports request cancellation — when the user types during an in-flight
/// LLM request, callers should invoke `cancelCurrentRequest()` so the
/// previous request is torn down immediately.
final class LLMClient {
    private let baseURL: String
    private let session: URLSession

    /// The in-flight data task for correct/elaborate requests.
    private var currentTask: URLSessionDataTask?

    /// Protects `currentTask` from concurrent access.
    private let lock = NSLock()

    init(baseURL: String = Configuration.llmBaseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
    }

    // MARK: - Cancellation

    /// Cancel the currently in-flight correct/elaborate request, if any.
    /// Safe to call from any thread.
    func cancelCurrentRequest() {
        lock.lock()
        let task = currentTask
        currentTask = nil
        lock.unlock()
        task?.cancel()
    }

    // MARK: - Public API

    /// Send a correction request and return the corrected text.
    /// Any previously in-flight request is cancelled automatically.
    func correct(text: String, tone: Tone, styleHint: String? = nil) async throws -> LLMResponse {
        guard let body = PromptBuilder.correctionPayload(text: text, tone: tone, styleHint: styleHint) else {
            throw LLMClientError.invalidPayload
        }
        return try await post(endpoint: "/v1/correct", body: body)
    }

    /// Send an elaboration request and return the elaborated text.
    /// Any previously in-flight request is cancelled automatically.
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

        // Cancel any previously in-flight request before starting a new one.
        cancelCurrentRequest()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Create a URLSessionDataTask so we can cancel it later.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                let task = self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let data = data, let response = response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: LLMClientError.invalidResponse)
                    }
                }

                // Store the task for possible cancellation.
                self.lock.lock()
                self.currentTask = task
                self.lock.unlock()

                task.resume()
            }
        } catch {
            // Clear the current task reference on failure.
            lock.lock()
            currentTask = nil
            lock.unlock()

            // Rethrow cancellation as URLError(.cancelled) for callers.
            if (error as? URLError)?.code == .cancelled {
                throw URLError(.cancelled)
            }
            if (error as NSError).domain == NSURLErrorDomain,
               (error as NSError).code == NSURLErrorCancelled {
                throw URLError(.cancelled)
            }
            throw error
        }

        // Request finished — clear the tracked task.
        lock.lock()
        currentTask = nil
        lock.unlock()

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
