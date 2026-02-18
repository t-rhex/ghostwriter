import AppKit
import Foundation

/// Detects the frontmost application and its bundle identifier.
final class AppDetector {
    /// Returns the bundle identifier of the currently active application.
    func frontmostAppBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Returns the localized name of the currently active application.
    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Returns the PID of the currently active application.
    func frontmostAppPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}
