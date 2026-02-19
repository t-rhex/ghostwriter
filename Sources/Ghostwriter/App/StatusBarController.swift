import AppKit

/// Manages the menubar status item for Ghostwriter, showing active/paused state
/// and providing a toggle action and quit option.
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    /// Whether Ghostwriter is currently paused.
    var isPaused: Bool = false {
        didSet {
            updateStatusItem()
        }
    }

    /// Called when the user toggles pause via the menu.
    var onToggle: (() -> Void)?

    init() {
        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Use SF Symbol if available, otherwise fall back to text
        if let image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Ghostwriter") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "Gw"
        }

        buildMenu()
        statusItem?.menu = menu
    }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()

        let stateItem = NSMenuItem(
            title: isPaused ? "Ghostwriter: Paused" : "Ghostwriter: Active",
            action: nil,
            keyEquivalent: ""
        )
        stateItem.tag = 100
        stateItem.isEnabled = false
        menu?.addItem(stateItem)

        menu?.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(
            title: "Toggle",
            action: #selector(toggleAction),
            keyEquivalent: "G"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        menu?.addItem(toggleItem)

        menu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu?.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleAction() {
        onToggle?()
    }

    @objc private func quitAction() {
        print("[Ghostwriter] Quit requested from menubar.")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Update

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if isPaused {
            // Dimmed appearance when paused
            button.appearsDisabled = true
            if button.image == nil {
                button.title = "Gw"
            }
        } else {
            // Normal appearance when active
            button.appearsDisabled = false
            if button.image == nil {
                button.title = "Gw"
            }
        }

        // Update the state label in the menu
        if let stateItem = menu?.item(withTag: 100) {
            stateItem.title = isPaused ? "Ghostwriter: Paused" : "Ghostwriter: Active"
        }
    }
}
