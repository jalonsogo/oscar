import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            AgentsTab()
                .tabItem { Label("Agents", systemImage: "person.2.wave.2") }

            DockerAgentTab()
                .tabItem { Label("Docker Agent", systemImage: "shippingbox") }

            UpdateTab(downloader: state.downloader) {
                Task { await state.downloadCagent() }
            }
            .tabItem { Label("Update", systemImage: "arrow.down.circle") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .environmentObject(state)
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 500)
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
                LabeledContent("Agent name") {
                    TextField("agent", text: $agentName)
                        .frame(maxWidth: 200)
                }
                .help("Run mode passed to /api/sessions/{id}/agent/{name}")

                LabeledContent("Config file") {
                    HStack {
                        Text(configLabel)
                            .foregroundStyle(agentConfigPath.isEmpty ? Color.red : Color.secondary)
                            .lineLimit(1)
                        Button("Choose\u{2026}") { showConfigPicker = true }
                        if !agentConfigPath.isEmpty {
                            Button("Create default") { createDefaultConfig() }
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .help("Path to your cagent agent.yaml")

                LabeledContent("Sessions folder") {
                    HStack {
                        Text(sessionsFolderLabel)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                        Button("Choose\u{2026}") { pickSessionsFolder() }
                        if !sessionsFolderPath.isEmpty {
                            Button("Clear") { sessionsFolderPath = "" }
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                .help("New sessions are created in {folder}/{session_name}")
            }

            Section("Server") {
                LabeledContent("Port") {
                    TextField("8080", value: $serverPort, format: .number)
                        .frame(maxWidth: 80)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(state.serverStatus.description).foregroundStyle(Color.secondary)
                        Spacer()
                        Button("Restart") {
                            state.process.stop()
                            Task { await state.start() }
                        }
                    }
                }

                LabeledContent("Sessions") {
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
                LabeledContent("Folder") {
                    HStack {
                        Text(folderLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Choose\u{2026}") { pickFolder() }
                        if !agentsFolderPath.isEmpty {
                            Button("Clear") { agentsFolderPath = "" }
                                .foregroundStyle(.secondary)
                        }
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
    @AppStorage("boxAgentSuffix") private var boxAgentSuffix: String = "-box"

    var body: some View {
        Form {
            Section("Prefix Routing") {
                LabeledContent("Box agent suffix") {
                    TextField("-box", text: $boxAgentSuffix)
                        .frame(maxWidth: 120)
                }
                .help("Appended to the agent name when using the box/ prefix. E.g. claude-box")

                VStack(alignment: .leading, spacing: 6) {
                    Text("How to use prefix routing in Quick Entry or Spotlight:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        Text("• ") + Text("claude/query").font(.system(.caption, design: .monospaced)) + Text(" — use the \"claude\" agent")
                        Text("• ") + Text("box/claude/query").font(.system(.caption, design: .monospaced)) + Text(" — use \"claude\(boxAgentSuffix)\" (Docker sandbox)")
                        Text("• ") + Text("query").font(.system(.caption, design: .monospaced)) + Text(" — use the default agent")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Agent Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Define sandbox agents in your agent.yaml:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(yamlExample)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(NSColor.systemGreen))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var yamlExample: String {
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
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        statusBadge
                        Spacer()
                        Button(buttonLabel, action: onDownload)
                            .disabled(downloader.state.isInProgress)
                    }
                }

                LabeledContent("Override path") {
                    HStack {
                        TextField("Auto-detected", text: $cagentBinaryPath)
                            .frame(maxWidth: 200)
                        Button("Choose\u{2026}") { showBinaryPicker = true }
                        if !cagentBinaryPath.isEmpty {
                            Button("Clear") { cagentBinaryPath = "" }
                                .foregroundStyle(Color.secondary)
                        }
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
