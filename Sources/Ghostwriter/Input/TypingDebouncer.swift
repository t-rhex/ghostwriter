import Foundation

/// Detects pauses in typing. Fires short-pause (correction) and long-pause (elaboration) callbacks.
final class TypingDebouncer {
    private let shortDelay: TimeInterval
    private let longDelay: TimeInterval

    private var shortTimer: DispatchSourceTimer?
    private var longTimer: DispatchSourceTimer?
    private let queue: DispatchQueue

    var onShortPause: (() -> Void)?
    var onLongPause: (() -> Void)?

    init(
        shortDelay: TimeInterval = Configuration.shortPauseInterval,
        longDelay: TimeInterval = Configuration.longPauseInterval,
        queue: DispatchQueue = DispatchQueue(label: "com.ghostwriter.debouncer")
    ) {
        self.shortDelay = shortDelay
        self.longDelay = longDelay
        self.queue = queue
    }

    /// Call on every keystroke to reset the debounce timers.
    func keystrokeReceived() {
        cancelTimers()

        // Short pause timer (correction)
        let short = DispatchSource.makeTimerSource(queue: queue)
        short.schedule(deadline: .now() + shortDelay)
        short.setEventHandler { [weak self] in
            self?.onShortPause?()
        }
        short.resume()
        shortTimer = short

        // Long pause timer (elaboration)
        let long = DispatchSource.makeTimerSource(queue: queue)
        long.schedule(deadline: .now() + longDelay)
        long.setEventHandler { [weak self] in
            self?.onLongPause?()
        }
        long.resume()
        longTimer = long
    }

    /// Cancel all pending timers (e.g., when user starts typing again).
    func cancelTimers() {
        shortTimer?.cancel()
        shortTimer = nil
        longTimer?.cancel()
        longTimer = nil
    }

    /// Cancel and clean up.
    func stop() {
        cancelTimers()
        onShortPause = nil
        onLongPause = nil
    }
}
