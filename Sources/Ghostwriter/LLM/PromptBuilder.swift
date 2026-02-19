import Foundation

/// Builds request payloads for the LLM server.
enum PromptBuilder {
    /// Build a correction request body.
    /// Optionally includes a style hint derived from recent corrections for consistency.
    static func correctionPayload(text: String, tone: Tone, styleHint: String? = nil) -> Data? {
        var toneModifier = tone.systemPromptModifier
        if let hint = styleHint {
            toneModifier += " " + hint
        }
        let body: [String: String] = [
            "text": text,
            "tone": toneModifier,
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

    // MARK: - Paragraph Extraction

    /// Extract the paragraph containing the cursor position.
    ///
    /// Paragraphs are delimited by double newlines (`\n\n`). If no double-newline
    /// boundaries exist, single newlines are used as a fallback delimiter.
    /// When `cursorPosition` is nil the last paragraph is returned.
    ///
    /// - Parameters:
    ///   - fullText: The entire text content of the field.
    ///   - cursorPosition: UTF-16 offset of the cursor (matching `CFRange.location`
    ///     from accessibility APIs), or nil to default to the last paragraph.
    /// - Returns: A tuple of the paragraph string and its `Range<String.Index>` within `fullText`.
    static func extractParagraphAtCursor(
        _ fullText: String,
        cursorPosition: Int?
    ) -> (paragraph: String, range: Range<String.Index>) {
        guard !fullText.isEmpty else {
            let r = fullText.startIndex..<fullText.endIndex
            return (fullText, r)
        }

        // Determine paragraph boundaries. Prefer double-newline splits; fall back to single newlines.
        let delimiter: String
        if fullText.contains("\n\n") {
            delimiter = "\n\n"
        } else {
            delimiter = "\n"
        }

        // Build an array of (paragraphText, rangeInFullText) tuples.
        var segments: [(text: String, range: Range<String.Index>)] = []
        var searchStart = fullText.startIndex

        while searchStart < fullText.endIndex {
            if let delimRange = fullText.range(of: delimiter, range: searchStart..<fullText.endIndex) {
                let segmentRange = searchStart..<delimRange.lowerBound
                segments.append((String(fullText[segmentRange]), segmentRange))
                searchStart = delimRange.upperBound
            } else {
                // Last segment — no trailing delimiter
                let segmentRange = searchStart..<fullText.endIndex
                segments.append((String(fullText[segmentRange]), segmentRange))
                break
            }
        }

        // If splitting produced nothing (shouldn't happen), return the full text.
        guard !segments.isEmpty else {
            let r = fullText.startIndex..<fullText.endIndex
            return (fullText, r)
        }

        // Convert the cursor position from a UTF-16 offset to a String.Index.
        if let cursorUTF16 = cursorPosition {
            let clampedOffset = min(max(cursorUTF16, 0), fullText.utf16.count)
            if let cursorIndex = fullText.utf16.index(
                fullText.utf16.startIndex,
                offsetBy: clampedOffset,
                limitedBy: fullText.utf16.endIndex
            ).flatMap({ String.Index($0, within: fullText) }) {
                // Find the segment whose range contains the cursor.
                for segment in segments {
                    // The cursor may sit right at the end of a segment (e.g. after the last char).
                    if segment.range.contains(cursorIndex) || cursorIndex == segment.range.upperBound {
                        return (segment.text, segment.range)
                    }
                }
            }
        }

        // Fallback: return the last non-empty segment, or just the last segment.
        if let last = segments.last(where: { !$0.text.isEmpty }) {
            return (last.text, last.range)
        }
        let last = segments[segments.count - 1]
        return (last.text, last.range)
    }

    /// Truncate text to the current paragraph if it exceeds the max length.
    /// Uses cursor-aware paragraph extraction when possible, then caps at maxLength.
    static func extractRelevantText(
        _ text: String,
        cursorPosition: Int? = nil,
        maxLength: Int = Configuration.maxTextLength
    ) -> String {
        guard text.count > maxLength else { return text }

        let (paragraph, _) = extractParagraphAtCursor(text, cursorPosition: cursorPosition)

        if !paragraph.isEmpty {
            return String(paragraph.suffix(maxLength))
        }

        // Fallback: take the tail
        return String(text.suffix(maxLength))
    }
}
