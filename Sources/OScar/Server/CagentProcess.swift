import Foundation
import AppKit

/// Manages the lifecycle of the `cagent serve api` subprocess.
@MainActor
class CagentProcess: ObservableObject {
    @Published private(set) var status: ServerStatus = .stopped
    @Published private(set) var lastError: String?

    private var process: Process?
    private var healthTask: Task<Void, Never>?
    private var restartCount = 0

    // MARK: - Public

    /// Start the cagent API server. No-op if already running.
    func start(binaryPath: String, agentConfigPath: String, port: Int = 8080) async {
        guard process == nil else { return }

        let resolvedBinary = await resolve(binaryPath: binaryPath)
        guard let binary = resolvedBinary else {
            status = .error("cagent binary not found at \(binaryPath)")
            return
        }

        let configPath = resolvedAgentConfig(agentConfigPath)
        guard let config = configPath else {
            status = .error("No agent config found. Set one in Settings.")
            return
        }

        status = .launching
        launch(binary: binary, config: config, port: port)
        await waitUntilHealthy(port: port)
    }

    func stop() {
        healthTask?.cancel()
        healthTask = nil
        process?.terminate()
        process = nil
        status = .stopped
    }

    // MARK: - Private

    private func launch(binary: String, config: String, port: Int) {
        let sessionDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cagent/session.db").path

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = [
            "api", config,
            "--listen", "127.0.0.1:\(port)",
            "--session-db", sessionDB
        ]

        // Pipe stderr to capture errors, but don't block stdout (SSE needs it)
        let errorPipe = Pipe()
        p.standardError = errorPipe

        p.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                if process.terminationStatus != 0 && self.restartCount < 3 {
                    self.restartCount += 1
                    // Brief delay before restart
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await self.start(
                        binaryPath: binary,
                        agentConfigPath: config,
                        port: port
                    )
                } else {
                    self.status = .error("cagent exited (code \(process.terminationStatus))")
                }
            }
        }

        do {
            try p.run()
            self.process = p
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func waitUntilHealthy(port: Int, timeout: TimeInterval = 15) async {
        let start = Date()
        let url = URL(string: "http://127.0.0.1:\(port)/api/sessions")!
        while Date().timeIntervalSince(start) < timeout {
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    status = .running
                    restartCount = 0
                    return
                }
            } catch {}
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        status = .error("cagent did not start within \(Int(timeout))s")
    }

    private func resolve(binaryPath: String) async -> String? {
        // 1. Try the configured path
        if FileManager.default.isExecutableFile(atPath: binaryPath) {
            return binaryPath
        }
        // 2. Try common install locations
        let candidates = [
            "/usr/local/bin/cagent",
            "/opt/homebrew/bin/cagent",
            (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(".local/bin/cagent")
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // 3. which cagent
        return await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            p.arguments = ["cagent"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            continuation.resume(returning: output.flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    private func resolvedAgentConfig(_ path: String) -> String? {
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return path
        }
        // Try default OScar config location
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/oscar/agent.yaml").path
        if FileManager.default.fileExists(atPath: defaultPath) {
            return defaultPath
        }
        return nil
    }

    // MARK: - Helpers

    static func openCagentInstallPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/docker/cagent")!)
    }
}
