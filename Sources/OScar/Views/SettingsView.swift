import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    private enum Tab: String, CaseIterable {
        case general = "General"
        case agents  = "Agents"
        case docker  = "Docker"
        case update  = "Update"
        case about   = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .agents:  return "person.2.wave.2"
            case .docker:  return "shippingbox"
            case .update:  return "arrow.down.circle"
            case .about:   return "info.circle"
            }
        }
    }

    @State private var selection: Tab = .general

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button { selection = tab } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 14)
                                .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                            Text(tab.rawValue)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 120)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selection {
                    case .general: GeneralTab()
                    case .agents:  AgentsTab()
                    case .docker:  DockerAgentTab()
                    case .update:
                        UpdateTab(downloader: state.downloader) {
                            Task { await state.downloadCagent() }
                        }
                    case .about:   AboutTab()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .environmentObject(state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @EnvironmentObject var state: AppState

    @AppStorage("agentConfigPath") private var agentConfigPath: String = ""
    @AppStorage("agentName")       private var agentName: String = "agent"
    @AppStorage("sessionsFolderPath") private var sessionsFolderPath: String = ""
    @AppStorage("serverPort")      private var serverPort: Int = 8080

    @State private var showConfigPicker = false

    var body: some View {
        Form {
            Section("Agent") {
                HStack {
                    Text("Agent name")
                    TextField("agent", text: $agentName)
                        .multilineTextAlignment(.trailing)
                }
                .help("Run mode passed to /api/sessions/{id}/agent/{name}")

                HStack {
                    Text("Config file")
                    Spacer()
                    Text(configLabel)
                        .foregroundStyle(agentConfigPath.isEmpty ? Color.red : Color.secondary)
                        .lineLimit(1)
                    Button("Choose\u{2026}") { showConfigPicker = true }
                    if !agentConfigPath.isEmpty {
                        Button("Create default") { createDefaultConfig() }
                            .foregroundStyle(Color.secondary)
                    }
                }
                .help("Path to your cagent agent.yaml")

                HStack {
                    Text("Sessions folder")
                    Spacer()
                    Text(sessionsFolderLabel)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                    Button("Choose\u{2026}") { pickSessionsFolder() }
                    if !sessionsFolderPath.isEmpty {
                        Button("Clear") { sessionsFolderPath = "" }
                            .foregroundStyle(Color.secondary)
                    }
                }
                .help("New sessions are created in {folder}/{session_name}")
            }

            Section("Server") {
                HStack {
                    Text("Port")
                    TextField("8080", value: $serverPort, format: .number)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 6) {
                    Text("Status")
                    Spacer()
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(state.serverStatus.description).foregroundStyle(Color.secondary)
                    Button("Restart") {
                        state.process.stop()
                        Task { await state.start() }
                    }
                }

                HStack {
                    Text("Sessions")
                    Spacer()
                    Text("\(state.sessions.count)").foregroundStyle(Color.secondary)
                }
            }

            Section {
                HStack {
                    if agentConfigPath.isEmpty {
                        Button("Create default agent.yaml\u{2026}") { createDefaultConfig() }
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showConfigPicker, allowedContentTypes: [.text, .data]) { result in
            if case .success(let url) = result { agentConfigPath = url.path }
        }
    }

    private var configLabel: String {
        agentConfigPath.isEmpty ? "Not set" : URL(fileURLWithPath: agentConfigPath).lastPathComponent
    }

    private var sessionsFolderLabel: String {
        if sessionsFolderPath.isEmpty { return "~/Documents/Oscar/{session_name}" }
        return (sessionsFolderPath as NSString).abbreviatingWithTildeInPath + "/{session_name}"
    }

    private var statusColor: Color {
        switch state.serverStatus {
        case .running: return .green
        case .launching: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private func pickSessionsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Sessions Folder"
        if panel.runModal() == .OK, let url = panel.url {
            sessionsFolderPath = url.path
        }
    }

    private func createDefaultConfig() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/oscar")
        let configFile = configDir.appendingPathComponent("agent.yaml")
        let yaml = """
        version: 1

        agents:
          agent:
            model: anthropic/claude-opus-4-6
            description: "OScar \u{2014} your OS-level cognitive agent"
            instruction: |
              You are OScar, an intelligent assistant in the macOS menu bar.
              You can help with coding, research, and any task the user needs.
            toolsets:
              - type: shell
              - type: filesystem
        """
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try yaml.write(to: configFile, atomically: true, encoding: .utf8)
            agentConfigPath = configFile.path
            NSWorkspace.shared.open(configFile)
        } catch {
            // silently fail — user will notice the path didn't update
        }
    }
}

// MARK: - Agents Tab

private struct AgentsTab: View {
    @AppStorage("agentsFolderPath") private var agentsFolderPath: String = ""
    @AppStorage("agentConfigPath")  private var agentConfigPath: String  = ""

    var body: some View {
        Form {
            Section("Agents Folder") {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(folderLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Choose\u{2026}") { pickFolder() }
                    if !agentsFolderPath.isEmpty {
                        Button("Clear") { agentsFolderPath = "" }
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Folder containing agent YAML config files")
            }

            if !agentsFolderPath.isEmpty {
                Section("Discovered Agents") {
                    if discoveredAgents.isEmpty {
                        Text("No .yaml / .yml files found in this folder")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(discoveredAgents, id: \.path) { url in
                            AgentRow(
                                url: url,
                                isDefault: url.path == agentConfigPath,
                                onSetDefault: { agentConfigPath = url.path },
                                onClearDefault: { agentConfigPath = "" }
                            )
                        }
                    }
                }

                Section("Usage") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Start a session with a specific agent:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("cagent run {agent.yaml} {folder}")
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(NSColor.systemGreen))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var folderLabel: String {
        agentsFolderPath.isEmpty
            ? "Not set"
            : (agentsFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private var discoveredAgents: [URL] {
        guard !agentsFolderPath.isEmpty else { return [] }
        let url = URL(fileURLWithPath: (agentsFolderPath as NSString).expandingTildeInPath)
        let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        return (files ?? [])
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Agents Folder"
        if panel.runModal() == .OK, let url = panel.url {
            agentsFolderPath = url.path
        }
    }
}

private struct AgentRow: View {
    let url: URL
    let isDefault: Bool
    let onSetDefault: () -> Void
    let onClearDefault: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if isDefault {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Text(url.deletingPathExtension().lastPathComponent)
                        .fontWeight(isDefault ? .semibold : .regular)
                }
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Open") { NSWorkspace.shared.open(url) }
                .foregroundStyle(.secondary)

            if isDefault {
                Button("Remove Default") { onClearDefault() }
                    .foregroundStyle(.secondary)
            } else {
                Button("Set Default") { onSetDefault() }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Docker Agent Tab

private struct DockerAgentTab: View {
    @EnvironmentObject var state: AppState

    @AppStorage("boxAgentSuffix")          private var boxAgentSuffix: String = "-box"
    @AppStorage("dockerSandboxServerMode") private var dockerSandboxServerMode: Bool = false
    @AppStorage("dockerYolo")              private var dockerYolo: Bool = false

    var body: some View {
        Form {
            Section("Docker Account") {
                DockerAccountRow()
            }

            Section("Sandbox Agent Suffix") {
                HStack {
                    Text("Suffix")
                    TextField("-box", text: $boxAgentSuffix)
                        .multilineTextAlignment(.trailing)
                }
                .help("When Sandbox mode is enabled in Quick Entry, this suffix is appended to the agent name (e.g. claude → claude-box).")
            }

            Section("Docker Desktop Sandbox") {
                HStack {
                    Text("Docker status")
                    Spacer()
                    dockerStatusBadge
                }

                Toggle(isOn: $dockerSandboxServerMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch cagent via Docker Sandbox")
                        Text("Runs cagent inside Docker Desktop's managed sandbox. API credentials are injected automatically — no need to set ANTHROPIC_API_KEY or similar in OScar settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if dockerSandboxServerMode {
                    Toggle(isOn: $dockerYolo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Disable approval prompts (--yolo)")
                            Text("Grants unrestricted sandbox access without confirmation dialogs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Label("Restart required to apply changes", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Restart Server") {
                            state.process.stop()
                            Task { await state.start() }
                        }
                    }
                }
            }

            Section("Docker Toolset — agent.yaml") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Run tools inside an isolated Docker container:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dockerToolsetYaml)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(NSColor.systemGreen))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            Section("Docker MCP Catalog — agent.yaml") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Use containerized tools from the Docker MCP Catalog:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(mcpCatalogYaml)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(NSColor.systemGreen))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                    Button("Browse Docker MCP Catalog") {
                        NSWorkspace.shared.open(URL(string: "https://hub.docker.com/mcp")!)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var dockerStatusBadge: some View {
        if let path = dockerBinaryPath {
            Label(path, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            HStack(spacing: 6) {
                Label("Not found", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Install") {
                    NSWorkspace.shared.open(
                        URL(string: "https://docs.docker.com/desktop/install/mac-install/")!
                    )
                }
                .font(.caption)
            }
        }
    }

    private var dockerBinaryPath: String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var dockerToolsetYaml: String {
        """
        agents:
          claude:
            model: anthropic/claude-opus-4-6
            toolsets:
              - type: shell
          claude\(boxAgentSuffix):
            model: anthropic/claude-opus-4-6
            toolsets:
              - type: docker
                image: ubuntu:22.04
        """
    }

    private var mcpCatalogYaml: String {
        """
        agents:
          claude:
            model: anthropic/claude-opus-4-6
            toolsets:
              - type: mcp
                ref: docker:duckduckgo
              - type: mcp
                ref: docker:brave-search
                env:
                  BRAVE_API_KEY: "your-key"
        """
    }
}

// MARK: - Docker Account Row

private struct DockerHubProfile: Decodable {
    let username: String?
    let fullName: String?
    let gravatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case username = "user"
        case fullName = "full_name"
        case gravatarUrl = "gravatar_url"
    }
}

private struct DockerAccountRow: View {
    @State private var username: String = ""
    @State private var fullName: String = ""
    @State private var gravatarURL: URL? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Checking Docker account\u{2026}")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else if username.isEmpty {
                HStack {
                    Image(systemName: "person.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not signed in")
                            .fontWeight(.medium)
                        Text("Sign in to Docker Desktop to use sandbox features.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign in") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: "/Applications/Docker.app")
                        )
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 12) {
                    AsyncImage(url: gravatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fullName.isEmpty ? username : fullName)
                            .fontWeight(.medium)
                        if !username.isEmpty {
                            Text(username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .task { await loadAccount() }
    }

    private func loadAccount() async {
        isLoading = true
        defer { isLoading = false }

        guard let un = await dockerUsername(), !un.isEmpty else { return }
        username = un

        guard let url = URL(string: "https://hub.docker.com/v2/users/\(un)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let profile = try? JSONDecoder().decode(DockerHubProfile.self, from: data)
        else { return }

        fullName = profile.fullName ?? ""
        if let raw = profile.gravatarUrl, !raw.isEmpty {
            gravatarURL = URL(string: raw)
        }
    }

    private func dockerUsername() async -> String? {
        guard let docker = findDocker() else { return nil }
        return await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: docker)
            p.arguments = ["info", "--format", "{{.Username}}"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = out.flatMap { $0.isEmpty || $0 == "<no value>" ? nil : $0 }
            continuation.resume(returning: value)
        }
    }

    private func signOut() {
        guard let docker = findDocker() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: docker)
        p.arguments = ["logout"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        username = ""
        fullName = ""
        gravatarURL = nil
    }

    private func findDocker() -> String? {
        ["/usr/local/bin/docker",
         "/opt/homebrew/bin/docker",
         "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Update Tab

struct UpdateTab: View {
    @ObservedObject var downloader: CagentDownloader
    let onDownload: () -> Void

    @AppStorage("cagentBinaryPath") private var cagentBinaryPath: String = ""
    @State private var showBinaryPicker = false

    var body: some View {
        Form {
            Section("cagent Binary") {
                HStack(spacing: 8) {
                    Text("Status")
                    Spacer()
                    statusBadge
                    Button(buttonLabel, action: onDownload)
                        .disabled(downloader.state.isInProgress)
                }

                HStack {
                    Text("Override path")
                    TextField("Auto-detected", text: $cagentBinaryPath)
                        .multilineTextAlignment(.trailing)
                    Button("Choose\u{2026}") { showBinaryPicker = true }
                    if !cagentBinaryPath.isEmpty {
                        Button("Clear") { cagentBinaryPath = "" }
                            .foregroundStyle(Color.secondary)
                    }
                }
                .help("Leave empty to use the auto-downloaded or system cagent binary")
            }

            Section("Links") {
                HStack {
                    Button("cagent on GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/docker/cagent")!)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showBinaryPicker, allowedContentTypes: [.unixExecutable, .data]) { result in
            if case .success(let url) = result { cagentBinaryPath = url.path }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch downloader.state {
        case .idle:
            Label("Not downloaded", systemImage: "arrow.down.circle").foregroundStyle(Color.secondary)
        case .checking:
            Label("Checking\u{2026}", systemImage: "magnifyingglass").foregroundStyle(Color.secondary)
        case .downloading:
            HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Downloading\u{2026}").foregroundStyle(Color.secondary) }
        case .installing:
            HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Installing\u{2026}").foregroundStyle(Color.secondary) }
        case .ready(let version):
            Label(version, systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.red).lineLimit(2).help(msg)
        }
    }

    private var buttonLabel: String {
        switch downloader.state {
        case .ready: return "Update"
        case .checking, .downloading, .installing: return "Downloading\u{2026}"
        default: return "Download"
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    if let img = Bundle.main.image(forResource: "Oscar-logo") {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                    }
                    Text("OScar")
                        .font(.title.bold())
                    Text("Version \(version)")
                        .foregroundStyle(Color.secondary)
                    Text("Operating System for Cognitive Agent Runtime")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Links") {
                HStack {
                    Button("OScar on GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/jalonsogo/oscar")!)
                    }
                    Spacer()
                    Button("cagent on GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/docker/cagent")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
