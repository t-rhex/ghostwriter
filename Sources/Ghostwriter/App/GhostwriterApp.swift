import ApplicationServices
import Foundation

/// Orchestrator — wires all components together and runs the main correction/elaboration loop.
final class GhostwriterApp {
    // Components
    private let keystrokeMonitor = KeystrokeMonitor()
    private let keystrokeBuffer = KeystrokeBuffer()
    private let debouncer: TypingDebouncer
    private let textFieldReader = TextFieldReader()
    private let appDetector = AppDetector()
    private let llmClient = LLMClient()
    private let textReplacer = TextReplacer()
    private let ghostTextController = GhostTextController()
    private let undoManager = CorrectionUndoManager()
    private let serverManager = MLXServerManager()

    // State
    private let processingQueue = DispatchQueue(label: "com.ghostwriter.processing")
    private var isProcessing = false

    init() {
        self.debouncer = TypingDebouncer()
    }

    /// Start the Ghostwriter service.
    func start() {
        print("[Ghostwriter] Starting...")

        // Enable accessibility in Chromium browsers (required for AX queries to work)
        enableBrowserAccessibility()

        // Launch the Python MLX server
        serverManager.start()

        // Set up debouncer callbacks
        debouncer.onShortPause = { [weak self] in
            self?.handleShortPause()
        }
        debouncer.onLongPause = { [weak self] in
            self?.handleLongPause()
        }

        // Start keystroke monitoring
        keystrokeMonitor.start { [weak self] char, keyCode, flags in
            self?.handleKeystroke(char: char, keyCode: keyCode, flags: flags)
        }

        print("[Ghostwriter] Running. Listening for keystrokes...")
    }

    /// Stop the Ghostwriter service.
    func stop() {
        keystrokeMonitor.stop()
        debouncer.stop()
        serverManager.stop()
        print("[Ghostwriter] Stopped.")
    }

    // MARK: - Keystroke Handling

    private func handleKeystroke(char: String, keyCode: UInt16, flags: CGEventFlags) {
        // Detect Cmd+Z (undo)
        if flags.contains(.maskCommand) && keyCode == 6 { // 6 = 'z'
            handleUndo()
            return
        }

        // Handle Tab when ghost text is active
        if keyCode == KeyCode.tab && ghostTextController.isActive {
            ghostTextController.accept()
            keystrokeBuffer.clear()
            return
        }

        // Dismiss ghost text on any other key
        if ghostTextController.isActive {
            ghostTextController.dismiss()
        }

        // Skip modifier-only or non-printing keys
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return
        }

        // Buffer management
        if keyCode == KeyCode.delete {
            keystrokeBuffer.handleDelete()
        } else if !char.isEmpty && char.unicodeScalars.allSatisfy({ !$0.properties.isNoncharacterCodePoint }) {
            keystrokeBuffer.append(char)
        }

        // Reset debounce timers
        debouncer.keystrokeReceived()
    }

    // MARK: - Pause Handlers

    private func handleShortPause() {
        guard !isProcessing else { return }
        processingQueue.async { [weak self] in
            self?.performCorrection()
        }
    }

    private func handleLongPause() {
        guard !isProcessing else { return }
        processingQueue.async { [weak self] in
            self?.performElaboration()
        }
    }

    // MARK: - Correction

    private func performCorrection() {
        isProcessing = true
        defer { isProcessing = false }

        // Skip technical apps (terminals, IDEs) — their text fields contain
        // entire buffers/documents, not discrete user input
        let bundleID = appDetector.frontmostAppBundleID()
        let tone = ToneProfile.tone(for: bundleID)
        guard tone != .technical else { return }

        // Read the focused text field
        guard let fieldInfo = textFieldReader.readFocusedTextField() else {
            print("[Ghostwriter] No focused text field. App: \(bundleID ?? "unknown")")
            return
        }
        print("[Ghostwriter] Read field: \(fieldInfo.text.count) chars, browser=\(fieldInfo.isBrowserField), app=\(bundleID ?? "unknown")")

        // Skip password fields
        guard !fieldInfo.isSecure else {
            print("[Ghostwriter] Skipping secure field.")
            return
        }

        let text = PromptBuilder.extractRelevantText(fieldInfo.text)

        // Skip if too short
        guard text.count >= Configuration.minTextLengthForCorrection else { return }

        // Skip if recently corrected (prevent loops)
        guard !undoManager.wasRecentlyCorrected(text) else {
            print("[Ghostwriter] Skipping — recently corrected.")
            return
        }

        // Skip if user undid a correction
        guard !undoManager.isUndoneCorrection(text) else {
            print("[Ghostwriter] Skipping — user reverted correction.")
            return
        }

        // Call LLM
        let semaphore = DispatchSemaphore(value: 0)
        var correctedText: String?

        Task {
            do {
                let response = try await llmClient.correct(text: text, tone: tone)
                correctedText = response.result
            } catch {
                print("[Ghostwriter] Correction failed: \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard let corrected = correctedText, !corrected.isEmpty else { return }

        // Safety: reject if too different
        let distance = editDistanceRatio(original: text, corrected: corrected)
        guard distance <= Configuration.maxEditDistanceRatio else {
            print("[Ghostwriter] Rejected correction — edit distance \(String(format: "%.0f%%", distance * 100)) exceeds threshold.")
            return
        }

        // Skip if no change
        guard corrected != text else { return }

        // Re-read to check user hasn't typed during processing
        if let currentField = textFieldReader.readFocusedTextField(), currentField.text != fieldInfo.text {
            print("[Ghostwriter] Text changed during processing — skipping.")
            return
        }

        // Apply correction
        let strategy = textReplacer.replaceFullText(in: fieldInfo.element, with: corrected)
        if let strategy = strategy {
            undoManager.recordCorrection(original: text, corrected: corrected)
            print("[Ghostwriter] Corrected via \(strategy): \"\(text.prefix(30))\" → \"\(corrected.prefix(30))\"")
        }
    }

    // MARK: - Elaboration

    private func performElaboration() {
        isProcessing = true
        defer { isProcessing = false }

        guard let fieldInfo = textFieldReader.readFocusedTextField() else { return }
        guard !fieldInfo.isSecure else { return }

        let text = fieldInfo.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only elaborate short text
        guard text.count >= Configuration.minTextLengthForElaboration else { return }
        guard text.count < 100 else { return } // Only elaborate short fragments

        let bundleID = appDetector.frontmostAppBundleID()
        let tone = ToneProfile.tone(for: bundleID)

        // Skip technical apps for elaboration
        guard tone != .technical else { return }

        let semaphore = DispatchSemaphore(value: 0)
        var elaboratedText: String?

        Task {
            do {
                let response = try await llmClient.elaborate(text: text, tone: tone)
                elaboratedText = response.result
            } catch {
                print("[Ghostwriter] Elaboration failed: \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard let elaborated = elaboratedText, !elaborated.isEmpty else { return }
        guard elaborated != text else { return }

        // Re-read to check for changes
        if let currentField = textFieldReader.readFocusedTextField(), currentField.text != fieldInfo.text {
            print("[Ghostwriter] Text changed during processing — skipping elaboration.")
            return
        }

        // Show as ghost text (selected/highlighted)
        DispatchQueue.main.async { [weak self] in
            self?.ghostTextController.showGhostText(
                elaborated,
                in: fieldInfo.element,
                currentText: fieldInfo.text
            )
        }
    }

    // MARK: - Undo

    private func handleUndo() {
        undoManager.clear()
        keystrokeBuffer.clear()
        debouncer.cancelTimers()
        print("[Ghostwriter] Undo detected — cleared state.")
    }

    // MARK: - Helpers

    /// Compute edit distance ratio (0.0 = identical, 1.0 = completely different).
    private func editDistanceRatio(original: String, corrected: String) -> Double {
        let maxLen = max(original.count, corrected.count)
        guard maxLen > 0 else { return 0.0 }
        let distance = levenshteinDistance(Array(original), Array(corrected))
        return Double(distance) / Double(maxLen)
    }

    /// Simple Levenshtein distance implementation.
    private func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost  // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }

    /// Enable accessibility in Chromium-based browsers via user defaults.
    /// Chrome/Edge/Brave etc. don't expose AX elements unless this is set.
    private func enableBrowserAccessibility() {
        let chromiumApps = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser",  // Arc
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
        ]
        for bundleID in chromiumApps {
            let current = UserDefaults(suiteName: bundleID)?.bool(forKey: "NSAccessibilityEnabled")
            if current != true {
                UserDefaults(suiteName: bundleID)?.set(true, forKey: "NSAccessibilityEnabled")
                print("[Ghostwriter] Enabled accessibility for \(bundleID)")
            }
        }
    }
}
