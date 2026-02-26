import Foundation
import SwiftUI
import Combine

/// Central observable state for OScar. All UI reads from here.
@MainActor
class AppState: ObservableObject {
    // MARK: - Published State
    @Published var sessions: [SessionSummary] = []
    @Published var serverStatus: ServerStatus = .stopped
    @Published var isQuickEntryVisible: Bool = false
    @Published var alert: AlertInfo? = nil
    @Published var streamingSessions: Set<String> = []
    @Published var waitingSessions:   Set<String> = []

    /// Agent is generating a response.
    func markStreaming(_ sessionId: String) {
        streamingSessions.insert(sessionId)
        waitingSessions.remove(sessionId)
    }
    /// Agent finished — conversation window is open, waiting for next user message.
    func markWaiting(_ sessionId: String) {
        streamingSessions.remove(sessionId)
        waitingSessions.insert(sessionId)
    }
    /// Conversation window closed (or stream cancelled) — no longer relevant.
    func markIdle(_ sessionId: String) {
        streamingSessions.remove(sessionId)
        waitingSessions.remove(sessionId)
    }

    // MARK: - Settings (read from UserDefaults; write via SettingsView @AppStorage)
    var cagentBinaryPath: String {
        UserDefaults.standard.string(forKey: "cagentBinaryPath") ?? ""
    }

    /// Best available binary path: Settings override → downloaded → empty (CagentProcess tries system PATH).
    var resolvedBinaryPath: String {
        let configured = cagentBinaryPath
        if !configured.isEmpty && FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        let downloaded = CagentDownloader.installURL.path
        if FileManager.default.isExecutableFile(atPath: downloaded) {
            return downloaded
        }
        return configured
    }
    var agentConfigPath: String {
        UserDefaults.standard.string(forKey: "agentConfigPath") ?? ""
    }
    var serverPort: Int {
        let stored = UserDefaults.standard.integer(forKey: "serverPort")
        return stored == 0 ? 8080 : stored
    }
    var agentName: String {
        UserDefaults.standard.string(forKey: "agentName") ?? "agent"
    }
    var workingDir: String {
        UserDefaults.standard.string(forKey: "workingDir") ?? ""
    }
    var sessionsFolderPath: String {
        let stored = UserDefaults.standard.string(forKey: "sessionsFolderPath") ?? ""
        if !stored.isEmpty { return stored }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Oscar").path
    }

    // MARK: - Dependencies
    let client: CagentClient
    let process: CagentProcess
    let spotlight: SpotlightIndexer
    let downloader: CagentDownloader

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        self.client = CagentClient()
        self.process = CagentProcess()
        self.spotlight = SpotlightIndexer()
        self.downloader = CagentDownloader()
        observeServerStatus()
        observeIntentNotifications()
        downloader.checkInstalled()
    }

    // Keep a reference so we can pass openWindow from the App scene
    var openWindowAction: ((String) -> Void)?
    var openSettingsAction: (() -> Void)?

    // MARK: - Lifecycle

    /// Idempotent — safe to call multiple times (e.g. on MenuBarExtra appear).
    func startIfNeeded() async {
        guard !serverStatus.isRunning else { return }
        await start()
    }

    func start() async {
        // Try attaching to an already-running server first
        if await client.healthCheck() {
            serverStatus = .running
            await loadSessions()
            return
        }
        // Auto-download cagent if no binary is available anywhere
        if !hasCagentBinary() && !downloader.state.isInProgress {
            await downloader.downloadLatest()
        }
        // Launch cagent subprocess
        await process.start(
            binaryPath: resolvedBinaryPath,
            agentConfigPath: agentConfigPath,
            port: serverPort
        )
        if serverStatus.isRunning {
            await loadSessions()
        }
    }

    /// Download (or update) cagent and restart the server if it was running.
    func downloadCagent() async {
        let wasRunning = serverStatus.isRunning
        await downloader.downloadLatest()
        if case .ready = downloader.state, wasRunning {
            process.stop()
            await start()
        }
    }

    private func hasCagentBinary() -> Bool {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: resolvedBinaryPath) { return true }
        let systemPaths = ["/usr/local/bin/cagent", "/opt/homebrew/bin/cagent"]
        return systemPaths.contains { fm.isExecutableFile(atPath: $0) }
    }

    // MARK: - Sessions

    func loadSessions() async {
        do {
            let loaded = try await client.listSessions()
            sessions = loaded.sorted { $0.createdAt > $1.createdAt }
            spotlight.indexSessions(sessions)
        } catch {
            alert = AlertInfo(message: "Failed to load sessions: \(error.localizedDescription)")
        }
    }

    func createSession(title: String) async throws -> SessionSummary {
        let dir = resolvedSessionDir(for: title)
        let request = CreateSessionRequest(title: title, workingDir: dir)
        let session = try await client.createSession(request)
        await loadSessions()
        return session
    }

    private func resolvedSessionDir(for title: String) -> String {
        let folder = sessionsFolderPath
        if !folder.isEmpty {
            let expanded = (folder as NSString).expandingTildeInPath
            let name = sanitizeFolderName(title)
            let sessionDir = (expanded as NSString).appendingPathComponent(name)
            try? FileManager.default.createDirectory(
                atPath: sessionDir, withIntermediateDirectories: true
            )
            return sessionDir
        }
        if !workingDir.isEmpty {
            return workingDir
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func sanitizeFolderName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: allowed.inverted).joined()
            .replacingOccurrences(of: " ", with: "_")
        let truncated = String(cleaned.prefix(50))
        return truncated.isEmpty ? "session" : truncated
    }

    func deleteSession(id: String) async {
        do {
            try await client.deleteSession(id: id)
            sessions.removeAll { $0.id == id }
            spotlight.removeSession(id: id)
        } catch {
            alert = AlertInfo(message: "Delete failed: \(error.localizedDescription)")
        }
    }

    func updateSessionTitle(id: String, title: String) async {
        do {
            try await client.updateTitle(sessionId: id, title: title)
            await loadSessions()
        } catch {
            alert = AlertInfo(message: "Rename failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Observation

    private func observeIntentNotifications() {
        // Fired by StartConversationIntent (Spotlight "Ask Oscar")
        NotificationCenter.default.addObserver(
            forName: .oscOpenWithQuery,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let query = notification.userInfo?["query"] as? String ?? ""
            let agentName = notification.userInfo?["agentName"] as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let session = try? await self.createSession(title: String(query.prefix(60)))
                else { return }
                var payload = "\(session.id)|\(query)"
                if let agentName { payload += "|\(agentName)" }
                self.openWindowAction?(payload)
            }
        }

        // Fired by ContinueLastSessionIntent or Spotlight tap via NSUserActivity
        NotificationCenter.default.addObserver(
            forName: .oscContinueLastSession,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.loadSessions()
                if let first = self.sessions.first {
                    self.openWindowAction?(first.id)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .oscOpenSession,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let payload = notification.userInfo?["payload"] as? String {
                Task { @MainActor [weak self] in
                    self?.openWindowAction?(payload)
                }
            }
        }
    }

    private func observeServerStatus() {
        process.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.serverStatus = status
                if status.isRunning {
                    Task { [weak self] in await self?.loadSessions() }
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

struct AlertInfo: Identifiable {
    let id = UUID()
    let message: String
}
