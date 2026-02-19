import ApplicationServices
import Carbon
import Foundation

/// Callback type for keystroke events.
typealias KeystrokeCallback = (_ character: String, _ keyCode: UInt16, _ flags: CGEventFlags) -> Void

/// Monitors keystrokes using a listen-only CGEventTap. Never blocks or modifies input.
final class KeystrokeMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: KeystrokeCallback?

    /// Called when the global hotkey Cmd+Shift+G is pressed.
    var onToggleHotkey: (() -> Void)?

    /// Start monitoring keystrokes. Must be called on the main thread.
    func start(callback: @escaping KeystrokeCallback) {
        self.callback = callback

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: KeystrokeMonitor.eventTapCallback,
            userInfo: userInfo
        ) else {
            print("[KeystrokeMonitor] Failed to create event tap. Check Input Monitoring permissions.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[KeystrokeMonitor] Event tap active.")
    }

    /// Stop monitoring keystrokes.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        callback = nil
        print("[KeystrokeMonitor] Event tap stopped.")
    }

    /// The C-function callback for CGEventTap.
    private static let eventTapCallback: CGEventTapCallBack = {
        (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in

        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo = userInfo {
                let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passRetained(event)
        }

        guard let userInfo = userInfo else {
            return Unmanaged.passRetained(event)
        }

        let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .keyDown {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            // Detect Cmd+Shift+G (keyCode 5) for global toggle hotkey
            if keyCode == 5
                && flags.contains(.maskCommand)
                && flags.contains(.maskShift) {
                DispatchQueue.main.async {
                    monitor.onToggleHotkey?()
                }
                return Unmanaged.passRetained(event)
            }

            let chars = keyStringFromEvent(event)
            monitor.callback?(chars, keyCode, flags)
        }

        return Unmanaged.passRetained(event)
    }

    /// Extract the character string from a CGEvent.
    private static func keyStringFromEvent(_ event: CGEvent) -> String {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return "" }

        var buffer = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        return String(utf16CodeUnits: buffer, count: length)
    }
}

// MARK: - Well-known key codes

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
