import AppKit
import Foundation

// Ensure stdout flushes immediately (needed when not attached to a terminal)
setbuf(stdout, nil)
setbuf(stderr, nil)

print("[Ghostwriter] Ghostwriter v1.0.0")
print("[Ghostwriter] Checking permissions...")

// Poll for permissions instead of exiting — avoids crash loop under launchd
let maxWait: TimeInterval = 300 // 5 minutes
let pollInterval: TimeInterval = 5
let startTime = Date()

while !Permissions.checkAccessibility(prompt: false) || !Permissions.checkInputMonitoring() {
    let elapsed = Date().timeIntervalSince(startTime)
    if elapsed > maxWait {
        print("[Ghostwriter] Timed out waiting for permissions after 5 minutes. Exiting.")
        exit(1)
    }

    // Prompt once on first check
    if elapsed < pollInterval * 2 {
        Permissions.ensureAllPermissions()
    }

    print("[Ghostwriter] Waiting for permissions... (\(Int(elapsed))s elapsed)")
    Thread.sleep(forTimeInterval: pollInterval)
}

print("[Ghostwriter] All permissions granted.")

// Set up NSApplication for menubar support (must happen before creating status items)
let nsApp = NSApplication.shared
nsApp.setActivationPolicy(.accessory)  // Don't show in Dock

// Create and start the app
let app = GhostwriterApp()

// Handle SIGINT/SIGTERM gracefully
signal(SIGINT) { _ in
    print("\n[Ghostwriter] Shutting down...")
    exit(0)
}
signal(SIGTERM) { _ in
    print("\n[Ghostwriter] Shutting down...")
    exit(0)
}

app.start()

// Run the NSApplication run loop (replaces CFRunLoopRun).
// NSApplication.shared.run() drives the main CFRunLoop internally,
// so CGEventTap continues to work. NSStatusBar requires this.
nsApp.run()
