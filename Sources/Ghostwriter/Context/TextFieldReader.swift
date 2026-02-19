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
        let bundleID = app.bundleIdentifier

        // Route to browser-specific strategies when applicable
        if isSafari(bundleID) {
            return readSafariTextField(appElement: appElement, bundleID: bundleID)
                ?? readGenericTextField(appElement: appElement, bundleID: bundleID)
        }

        if isFirefox(bundleID) {
            return readFirefoxTextField(appElement: appElement, bundleID: bundleID)
                ?? readGenericTextField(appElement: appElement, bundleID: bundleID)
        }

        return readGenericTextField(appElement: appElement, bundleID: bundleID)
    }

    // MARK: - Browser-Specific Strategies

    /// Read the focused text field using Safari's AX tree structure.
    /// Safari exposes web content under AXWebArea rather than directly on the focused element.
    /// This walks the AXWebArea children to find the focused AXTextField or AXTextArea.
    private func readSafariTextField(appElement: AXUIElement, bundleID: String?) -> TextFieldInfo? {
        // First try to get the focused element directly — Safari sometimes cooperates
        var focusedValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        if focusedResult == .success, let focused = focusedValue {
            let element = focused as! AXUIElement
            let role = elementRole(element)

            // If Safari gave us a web text field directly, use it
            if role == kAXTextFieldRole || role == kAXTextAreaRole {
                if isSecureField(element) {
                    return TextFieldInfo(text: "", selectedRange: nil, isSecure: true, element: element, isBrowserField: true)
                }
                if let text = readTextFromElement(element) {
                    let selectedRange = readSelectedRange(element)
                    return TextFieldInfo(text: text, selectedRange: selectedRange, isSecure: false, element: element, isBrowserField: true)
                }
            }

            // Walk up or across to find AXWebArea, then search within it
            if let webArea = findWebArea(from: element) {
                if let result = findFocusedTextFieldInWebArea(webArea) {
                    return result
                }
            }
        }

        // Fallback: walk the app's AX tree to find AXWebArea
        var windowValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
           let window = windowValue {
            let windowElement = window as! AXUIElement
            if let webArea = findWebAreaInHierarchy(windowElement) {
                return findFocusedTextFieldInWebArea(webArea)
            }
        }

        print("[TextFieldReader] Safari: could not locate text field via AXWebArea strategy")
        return nil
    }

    /// Read the focused text field from Firefox.
    /// Firefox uses AXTextField/AXTextArea roles but may not respond to standard AX queries
    /// in the same way as Chromium. It sometimes requires reading AXSelectedText as a fallback
    /// and may expose the value through AXNumberOfCharacters + AXStringForRange instead of AXValue.
    private func readFirefoxTextField(appElement: AXUIElement, bundleID: String?) -> TextFieldInfo? {
        var focusedValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusedResult == .success, let focused = focusedValue else {
            print("[TextFieldReader] Firefox returned no focused element — check accessibility settings")
            return nil
        }

        let element = focused as! AXUIElement
        let role = elementRole(element)

        if isSecureField(element) {
            return TextFieldInfo(text: "", selectedRange: nil, isSecure: true, element: element, isBrowserField: true)
        }

        print("[TextFieldReader] Firefox element — role=\(role)")

        // Strategy 1: Try AXValue directly (works for simple text fields in Firefox)
        if hasValueAttribute(element) {
            var textValue: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
               let text = textValue as? String {
                let selectedRange = readSelectedRange(element)
                return TextFieldInfo(text: text, selectedRange: selectedRange, isSecure: false, element: element, isBrowserField: true)
            }
        }

        // Strategy 2: Try AXSelectedText — Firefox sometimes only exposes selected text
        var selectedTextValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
            return TextFieldInfo(text: selectedText, selectedRange: readSelectedRange(element), isSecure: false, element: element, isBrowserField: true)
        }

        // Strategy 3: Try parameterized text reading (AXStringForRange)
        if let text = readWebContentText(element) {
            let selectedRange = readSelectedRange(element)
            return TextFieldInfo(text: text, selectedRange: selectedRange, isSecure: false, element: element, isBrowserField: true)
        }

        print("[TextFieldReader] Firefox: all strategies failed for role=\(role)")
        return nil
    }

    /// Generic text field reading — used for Chromium-based browsers and non-browser apps.
    private func readGenericTextField(appElement: AXUIElement, bundleID: String?) -> TextFieldInfo? {
        // Get focused UI element
        var focusedValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusedResult == .success, let focused = focusedValue else {
            // Chrome/Electron apps need accessibility enabled explicitly
            if isBrowserApp(bundleID) {
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
        let role = elementRole(element)

        let isBrowser = isBrowserApp(bundleID)

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

    // MARK: - Safari AX Tree Helpers

    /// Find an AXWebArea element starting from the given element by walking the parent chain
    /// and then searching siblings, or by checking if the element itself is a web area.
    private func findWebArea(from element: AXUIElement) -> AXUIElement? {
        let role = elementRole(element)
        if role == "AXWebArea" { return element }

        // Walk up the parent chain looking for AXWebArea
        var current: AXUIElement = element
        for _ in 0..<20 {
            var parentValue: AnyObject?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
               let parent = parentValue {
                let parentElement = parent as! AXUIElement
                let parentRole = elementRole(parentElement)
                if parentRole == "AXWebArea" { return parentElement }
                current = parentElement
            } else {
                break
            }
        }
        return nil
    }

    /// Recursively search for an AXWebArea within the AX hierarchy of the given element.
    private func findWebAreaInHierarchy(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 10 else { return nil }

        let role = elementRole(element)
        if role == "AXWebArea" { return element }

        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(30) {
                if let webArea = findWebAreaInHierarchy(child, depth: depth + 1) {
                    return webArea
                }
            }
        }
        return nil
    }

    /// Search within an AXWebArea for the focused text field or text area.
    private func findFocusedTextFieldInWebArea(_ webArea: AXUIElement) -> TextFieldInfo? {
        // Try to find a focused text field within the web area's children (BFS)
        var queue: [AXUIElement] = [webArea]
        var visited = 0

        while !queue.isEmpty, visited < 200 {
            let current = queue.removeFirst()
            visited += 1

            let role = elementRole(current)

            // Check if this is a text-bearing element that is focused
            if role == kAXTextFieldRole || role == kAXTextAreaRole {
                // Check if this element has keyboard focus
                var focusedValue: AnyObject?
                if AXUIElementCopyAttributeValue(current, "AXFocused" as CFString, &focusedValue) == .success,
                   let isFocused = focusedValue as? Bool, isFocused {
                    if isSecureField(current) {
                        return TextFieldInfo(text: "", selectedRange: nil, isSecure: true, element: current, isBrowserField: true)
                    }
                    if let text = readTextFromElement(current) {
                        let selectedRange = readSelectedRange(current)
                        return TextFieldInfo(text: text, selectedRange: selectedRange, isSecure: false, element: current, isBrowserField: true)
                    }
                }
            }

            // Enqueue children
            var childrenValue: AnyObject?
            if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(30))
            }
        }

        return nil
    }

    /// Read text from a single element using AXValue, AXSelectedText, or parameterized range.
    private func readTextFromElement(_ element: AXUIElement) -> String? {
        // Try AXValue
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }

        // Try AXSelectedText as fallback
        var selectedValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
           let text = selectedValue as? String, !text.isEmpty {
            return text
        }

        // Try parameterized string-for-range
        var countValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countValue) == .success,
           let count = countValue as? Int, count > 0 {
            var cfRange = CFRange(location: 0, length: min(count, Configuration.maxTextLength))
            if let rangeValue = AXValueCreate(.cfRange, &cfRange) {
                var stringValue: AnyObject?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXStringForRangeParameterizedAttribute as CFString,
                    rangeValue,
                    &stringValue
                ) == .success, let text = stringValue as? String {
                    return text
                }
            }
        }

        return nil
    }

    /// Get the AX role string for an element.
    private func elementRole(_ element: AXUIElement) -> String {
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        return roleValue as? String ?? ""
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
            "com.apple.SafariTechnologyPreview",
            "org.mozilla.firefox",
            "org.mozilla.nightly",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",  // Arc
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
        ]
        return browsers.contains(id)
    }

    /// Check if the bundle ID belongs to Safari or Safari Technology Preview.
    private func isSafari(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return id == "com.apple.Safari" || id == "com.apple.SafariTechnologyPreview"
    }

    /// Check if the bundle ID belongs to Firefox or Firefox Nightly.
    private func isFirefox(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return id == "org.mozilla.firefox" || id == "org.mozilla.nightly"
    }
}
