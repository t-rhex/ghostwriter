import AppKit
import Foundation

/// Manages the lifecycle of the Python MLX server as a child process.
final class MLXServerManager {
    private var process: Process?
    private var restartCount = 0
    private var isRunning = false
    private let llmClient = LLMClient()
    private var serverDir: String?
    private var lastSuccessfulLaunchTime: Date?
    private var healthCheckTimer: DispatchSourceTimer?

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
        startHealthCheckTimer()
        observeSleepWake()
    }

    /// Stop the Python MLX server.
    func stop() {
        isRunning = false
        stopHealthCheckTimer()
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

        // Auto-restart on crash with exponential backoff
        proc.terminationHandler = { [weak self] process in
            guard let self = self, self.isRunning else { return }
            let code = process.terminationStatus
            print("[MLXServer] Server exited with code \(code).")

            // If the server was stable (up for 60+ seconds), reset the restart counter
            if let launchTime = self.lastSuccessfulLaunchTime,
               Date().timeIntervalSince(launchTime) >= Configuration.serverStableThreshold {
                print("[MLXServer] Server was stable for \(Int(Date().timeIntervalSince(launchTime)))s — resetting restart counter.")
                self.restartCount = 0
            }

            if self.restartCount < Configuration.maxServerRestartAttempts {
                self.restartCount += 1
                let delays = Configuration.serverBackoffDelays
                // Use the backoff array, clamping to the last value for indices beyond the array
                let delayIndex = min(self.restartCount - 1, delays.count - 1)
                let delay = delays[delayIndex]
                print("[MLXServer] Restarting (attempt \(self.restartCount)/\(Configuration.maxServerRestartAttempts)) after \(Int(delay))s backoff...")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    guard self.isRunning else { return }
                    self.launchServer(serverDir: serverDir)
                    self.waitForServerReady()
                }
            } else {
                print("[MLXServer] Max restart attempts (\(Configuration.maxServerRestartAttempts)) reached. Server will not restart automatically. A periodic health check will continue to monitor.")
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
                lastSuccessfulLaunchTime = Date()
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

    // MARK: - Periodic Health Check

    /// Start a repeating timer that checks if the server is responsive.
    /// If the process has died silently (or the health endpoint fails),
    /// trigger a restart — even if the termination handler didn't fire.
    private func startHealthCheckTimer() {
        stopHealthCheckTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(
            deadline: .now() + Configuration.serverPeriodicHealthCheckInterval,
            repeating: Configuration.serverPeriodicHealthCheckInterval
        )
        timer.setEventHandler { [weak self] in
            self?.performPeriodicHealthCheck()
        }
        timer.resume()
        healthCheckTimer = timer
    }

    private func stopHealthCheckTimer() {
        healthCheckTimer?.cancel()
        healthCheckTimer = nil
    }

    private func performPeriodicHealthCheck() {
        guard isRunning, let serverDir = serverDir else { return }

        let semaphore = DispatchSemaphore(value: 0)
        var healthy = false

        Task {
            healthy = await llmClient.readyCheck()
            semaphore.signal()
        }
        semaphore.wait()

        if healthy {
            // Server is alive — if it has been stable long enough, reset counter
            if let launchTime = lastSuccessfulLaunchTime,
               Date().timeIntervalSince(launchTime) >= Configuration.serverStableThreshold,
               restartCount > 0 {
                print("[MLXServer] Health check passed — server stable for \(Int(Date().timeIntervalSince(launchTime)))s. Resetting restart counter.")
                restartCount = 0
            }
            return
        }

        // Server is unresponsive — check if the process is still alive
        let processAlive = process?.isRunning ?? false
        print("[MLXServer] Health check FAILED (process alive: \(processAlive)). Attempting restart...")

        // Kill the zombie process if it's still technically running
        if processAlive {
            stopProcess()
        }

        // Attempt restart (respecting the backoff/counter logic)
        if restartCount < Configuration.maxServerRestartAttempts {
            restartCount += 1
            let delays = Configuration.serverBackoffDelays
            let delayIndex = min(restartCount - 1, delays.count - 1)
            let delay = delays[delayIndex]
            print("[MLXServer] Health-check restart (attempt \(restartCount)/\(Configuration.maxServerRestartAttempts)) after \(Int(delay))s backoff...")
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.launchServer(serverDir: serverDir)
                self.waitForServerReady()
            }
        } else {
            print("[MLXServer] Health check: max restart attempts (\(Configuration.maxServerRestartAttempts)) reached. Will keep checking periodically.")
            // Reset counter so that the next health check failure can try again
            // after the full backoff cycle. This prevents permanent death.
            restartCount = 0
            print("[MLXServer] Restart counter reset — will retry on next health check failure.")
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
