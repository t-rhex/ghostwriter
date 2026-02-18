import Foundation

/// Builds request payloads for the LLM server.
enum PromptBuilder {
    /// Build a correction request body.
    static func correctionPayload(text: String, tone: Tone) -> Data? {
        let body: [String: String] = [
            "text": text,
            "tone": tone.systemPromptModifier,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Build an elaboration request body.
    static func elaborationPayload(text: String, tone: Tone) -> Data? {
        let body: [String: String] = [
            "text": text,
            "tone": tone.systemPromptModifier,
        ]
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// Truncate text to the current paragraph if it exceeds the max length.
    /// Returns the last paragraph or the tail of the text capped at maxLength.
    static func extractRelevantText(_ text: String, maxLength: Int = Configuration.maxTextLength) -> String {
        guard text.count > maxLength else { return text }

        // Try to find the last paragraph break
        let paragraphs = text.components(separatedBy: "\n\n")
        if let lastParagraph = paragraphs.last, !lastParagraph.isEmpty {
            return String(lastParagraph.suffix(maxLength))
        }

        // Fallback: take the tail
        return String(text.suffix(maxLength))
    }
}
