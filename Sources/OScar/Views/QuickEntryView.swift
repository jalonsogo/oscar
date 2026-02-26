import SwiftUI
import AppKit

/// Floating quick-entry window. Opens via menu bar "+" or global hotkey.
struct QuickEntryView: View {
    @EnvironmentObject var state: AppState

    @AppStorage("agentName")        private var defaultAgentName: String = "agent"
    @AppStorage("agentsFolderPath") private var agentsFolderPath: String  = ""
    @AppStorage("boxAgentSuffix")   private var boxAgentSuffix: String    = "-box"

    @State private var query: String = ""
    @State private var isCreating: Bool = false
    @State private var error: String? = nil
    @State private var selectedAgent: String = ""   // "" = use default
    @State private var remoteMode: Bool = false      // Remote TBD
    @State private var sandboxMode: Bool = false
    @FocusState private var focused: Bool

    var prefillQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Input row
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)

                TextField("Ask OScar anything\u{2026}", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { Task { await create() } }

                if isCreating {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { Task { await create() } } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(query.isEmpty ? Color.secondary : Color.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(query.isEmpty)
                }
            }
            .padding(20)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            // MARK: Options row
            HStack(spacing: 0) {

                // Agent picker
                Picker("", selection: $selectedAgent) {
                    Text(defaultAgentName)
                        .tag("")
                    if !discoveredAgents.isEmpty {
                        Divider()
                        ForEach(discoveredAgents, id: \.self) { agent in
                            Text(agent).tag(agent)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                optionDivider

                // Local / Remote toggle
                HStack(spacing: 0) {
                    modeButton("Local",  active: !remoteMode,  disabled: false) { remoteMode = false }
                    modeButton("Remote", active: remoteMode,   disabled: true)  { remoteMode = true  }
                }
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                optionDivider

                // Sandbox toggle
                Toggle(isOn: $sandboxMode) {
                    Text("Sandbox")
                        .font(.callout)
                        .foregroundStyle(sandboxMode ? .primary : .secondary)
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.25), radius: 20, y: 8)
        .onAppear {
            focused = true
            if !prefillQuery.isEmpty { query = prefillQuery }
        }
    }

    // MARK: - Helpers

    private var optionDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func modeButton(
        _ label: String,
        active: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? Color.primary.opacity(0.12) : Color.clear)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : (active ? Color.primary : Color.secondary))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var discoveredAgents: [String] {
        guard !agentsFolderPath.isEmpty else { return [] }
        let url = URL(fileURLWithPath: (agentsFolderPath as NSString).expandingTildeInPath)
        let files = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        return (files ?? [])
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private var effectiveAgent: String {
        let base = selectedAgent.isEmpty ? defaultAgentName : selectedAgent
        return sandboxMode ? "\(base)\(boxAgentSuffix)" : base
    }

    // MARK: - Create session

    private func create() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isCreating = true
        error = nil

        let agent = effectiveAgent

        do {
            let session = try await state.createSession(title: String(text.prefix(60)))
            state.recordAgent(agent, for: session.id)
            let payload = "\(session.id)|\(text)|\(agent)"
            state.openWindowAction?(payload)
        } catch {
            self.error = error.localizedDescription
            isCreating = false
        }
    }
}
