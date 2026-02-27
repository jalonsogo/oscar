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
    @State private var remoteMode: Bool = false
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
                        ZStack {
                            Circle()
                                .fill(query.isEmpty
                                      ? Color(NSColor.quaternaryLabelColor)
                                      : Color.accentColor)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(query.isEmpty
                                                 ? Color(NSColor.tertiaryLabelColor)
                                                 : .white)
                        }
                        .frame(width: 28, height: 28)
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
                AgentDropdownButton(
                    selection: $selectedAgent,
                    defaultName: defaultAgentName,
                    sandboxes: sandboxEntries,
                    agents: discoveredAgents
                )
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                // Local / Remote toggle
                HStack(spacing: 0) {
                    modeButton("Local",  active: !remoteMode, disabled: false) { remoteMode = false }
                    modeButton("Remote", active: remoteMode,  disabled: true)  { remoteMode = true  }
                }
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private var sandboxEntries: [(display: String, value: String)] {
        [("Cagent", "cagent\(boxAgentSuffix)"),
         ("Claude", "claude\(boxAgentSuffix)"),
         ("Codex",  "codex\(boxAgentSuffix)"),
         ("Gemini", "gemini\(boxAgentSuffix)")]
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
        selectedAgent.isEmpty ? defaultAgentName : selectedAgent
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

// MARK: - Agent Dropdown

private struct AgentDropdownButton: View {
    @Binding var selection: String
    let defaultName: String
    let sandboxes: [(display: String, value: String)]
    let agents: [String]

    @State private var isOpen = false
    @State private var search = ""

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 5) {
                if isSandbox {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(selectionLabel)
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            AgentPickerPopover(
                selection: $selection,
                isOpen: $isOpen,
                search: $search,
                defaultName: defaultName,
                sandboxes: sandboxes,
                agents: agents
            )
        }
    }

    private var isSandbox: Bool {
        sandboxes.contains { $0.value == selection }
    }

    private var selectionLabel: String {
        if selection.isEmpty { return defaultName }
        return sandboxes.first { $0.value == selection }?.display ?? selection
    }
}

private struct AgentPickerPopover: View {
    @Binding var selection: String
    @Binding var isOpen: Bool
    @Binding var search: String
    let defaultName: String
    let sandboxes: [(display: String, value: String)]
    let agents: [String]

    @FocusState private var searchFocused: Bool

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedCaseInsensitiveContains(search)
    }

    private func pick(_ value: String) {
        selection = value
        isOpen = false
        search = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Search\u{2026}", text: $search)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Default agent
                    if matches(defaultName) {
                        groupHeader("Default")
                        pickerRow(label: defaultName, value: "", icon: "person.circle")
                    }

                    // Sandboxes group
                    let filteredSandboxes = sandboxes.filter { matches($0.display) }
                    if !filteredSandboxes.isEmpty {
                        groupHeader("Sandboxes")
                        ForEach(filteredSandboxes, id: \.value) { item in
                            pickerRow(label: item.display, value: item.value,
                                      icon: "shippingbox.fill", iconColor: .orange,
                                      badge: "sandbox")
                        }
                    }

                    // Agents group
                    let filteredAgents = agents.filter { matches($0) }
                    if !filteredAgents.isEmpty {
                        groupHeader("Agents")
                        ForEach(filteredAgents, id: \.self) { agent in
                            pickerRow(label: agent, value: agent, icon: "doc.text")
                        }
                    }

                    if !matches(defaultName) && sandboxes.filter({ matches($0.display) }).isEmpty && agents.filter({ matches($0) }).isEmpty {
                        Text("No results")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 210)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pickerRow(
        label: String,
        value: String,
        icon: String,
        iconColor: Color = .secondary,
        badge: String? = nil
    ) -> some View {
        let isSelected = selection == value
        Button { pick(value) } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark" : icon)
                    .font(.caption)
                    .frame(width: 14)
                    .foregroundStyle(isSelected ? Color.primary : iconColor)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(Color.primary)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
