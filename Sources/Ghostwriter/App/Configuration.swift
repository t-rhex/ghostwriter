import Foundation

enum Configuration {
    // MARK: - Debouncing
    static let shortPauseInterval: TimeInterval = 1.0   // 1.0s → trigger correction (tuned for 3B model latency)
    static let longPauseInterval: TimeInterval = 2.0     // 2s → trigger elaboration

    // MARK: - LLM Server
    static let llmHost = "127.0.0.1"
    static let llmPort: UInt16 = 9274
    static var llmBaseURL: String { "http://\(llmHost):\(llmPort)" }

    // MARK: - Safety
    static let maxTextLength = 2000
    static let maxEditDistanceRatio = 0.30               // Reject if >30% changed
    static let minTextLengthForCorrection = 3
    static let minTextLengthForElaboration = 5

    // MARK: - Model
    static let modelName = "mlx-community/Llama-3.2-3B-Instruct-4bit"

    // MARK: - Server Management
    static let serverStartupTimeout: TimeInterval = 30.0   // For uvicorn process to start
    static let serverReadyTimeout: TimeInterval = 180.0    // For model download + load (up to 3 min)
    static let serverHealthCheckInterval: TimeInterval = 5.0
    static let serverRestartDelay: TimeInterval = 2.0
    static let maxServerRestartAttempts = 3

    // MARK: - Python Virtual Environment
    static let venvDirectory = ".venv"
    static let serverScript = "ghostwriter_server.py"
    static let serverDirectory = "Server"

    /// Resolve the python executable inside the venv, relative to a base directory.
    static func pythonExecutable(relativeTo baseDir: String) -> String {
        let venvPython = (baseDir as NSString).appendingPathComponent("\(venvDirectory)/bin/python3")
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        // Fallback to system python
        return "python3"
    }
}
