import ApplicationServices
import Dispatch
import Foundation

/// Manages ghost text (elaboration suggestions) — appends as selected text, accept on Tab, dismiss on typing.
final class GhostTextController {

    // MARK: - Dismissal tracking

    /// Describes why ghost text was dismissed.
    enum DismissalReason {
        /// The user continued typing, implicitly rejecting the suggestion.
        case typed
        /// The user pressed Escape (or another dismiss key) explicitly.
        case escaped
        /// The ghost text was automatically dismissed after the auto-dismiss interval elapsed.
        case timeout
    }

    // MARK: - Configuration

    /// Maximum number of characters allowed for ghost text. Suggestions longer than this are truncated.
    var maxGhostTextLength: Int = 200

    /// Seconds of inactivity before ghost text is automatically dismissed.
    var autoDismissInterval: TimeInterval = 10.0

    // MARK: - State

    private var activeGhostText: String?
    private var activeElement: AXUIElement?
    private var originalText: String?
    private var insertionPosition: Int?

    /// The reason the most recent ghost text was dismissed, if any.
    private(set) var lastDismissalReason: DismissalReason?

    /// Whether ghost text is currently displayed.
    var isActive: Bool { activeGhostText != nil }

    // MARK: - Auto-dismiss timer

    private var autoDismissTimer: DispatchSourceTimer?

    private func startAutoDismissTimer() {
        cancelAutoDismissTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + autoDismissInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isActive else { return }
            print("[GhostText] Auto-dismiss after \(self.autoDismissInterval)s timeout.")
            self.dismiss(reason: .timeout)
        }
        timer.resume()
        autoDismissTimer = timer
    }

    private func cancelAutoDismissTimer() {
        autoDismissTimer?.cancel()
        autoDismissTimer = nil
    }

    // MARK: - Show ghost text

    /// Show ghost text by appending it to the end of the current text and selecting the appended part.
    ///
    /// This is the original convenience method. It delegates to ``showInlinePreview(_:in:currentText:cursorPosition:)``
    /// with `cursorPosition: nil` so the ghost text is appended at the end.
    func showGhostText(_ ghostText: String, in element: AXUIElement, currentText: String) {
        showInlinePreview(ghostText, in: element, currentText: currentText, cursorPosition: nil)
    }

    /// Show ghost text inserted at an arbitrary cursor position (or appended at the end when `cursorPosition` is nil).
    ///
    /// - Parameters:
    ///   - previewText: The raw suggestion text. It will be truncated to ``maxGhostTextLength`` characters.
    ///   - element: The accessibility element of the focused text field.
    ///   - currentText: The current contents of the text field *before* the ghost text is injected.
    ///   - cursorPosition: UTF-16 offset where the ghost text should be inserted, or `nil` to append at the end.
    func showInlinePreview(
        _ previewText: String,
        in element: AXUIElement,
        currentText: String,
        cursorPosition: Int?
    ) {
        // Dismiss any existing ghost text first.
        if isActive {
            dismiss(reason: .typed)
        }

        // Truncate if needed.
        let truncated: String
        if previewText.count > maxGhostTextLength {
            let endIndex = previewText.index(previewText.startIndex, offsetBy: maxGhostTextLength)
            truncated = String(previewText[..<endIndex])
            print("[GhostText] Truncated suggestion from \(previewText.count) to \(maxGhostTextLength) chars.")
        } else {
            truncated = previewText
        }

        // Determine insertion point (UTF-16 offset).
        let insertAt: Int = cursorPosition ?? currentText.utf16.count

        // Build the substring parts around the insertion point, clamping to valid range.
        let clampedInsert = min(max(insertAt, 0), currentText.utf16.count)

        let prefixEnd = currentText.utf16.index(currentText.utf16.startIndex, offsetBy: clampedInsert)
        let prefix = String(currentText[currentText.startIndex..<prefixEnd])
        let suffix = String(currentText[prefixEnd...])

        // Determine if we need padding between the prefix and the ghost text.
        let needsLeadingSpace = !prefix.isEmpty
            && !prefix.hasSuffix(" ")
            && !prefix.hasSuffix("\n")
            && !truncated.hasPrefix(" ")
            && !truncated.hasPrefix("\n")

        // Determine if we need padding between the ghost text and the suffix.
        let needsTrailingSpace = !suffix.isEmpty
            && !suffix.hasPrefix(" ")
            && !suffix.hasPrefix("\n")
            && !truncated.hasSuffix(" ")
            && !truncated.hasSuffix("\n")

        let paddedGhost = (needsLeadingSpace ? " " : "") + truncated + (needsTrailingSpace ? " " : "")

        // Store state for dismiss / accept.
        self.activeGhostText = paddedGhost
        self.activeElement = element
        self.originalText = currentText
        self.insertionPosition = clampedInsert
        self.lastDismissalReason = nil

        // Build full text = prefix + ghost + suffix.
        let fullText = prefix + paddedGhost + suffix

        // Set the full text.
        let setResult = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, fullText as CFTypeRef
        )
        guard setResult == .success else {
            print("[GhostText] Failed to set text value.")
            clearState()
            return
        }

        // Select the ghost portion so it appears highlighted.
        // This works correctly for multi-line / multi-paragraph ghost text because
        // the selection range is expressed in UTF-16 offsets and AX handles newlines.
        var selectionRange = CFRange(
            location: prefix.utf16.count,
            length: paddedGhost.utf16.count
        )
        if let rangeVal = AXValueCreate(.cfRange, &selectionRange) {
            let selectResult = AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, rangeVal
            )
            if selectResult != .success {
                print("[GhostText] Warning: could not select ghost text range.")
            }
        }

        let previewSummary = truncated.prefix(80).replacingOccurrences(of: "\n", with: "\\n")
        let lineCount = truncated.components(separatedBy: "\n").count
        print("[GhostText] Showed (\(truncated.count) chars, \(lineCount) line(s)): \"\(previewSummary)\"")

        // Start the auto-dismiss timer.
        startAutoDismissTimer()
    }

    // MARK: - Accept

    /// Accept the ghost text (move cursor to end of inserted text, deselecting it).
    func accept() {
        cancelAutoDismissTimer()

        guard let element = activeElement,
              let original = originalText,
              let ghost = activeGhostText,
              let insertPos = insertionPosition else {
            clearState()
            return
        }

        // Rebuild the accepted text.
        let clampedInsert = min(max(insertPos, 0), original.utf16.count)
        let prefixEnd = original.utf16.index(original.utf16.startIndex, offsetBy: clampedInsert)
        let prefix = String(original[original.startIndex..<prefixEnd])
        let suffix = String(original[prefixEnd...])
        let acceptedText = prefix + ghost + suffix

        // Re-set the text value explicitly so the Tab character that passes through
        // (listen-only tap can't block it) gets overwritten.
        AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, acceptedText as CFTypeRef
        )

        // Move cursor to end of the inserted ghost text (right after the ghost, before the suffix).
        let cursorAfterGhost = prefix.utf16.count + ghost.utf16.count
        var range = CFRange(location: cursorAfterGhost, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, rangeValue
            )
        }

        // After a short delay, clean up any tab character that snuck in.
        let el = element
        let expected = acceptedText
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            var currentValue: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &currentValue)
            if let current = currentValue as? String, current != expected {
                // Remove trailing tab/whitespace the keystroke added.
                let cleaned = current.replacingOccurrences(
                    of: "\t", with: "",
                    range: current.range(of: "\t", options: .backwards)
                )
                if cleaned != current {
                    AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, cleaned as CFTypeRef)
                    var endRange = CFRange(location: cleaned.utf16.count, length: 0)
                    if let rv = AXValueCreate(.cfRange, &endRange) {
                        AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, rv)
                    }
                }
            }
        }

        print("[GhostText] Accepted.")
        clearState()
    }

    // MARK: - Dismiss

    /// Dismiss the ghost text (restore original text and cursor position).
    ///
    /// Callers that don't care about the reason can use the no-argument ``dismiss()`` overload
    /// which defaults to `.escaped`.
    func dismiss(reason: DismissalReason = .escaped) {
        cancelAutoDismissTimer()

        guard let element = activeElement, let original = originalText else {
            clearState()
            return
        }

        lastDismissalReason = reason

        // Restore original text (removes the ghost portion).
        AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, original as CFTypeRef
        )

        // Restore cursor to where it was.
        if let pos = insertionPosition {
            var range = CFRange(location: pos, length: 0)
            if let rangeValue = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(
                    element, kAXSelectedTextRangeAttribute as CFString, rangeValue
                )
            }
        }

        print("[GhostText] Dismissed (reason: \(reason)).")
        clearState()
    }

    // MARK: - Internals

    private func clearState() {
        activeGhostText = nil
        activeElement = nil
        originalText = nil
        insertionPosition = nil
    }
}
