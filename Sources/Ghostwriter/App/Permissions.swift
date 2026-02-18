import ApplicationServices
import Foundation

enum Permissions {
    /// Check if Accessibility permission is granted.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Check Accessibility permission, optionally prompting the user.
    static func checkAccessibility(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Check if Input Monitoring permission is granted by attempting to create an event tap.
    static func checkInputMonitoring() -> Bool {
        // Attempt to create a passive event tap — if it succeeds, we have permission
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }

    /// Run all permission checks. Returns true if all required permissions are granted.
    @discardableResult
    static func ensureAllPermissions() -> Bool {
        let accessibility = checkAccessibility(prompt: true)
        let inputMonitoring = checkInputMonitoring()

        if !accessibility {
            print("[Ghostwriter] Accessibility permission not granted.")
            print("  → System Settings > Privacy & Security > Accessibility")
        }
        if !inputMonitoring {
            print("[Ghostwriter] Input Monitoring permission not granted.")
            print("  → System Settings > Privacy & Security > Input Monitoring")
        }

        return accessibility && inputMonitoring
    }
}
