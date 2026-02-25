import SwiftUI

/// Settings window. Uses @AppStorage directly (it's a View) for two-way binding.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    // Bindings to UserDefaults — must mirror keys in AppState computed properties
    @AppStorage("cagentBinaryPath") private var cagentBinaryPath: String = "/usr/local/bin/cagent"
    @AppStorage("agentConfigPath") private var agentConfigPath: String = ""
    @AppStorage("serverPort") private var serverPort: Int = 8080
    @AppStorage("agentName") private var agentName: String = "agent"
    @AppStorage("workingDir") private var workingDir: String = ""

    @State private var showBinaryPicker = false
    @State private var showConfigPicker = false

    var body: some View {
        Form {
            Section("Agent") {
                LabeledContent("Agent name") {
                    TextField("agent", text: $agentName)
                        .frame(maxWidth: 200)
                }
                .help("The run mode passed to the cagent API endpoint (default: \"agent\")")

                LabeledContent("Config file") {
                    HStack {
                        Text(configLabel)
                            .foregroundStyle(agentConfigPath.isEmpty ? Color.red : Color.secondary)
                            .lineLimit(1)
                        Button("Choose\u{2026}") { showConfigPicker = true }
                    }
                }
                .help("Path to your cagent agent.yaml")

                LabeledContent("Working dir") {
                    HStack {
                        TextField(
                            FileManager.default.homeDirectoryForCurrentUser.path,
                            text: $workingDir
                        )
                        .frame(maxWidth: 200)
                        Button("Choose\u{2026}") { pickWorkingDir() }
                    }
                }
            }

            Section("Server") {
                LabeledContent("cagent binary") {
                    HStack {
                        TextField("/usr/local/bin/cagent", text: $cagentBinaryPath)
                            .frame(maxWidth: 200)
                        Button("Choose\u{2026}") { showBinaryPicker = true }
                    }
                }

                LabeledContent("Port") {
                    TextField("8080", value: $serverPort, format: .number)
                        .frame(maxWidth: 80)
                }

                HStack {
                    Spacer()
                    Button("Restart Server") {
                        state.process.stop()
                        Task { await state.start() }
                    }
                }
            }

            Section("Status") {
                LabeledContent("Server") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(state.serverStatus.description)
                            .foregroundStyle(Color.secondary)
                    }
                }
                LabeledContent("Sessions") {
                    Text("\(state.sessions.count)").foregroundStyle(Color.secondary)
                }
            }

            Section {
                HStack {
                    Button("Create default agent.yaml\u{2026}") { createDefaultConfig() }
                    Spacer()
                    Button("cagent on GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/docker/cagent")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .fileImporter(
            isPresented: $showBinaryPicker,
            allowedContentTypes: [.unixExecutable, .data]
        ) { result in
            if case .success(let url) = result {
                cagentBinaryPath = url.path
            }
        }
        .fileImporter(
            isPresented: $showConfigPicker,
            allowedContentTypes: [.text, .data]
        ) { result in
            if case .success(let url) = result {
                agentConfigPath = url.path
            }
        }
    }

    private var configLabel: String {
        if agentConfigPath.isEmpty { return "Not set" }
        return URL(fileURLWithPath: agentConfigPath).lastPathComponent
    }

    private var statusColor: Color {
        switch state.serverStatus {
        case .running: return .green
        case .launching: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private func pickWorkingDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            workingDir = url.path
        }
    }

    private func createDefaultConfig() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/oscar")
        let configFile = configDir.appendingPathComponent("agent.yaml")
        let yaml = """
        version: 1

        agents:
          root:
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
            state.alert = AlertInfo(message: "Failed to create config: \(error.localizedDescription)")
        }
    }
}
