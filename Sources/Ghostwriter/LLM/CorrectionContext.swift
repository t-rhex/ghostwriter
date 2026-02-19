import Foundation

/// Maintains a sliding window of recent corrections so the LLM can receive
/// style-consistency hints derived from the user's actual writing patterns.
///
/// Thread-safe — all public methods are guarded by an internal lock.
final class CorrectionContext {

    // MARK: - Types

    private struct Entry {
        let original: String
        let corrected: String
        let timestamp: Date
    }

    // MARK: - Properties

    private var recentCorrections: [Entry] = []
    private let maxEntries = 10
    private let maxAge: TimeInterval = 300  // 5 minutes
    private let lock = NSLock()

    // MARK: - Public API

    /// Record a correction pair. Old entries beyond `maxEntries` or `maxAge` are evicted.
    func record(original: String, corrected: String) {
        lock.lock()
        defer { lock.unlock() }

        recentCorrections.append(Entry(
            original: original,
            corrected: corrected,
            timestamp: Date()
        ))
        evictExpired()
        // Cap the total size
        if recentCorrections.count > maxEntries {
            recentCorrections.removeFirst(recentCorrections.count - maxEntries)
        }
    }

    /// Return non-expired correction pairs, oldest first.
    func recentExamples() -> [(original: String, corrected: String)] {
        lock.lock()
        defer { lock.unlock() }

        evictExpired()
        return recentCorrections.map { ($0.original, $0.corrected) }
    }

    /// Analyze the recent correction window and return a short style hint string
    /// for the LLM, or `nil` if there is not enough data to infer a pattern.
    ///
    /// Detected patterns include:
    /// - Contraction preference (expanded vs. contracted)
    /// - Formality level (formal vs. informal)
    /// - Average sentence length tendency
    /// - Emoji usage
    func styleHint() -> String? {
        lock.lock()
        defer { lock.unlock() }

        evictExpired()

        // Need at least 2 correction pairs to infer anything meaningful.
        guard recentCorrections.count >= 2 else { return nil }

        var hints: [String] = []

        // --- Contraction analysis ---
        let contractionPattern = #"(?i)\b(don't|doesn't|won't|can't|isn't|aren't|wasn't|weren't|shouldn't|wouldn't|couldn't|haven't|hasn't|hadn't|they're|we're|you're|it's|I'm|he's|she's|that's|there's|here's|let's|who's|what's)\b"#
        let expandedPattern = #"(?i)\b(do not|does not|will not|cannot|is not|are not|was not|were not|should not|would not|could not|have not|has not|had not|they are|we are|you are|it is|I am|he is|she is|that is|there is|here is|let us|who is|what is)\b"#

        var correctedContractions = 0
        var correctedExpanded = 0

        for entry in recentCorrections {
            correctedContractions += matchCount(entry.corrected, pattern: contractionPattern)
            correctedExpanded += matchCount(entry.corrected, pattern: expandedPattern)
        }

        let totalContractionSignals = correctedContractions + correctedExpanded
        if totalContractionSignals >= 2 {
            let contractionRatio = Double(correctedContractions) / Double(totalContractionSignals)
            if contractionRatio > 0.7 {
                hints.append("User prefers contractions (e.g. \"don't\" over \"do not\").")
            } else if contractionRatio < 0.3 {
                hints.append("User prefers expanded forms (e.g. \"do not\" over \"don't\").")
            }
        }

        // --- Sentence length analysis ---
        let allCorrectedText = recentCorrections.map(\.corrected).joined(separator: " ")
        let sentences = allCorrectedText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.count >= 3 {
            let avgWords = sentences.reduce(0) { sum, s in
                sum + s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
            } / sentences.count

            if avgWords <= 8 {
                hints.append("User tends toward short, concise sentences.")
            } else if avgWords >= 20 {
                hints.append("User tends toward longer, detailed sentences.")
            }
        }

        // --- Emoji usage ---
        var emojiCount = 0
        for entry in recentCorrections {
            emojiCount += entry.corrected.unicodeScalars.filter { $0.properties.isEmoji && !$0.isASCII }.count
        }
        if emojiCount >= 2 {
            hints.append("User includes emoji in their writing; preserve emoji where present.")
        }

        // --- Formality heuristic ---
        // Check for informal markers in corrected text.
        let informalMarkers = ["lol", "haha", "omg", "btw", "ngl", "tbh", "imo", "fwiw", "afaik"]
        var informalCount = 0
        for entry in recentCorrections {
            let lower = entry.corrected.lowercased()
            for marker in informalMarkers {
                if lower.contains(marker) {
                    informalCount += 1
                    break  // count at most once per entry
                }
            }
        }

        if informalCount > recentCorrections.count / 2 {
            hints.append("User writes informally; do not over-formalize.")
        }

        guard !hints.isEmpty else { return nil }
        return "Style notes from recent writing: " + hints.joined(separator: " ")
    }

    // MARK: - Private

    /// Remove entries older than `maxAge`. Must be called while holding `lock`.
    private func evictExpired() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        recentCorrections.removeAll { $0.timestamp < cutoff }
    }

    /// Count regex matches in a string.
    private func matchCount(_ string: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(string.startIndex..., in: string)
        return regex.numberOfMatches(in: string, range: range)
    }
}
