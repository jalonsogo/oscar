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

    // MARK: - Settings (read from UserDefaults; write via SettingsView @AppStorage)
    var cagentBinaryPath: String {
        UserDefaults.standard.string(forKey: "cagentBinaryPath") ?? "/usr/local/bin/cagent"
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

    // MARK: - Dependencies
    let client: CagentClient
    let process: CagentProcess
    let spotlight: SpotlightIndexer

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        self.client = CagentClient()
        self.process = CagentProcess()
        self.spotlight = SpotlightIndexer()
        observeServerStatus()
        observeIntentNotifications()
    }

    // Keep a reference so we can pass openWindow from the App scene
    var openWindowAction: ((String) -> Void)?

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
        // Launch cagent subprocess
        await process.start(
            binaryPath: cagentBinaryPath,
            agentConfigPath: agentConfigPath,
            port: serverPort
        )
        if serverStatus.isRunning {
            await loadSessions()
        }
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
        let dir = workingDir.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : workingDir
        let request = CreateSessionRequest(title: title, workingDir: dir)
        let session = try await client.createSession(request)
        await loadSessions()
        return session
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
