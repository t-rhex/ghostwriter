import Foundation

/// Accumulates typed characters into a buffer for processing.
final class KeystrokeBuffer {
    private var buffer: [String] = []
    private let lock = NSLock()

    /// Append a character to the buffer.
    func append(_ character: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(character)
    }

    /// Get the current buffer content as a single string.
    var content: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.joined()
    }

    /// Get the number of characters in the buffer.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Whether the buffer is empty.
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.isEmpty
    }

    /// Clear the buffer and return its contents.
    @discardableResult
    func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        let result = buffer.joined()
        buffer.removeAll()
        return result
    }

    /// Handle a delete keypress — remove the last character if present.
    func handleDelete() {
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty {
            buffer.removeLast()
        }
    }

    /// Clear the buffer without returning contents.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}
