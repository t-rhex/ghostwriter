import Foundation

/// Response from the LLM server.
struct LLMResponse: Codable {
    let result: String
    let elapsedMs: Double

    enum CodingKeys: String, CodingKey {
        case result
        case elapsedMs = "elapsed_ms"
    }
}
