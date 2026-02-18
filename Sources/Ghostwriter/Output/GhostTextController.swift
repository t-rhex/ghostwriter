import ApplicationServices
import Foundation

/// Manages ghost text (elaboration suggestions) — appends as selected text, accept on Tab, dismiss on typing.
final class GhostTextController {
    private var activeGhostText: String?
    private var activeElement: AXUIElement?
    private var originalText: String?
    private var cursorPosition: Int?

    /// Whether ghost text is currently displayed.
    var isActive: Bool { activeGhostText != nil }

    /// Show ghost text by appending it to the current text and selecting only the appended part.
    /// The selected (highlighted) portion can be accepted with Tab or dismissed by typing.
    func showGhostText(_ ghostText: String, in element: AXUIElement, currentText: String) {
        // Ensure a space between original text and ghost text
        let needsSpace = !currentText.isEmpty
            && !currentText.hasSuffix(" ")
            && !currentText.hasSuffix("\n")
            && !ghostText.hasPrefix(" ")
            && !ghostText.hasPrefix("\n")
        let paddedGhost = needsSpace ? " " + ghostText : ghostText

        // Store state for dismiss/accept
        self.activeGhostText = paddedGhost
        self.activeElement = element
        self.originalText = currentText
        self.cursorPosition = currentText.utf16.count

        // Build full text = original + ghost continuation
        let fullText = currentText + paddedGhost

        // Set the full text
        let setResult = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, fullText as CFTypeRef
        )
        guard setResult == .success else {
            print("[GhostText] Failed to set text value.")
            clearState()
            return
        }

        // Select only the ghost portion (so it appears highlighted)
        var selectionRange = CFRange(
            location: currentText.utf16.count,
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

        print("[GhostText] Showed: \"\(ghostText.prefix(60))\"")
    }

    /// Accept the ghost text (move cursor to end, deselecting it).
    func accept() {
        guard let element = activeElement, let original = originalText, let ghost = activeGhostText else { return }

        let acceptedText = original + ghost

        // Re-set the text value explicitly so the Tab character that passes through
        // (listen-only tap can't block it) gets overwritten
        AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, acceptedText as CFTypeRef
        )

        // Move cursor to end
        var range = CFRange(location: acceptedText.utf16.count, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, rangeValue
            )
        }

        // After a short delay, clean up any tab character that snuck in
        let el = element
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            var currentValue: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &currentValue)
            if let current = currentValue as? String, current != acceptedText {
                // Remove trailing tab/whitespace the keystroke added
                let cleaned = current.replacingOccurrences(of: "\t", with: "", range: current.range(of: "\t", options: .backwards))
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

    /// Dismiss the ghost text (restore original text and cursor position).
    func dismiss() {
        guard let element = activeElement, let original = originalText else {
            clearState()
            return
        }

        // Restore original text (removes the ghost portion)
        AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, original as CFTypeRef
        )

        // Restore cursor to where it was (end of original text)
        if let pos = cursorPosition {
            var range = CFRange(location: pos, length: 0)
            if let rangeValue = AXValueCreate(.cfRange, &range) {
                AXUIElementSetAttributeValue(
                    element, kAXSelectedTextRangeAttribute as CFString, rangeValue
                )
            }
        }

        print("[GhostText] Dismissed.")
        clearState()
    }

    private func clearState() {
        activeGhostText = nil
        activeElement = nil
        originalText = nil
        cursorPosition = nil
    }
}
