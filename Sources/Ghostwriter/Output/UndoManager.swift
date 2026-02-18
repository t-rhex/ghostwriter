import Foundation

/// Tracks corrections so Cmd+Z reverts are detected and handled properly.
final class CorrectionUndoManager {
    struct CorrectionRecord {
        let originalText: String
        let correctedText: String
        let timestamp: Date
        let textHash: Int
    }

    private var history: [CorrectionRecord] = []
    private let maxHistory = 50
    private let lock = NSLock()

    /// Record a correction that was applied.
    func recordCorrection(original: String, corrected: String) {
        lock.lock()
        defer { lock.unlock() }

        let record = CorrectionRecord(
            originalText: original,
            correctedText: corrected,
            timestamp: Date(),
            textHash: corrected.hashValue
        )
        history.append(record)

        // Trim old entries
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    /// Check if the given text matches a recently corrected text (to prevent correction loops).
    func wasRecentlyCorrected(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let hash = text.hashValue
        let cutoff = Date().addingTimeInterval(-10) // Within last 10 seconds
        return history.contains { $0.textHash == hash && $0.timestamp > cutoff }
    }

    /// Check if the user appears to have undone a correction.
    /// This is detected when the current text matches the original of a recent correction.
    func isUndoneCorrection(_ currentText: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = Date().addingTimeInterval(-30) // Within last 30 seconds
        return history.contains {
            $0.originalText == currentText && $0.timestamp > cutoff
        }
    }

    /// Clear all history.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        history.removeAll()
    }
}
