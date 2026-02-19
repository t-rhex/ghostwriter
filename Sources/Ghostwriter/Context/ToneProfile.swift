import Foundation

/// Tone profiles that control how aggressively text is corrected and what style is used.
enum Tone: String, Codable {
    case casual       // Slack, Messages, Discord — contractions OK, natural
    case professional // Mail, Outlook — polished grammar, no slang
    case technical    // Terminal, Xcode, VS Code — preserve terminology, minimal fixes
    case neutral      // Default — standard English

    var systemPromptModifier: String {
        switch self {
        case .casual:
            return "Keep a casual, friendly tone. Contractions are fine. Don't over-formalize."
        case .professional:
            return "Use a polished, professional tone. Avoid slang and contractions."
        case .technical:
            return "Preserve technical terminology. Only fix clear typos and grammar. Don't rephrase code-related terms."
        case .neutral:
            return "Use standard English. Fix grammar and spelling naturally."
        }
    }
}

/// Maps application bundle identifiers to tone profiles.
enum ToneProfile {
    private static let appToneMap: [String: Tone] = [
        // Casual
        "com.tinyspeck.slackmacgap": .casual,
        "com.apple.MobileSMS": .casual,
        "com.hnc.Discord": .casual,
        "com.facebook.archon": .casual,       // Messenger
        "ru.keepcoder.Telegram": .casual,
        "net.whatsapp.WhatsApp": .casual,

        // Professional
        "com.apple.mail": .professional,
        "com.microsoft.Outlook": .professional,
        "com.google.Gmail": .professional,
        "com.readdle.smartemail-macos": .professional,

        // Technical
        "com.apple.Terminal": .technical,
        "com.apple.dt.Xcode": .technical,
        "com.microsoft.VSCode": .technical,
        "com.todesktop.230313mzl4w4u92": .technical,  // Cursor
        "dev.warp.Warp-Stable": .technical,
        "com.googlecode.iterm2": .technical,
        "net.kovidgoyal.kitty": .technical,
        "com.mitchellh.ghostty": .technical,
    ]

    /// Get the tone for a given app bundle identifier.
    static func tone(for bundleID: String?) -> Tone {
        guard let bundleID = bundleID else { return .neutral }
        return appToneMap[bundleID] ?? .neutral
    }

    // MARK: - Per-App Correction Skip Rules

    /// AX roles and subroles whose elements should never be corrected.
    /// These represent UI elements where spell-correction is inappropriate
    /// (search bars, dropdowns, URL bars, password fields).
    static let skippedRoles: Set<String> = [
        "AXSearchField",       // Search bars — user expects literal input
        "AXComboBox",          // Dropdowns — values are predefined, not prose
        "AXSecureTextField",   // Password fields — must never be altered
    ]

    /// AX subroles whose elements should never be corrected.
    static let skippedSubroles: Set<String> = [
        "AXURLTextField",      // URL bars — addresses, not prose
        "AXSearchField",       // Some apps expose search as a subrole
        "AXSecureTextField",   // Password fields via subrole
    ]

    /// Determine whether a given element should be skipped for correction
    /// based on its AX role and subrole.
    ///
    /// - Parameters:
    ///   - role: The AXRole of the focused element (e.g. "AXTextField", "AXSearchField").
    ///   - subrole: The AXSubrole of the focused element (e.g. "AXURLTextField"), or nil.
    /// - Returns: `true` if correction should be skipped for this element.
    static func shouldSkip(role: String?, subrole: String?) -> Bool {
        if let role = role, skippedRoles.contains(role) {
            return true
        }
        if let subrole = subrole, skippedSubroles.contains(subrole) {
            return true
        }
        return false
    }
}
