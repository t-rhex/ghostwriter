import Foundation

/// Manages the lifecycle of the Python MLX server as a child process.
final class MLXServerManager {
    private var process: Process?
    private var restartCount = 0
    private var isRunning = false
    private let llmClient = LLMClient()

    /// Start the Python MLX server.
    func start() {
        guard !isRunning else { return }

        let serverDir = findServerDirectory()
        guard let serverDir = serverDir else {
            print("[MLXServer] Could not find Server directory.")
            return
        }

        launchServer(serverDir: serverDir)
        waitForServerReady()
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

    private func findServerDirectory() -> String? {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let candidates = [
            // Installed location
            "/usr/local/share/ghostwriter/Server",
            // Relative to executable (dev builds)
            execURL.deletingLastPathComponent().appendingPathComponent("../../../Server").path,
            execURL.deletingLastPathComponent().appendingPathComponent("../../Server").path,
            execURL.deletingLastPathComponent().appendingPathComponent("Server").path,
            // Relative to working directory
            FileManager.default.currentDirectoryPath + "/Server",
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
