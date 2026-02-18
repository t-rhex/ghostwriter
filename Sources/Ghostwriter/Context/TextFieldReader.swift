import ApplicationServices
import AppKit
import Foundation

/// Reads the currently focused text field via AXUIElement accessibility APIs.
final class TextFieldReader {
    /// Result of reading a text field.
    struct TextFieldInfo {
        let text: String
        let selectedRange: CFRange?
        let isSecure: Bool
        let element: AXUIElement
        let isBrowserField: Bool
    }

    /// Read the focused text field of the frontmost application.
    func readFocusedTextField() -> TextFieldInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get focused UI element
        var focusedValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusedResult == .success, let focused = focusedValue else {
            // Chrome/Electron apps need accessibility enabled explicitly
            if isBrowserApp(app.bundleIdentifier) {
                print("[TextFieldReader] Browser returned no focused element — enable accessibility in Chrome: chrome://accessibility")
            }
            return nil
        }

        let element = focused as! AXUIElement

        // Check if it's a secure (password) field
        if isSecureField(element) {
            return TextFieldInfo(text: "", selectedRange: nil, isSecure: true, element: element, isBrowserField: false)
        }

        // Get the role
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""

        let isBrowser = isBrowserApp(app.bundleIdentifier)

        // Log the role for debugging
        if isBrowser {
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = subroleValue as? String ?? "none"
            print("[TextFieldReader] Browser element — role=\(role) subrole=\(subrole)")
        }

        // Try to read text via kAXValueAttribute (works for native fields and some web fields)
        if hasValueAttribute(element) {
            var textValue: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
            if textResult == .success, let text = textValue as? String {
                let selectedRange = readSelectedRange(element)
                return TextFieldInfo(text: text, selectedRange: selectedRange, isSecure: false, element: element, isBrowserField: isBrowser)
            }
        }

        // Fallback: try web content text reading strategies (parameterized attributes, children)
        if let text = readWebContentText(element) {
            let selectedRange = readSelectedRange(element)
            return TextFieldInfo(text: text, selectedRange: selectedRange, isSecure: false, element: element, isBrowserField: true)
        }

        if isBrowser {
            print("[TextFieldReader] All strategies failed for browser element role=\(role)")
        }

        return nil
    }

    // MARK: - Private

    /// Try to read text from a web content element.
    /// Web editors (Gmail, Google Docs) often don't expose kAXValueAttribute but do
    /// support kAXStringForRangeParameterizedAttribute or child element traversal.
    private func readWebContentText(_ element: AXUIElement) -> String? {
        // Strategy 1: Try kAXValueAttribute on the element itself
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }

        // Strategy 2: Try to get text via number of characters + string-for-range
        var countValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countValue) == .success,
           let count = countValue as? Int, count > 0 {
            var cfRange = CFRange(location: 0, length: min(count, Configuration.maxTextLength))
            if let rangeValue = AXValueCreate(.cfRange, &cfRange) {
                var stringValue: AnyObject?
                let result = AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    rangeValue,
                    &stringValue
                )
                if result == .success, let text = stringValue as? String {
                    return text
                }
            }
        }

        // Strategy 3: Try to read children (some web editors expose text as child static text elements)
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            var parts: [String] = []
            for child in children.prefix(50) {
                var childValue: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childValue) == .success,
                   let text = childValue as? String, !text.isEmpty {
                    parts.append(text)
                }
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
            }
        }

        return nil
    }

    private func readSelectedRange(_ element: AXUIElement) -> CFRange? {
        var rangeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if let rangeRef = rangeValue {
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                return range
            }
        }
        return nil
    }

    /// Check if the element is a password/secure field.
    private func isSecureField(_ element: AXUIElement) -> Bool {
        var subroleValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        if result == .success, let subrole = subroleValue as? String {
            return subrole == kAXSecureTextFieldSubrole
        }
        return false
    }

    /// Check if the element has a value attribute (broad check for text-bearing elements).
    private func hasValueAttribute(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return result == .success && value is String
    }

    /// Check if the bundle ID belongs to a known browser.
    private func isBrowserApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        let browsers = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",  // Arc
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
        ]
        return browsers.contains(id)
    }
}
