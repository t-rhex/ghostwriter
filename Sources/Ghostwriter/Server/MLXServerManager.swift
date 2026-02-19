import AppKit
import Foundation

/// Manages the lifecycle of the Python MLX server as a child process.
final class MLXServerManager {
    private var process: Process?
    private var restartCount = 0
    private var isRunning = false
    private let llmClient = LLMClient()
    private var serverDir: String?

    /// Start the Python MLX server.
    func start() {
        guard !isRunning else { return }

        serverDir = findServerDirectory()
        guard let serverDir = serverDir else {
            print("[MLXServer] Could not find Server directory.")
            return
        }

        launchServer(serverDir: serverDir)
        waitForServerReady()
        observeSleepWake()
    }

    /// Stop the Python MLX server.
    func stop() {
        isRunning = false
        if let process = process, process.isRunning {
            process.terminate()
            print("[MLXServer] Server stopped.")
        }
        process = nil
    }

    // MARK: - Private

    private func launchServer(serverDir: String) {
        let baseDir = (serverDir as NSString).deletingLastPathComponent
        let pythonPath = Configuration.pythonExecutable(relativeTo: baseDir)
        print("[MLXServer] Using Python: \(pythonPath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [
            "-m", "uvicorn",
            "ghostwriter_server:app",
            "--host", Configuration.llmHost,
            "--port", String(Configuration.llmPort),
            "--app-dir", serverDir,
        ]
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDir)

        // Pipe stdout/stderr for logging
        let outputPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("[MLXServer] \(str)", terminator: "")
            }
        }

        // Auto-restart on crash
        proc.terminationHandler = { [weak self] process in
            guard let self = self, self.isRunning else { return }
            let code = process.terminationStatus
            print("[MLXServer] Server exited with code \(code).")

            if self.restartCount < Configuration.maxServerRestartAttempts {
                self.restartCount += 1
                print("[MLXServer] Restarting (attempt \(self.restartCount))...")
                DispatchQueue.global().asyncAfter(deadline: .now() + Configuration.serverRestartDelay) {
                    self.launchServer(serverDir: serverDir)
                    self.waitForServerReady()
                }
            } else {
                print("[MLXServer] Max restart attempts reached. Server will not restart.")
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.isRunning = true
            print("[MLXServer] Server launched (PID: \(proc.processIdentifier)).")
        } catch {
            print("[MLXServer] Failed to launch server: \(error)")
        }
    }

    private func waitForServerReady() {
        print("[MLXServer] Waiting for server to be ready (model loading may take a minute)...")
        let deadline = Date().addingTimeInterval(Configuration.serverReadyTimeout)

        while Date() < deadline {
            let semaphore = DispatchSemaphore(value: 0)
            var ready = false

            Task {
                ready = await llmClient.readyCheck()
                semaphore.signal()
            }
            semaphore.wait()

            if ready {
                print("[MLXServer] Server is ready — model loaded.")
                restartCount = 0
                return
            }

            Thread.sleep(forTimeInterval: 2.0)
        }

        print("[MLXServer] Server did not become ready within timeout. Will continue — first request may be slow.")
    }

    // MARK: - Sleep/Wake Handling

    private func observeSleepWake() {
        // Metal GPU state is invalidated on sleep/wake, causing MLX to crash.
        // Proactively restart the server when the system wakes.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[MLXServer] System going to sleep — stopping server.")
            self?.stopProcess()
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning, let serverDir = self.serverDir else { return }
            print("[MLXServer] System woke — restarting server.")
            self.restartCount = 0  // Reset since this is expected, not a crash
            // Delay slightly to let GPU stabilize
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                self.launchServer(serverDir: serverDir)
                self.waitForServerReady()
            }
        }
    }

    private func stopProcess() {
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    private func findServerDirectory() -> String? {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let candidates = [
            // Relative to executable (dev builds — checked first so local edits take precedence)
            execURL.deletingLastPathComponent().appendingPathComponent("../../../Server").path,
            execURL.deletingLastPathComponent().appendingPathComponent("../../Server").path,
            execURL.deletingLastPathComponent().appendingPathComponent("Server").path,
            // Relative to working directory
            FileManager.default.currentDirectoryPath + "/Server",
            // Installed location (fallback)
            "/usr/local/share/ghostwriter/Server",
        ]

        for candidate in candidates {
            let resolved = (candidate as NSString).standardizingPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue {
                let serverScript = (resolved as NSString).appendingPathComponent("ghostwriter_server.py")
                if FileManager.default.fileExists(atPath: serverScript) {
                    return resolved
                }
            }
        }

        return nil
    }
}
