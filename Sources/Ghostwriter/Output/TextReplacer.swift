import ApplicationServices
import AppKit
import Foundation

/// Replaces text in the focused text field via AXUIElement.
/// Uses three strategies in order: AX value set, AX selected text, clipboard paste.
final class TextReplacer {

    enum ReplacementStrategy {
        case axValue           // Set kAXValueAttribute directly
        case axSelectedText    // Select all, set kAXSelectedTextAttribute
        case clipboardPaste    // Copy to clipboard, Cmd+A, Cmd+V
    }

    /// Replace the full text of the given AX element.
    /// Returns the strategy that succeeded, or nil if all failed.
    @discardableResult
    func replaceFullText(in element: AXUIElement, with newText: String) -> ReplacementStrategy? {
        // Strategy 1: Direct value replacement
        if setAXValue(element, value: newText) {
            return .axValue
        }

        // Strategy 2: Select all + replace selected text
        if selectAllAndReplace(element, with: newText) {
            return .axSelectedText
        }

        // Strategy 3: Clipboard paste fallback
        if clipboardPaste(newText) {
            return .clipboardPaste
        }

        print("[TextReplacer] All replacement strategies failed.")
        return nil
    }

    /// Insert text at the current cursor position as a selection (for ghost text).
    func insertAsSelection(in element: AXUIElement, text: String) -> Bool {
        // Get current cursor position
        var rangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        )
        guard rangeResult == .success else { return false }

        // Insert the text at cursor
        let insertResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        guard insertResult == .success else { return false }

        // Now select the inserted text so it appears highlighted
        var range = CFRange(location: 0, length: 0)
        if let rv = rangeValue, AXValueGetValue(rv as! AXValue, .cfRange, &range) {
            let insertionPoint = range.location
            var selectionRange = CFRange(location: insertionPoint, length: text.utf16.count)
            if let rangeVal = AXValueCreate(.cfRange, &selectionRange) {
                AXUIElementSetAttributeValue(
                    element, kAXSelectedTextRangeAttribute as CFString, rangeVal
                )
            }
        }

        return true
    }

    // MARK: - Private Strategies

    private func setAXValue(_ element: AXUIElement, value: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, value as CFTypeRef
        )
        return result == .success
    }

    private func selectAllAndReplace(_ element: AXUIElement, with newText: String) -> Bool {
        // Get the full text length
        var textValue: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &textValue
        )
        guard textResult == .success, let text = textValue as? String else { return false }

        // Select all text
        var selectRange = CFRange(location: 0, length: text.utf16.count)
        guard let rangeValue = AXValueCreate(.cfRange, &selectRange) else { return false }

        let selectResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, rangeValue
        )
        guard selectResult == .success else { return false }

        // Replace selection
        let replaceResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, newText as CFTypeRef
        )
        return replaceResult == .success
    }

    private func clipboardPaste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Select all (Cmd+A)
        postKeyEvent(keyCode: 0, flags: .maskCommand)
        usleep(50_000) // 50ms

        // Paste (Cmd+V)
        postKeyEvent(keyCode: 9, flags: .maskCommand)
        usleep(50_000) // 50ms

        // Restore previous clipboard
        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        return true
    }

    private func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
