import SwiftUI

// MARK: - Tab

enum SessionTab: String, CaseIterable {
    case local     = "Local"
    case remote    = "Remote"
    case sandboxes = "Sandboxes"
    case agents    = "Agents"
}

/// Shows sessions / agents inside the MenuBar popover.
struct SessionListView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("agentsFolderPath") private var agentsFolderPath: String = ""
    @AppStorage("boxAgentSuffix")   private var boxAgentSuffix: String   = "-box"

    @Binding var selectedTab: SessionTab
    @State private var searchText: String = ""
    @State private var sessionToDelete: SessionSummary? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var hoveredSessionId: String? = nil

    // MARK: - Filtered data

    private var sandboxSessions: [SessionSummary] {
        state.sessions.filter { session in
            guard let agent = state.sessionAgentMap[session.id] else { return false }
            return agent.hasSuffix(boxAgentSuffix)
        }
    }

    private var tabSessions: [SessionSummary] {
        let base: [SessionSummary]
        switch selectedTab {
        case .local:     base = state.sessions
        case .sandboxes: base = sandboxSessions
        case .remote, .agents: return []
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.workingDir ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var waitingFiltered:   [SessionSummary] { tabSessions.filter { state.waitingSessions.contains($0.id) } }
    private var streamingFiltered: [SessionSummary] { tabSessions.filter { state.streamingSessions.contains($0.id) } }
    private var finalizedFiltered: [SessionSummary] { tabSessions.filter {
        !state.waitingSessions.contains($0.id) && !state.streamingSessions.contains($0.id)
    }}

    // MARK: - Agents tab data

    private var discoveredAgentNames: [String] {
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

    private func sessions(forAgent agentName: String) -> [SessionSummary] {
        state.sessions.filter { state.sessionAgentMap[$0.id] == agentName }
    }

    private var unassignedSessions: [SessionSummary] {
        let assigned = Set(state.sessionAgentMap.keys)
        return state.sessions.filter { !assigned.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            if selectedTab != .agents && selectedTab != .remote {
                searchBar
            }

            switch selectedTab {
            case .remote:
                remotePlaceholder
            case .agents:
                agentSections
            case .local, .sandboxes:
                if tabSessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
        }
        .confirmationDialog(
            "Delete session?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    Task { await state.deleteSession(id: session.id) }
                    sessionToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            if let title = sessionToDelete?.title, !title.isEmpty {
                Text("This will permanently delete \"\(title)\".")
            }
        }
    }

    // MARK: - Tab bar (pill style)

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SessionTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)

                        if let count = tabBadge(tab) {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(selectedTab == tab
                                       ? Color.primary.opacity(0.1)
                                       : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func tabBadge(_ tab: SessionTab) -> Int? {
        switch tab {
        case .local:     return state.sessions.isEmpty      ? nil : state.sessions.count
        case .sandboxes: return sandboxSessions.isEmpty     ? nil : sandboxSessions.count
        case .remote:    return nil
        case .agents:    return discoveredAgentNames.isEmpty ? nil : discoveredAgentNames.count
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).font(.callout)
            TextField("Search sessions\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - Session list (Local / Sandboxes)

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !waitingFiltered.isEmpty {
                    sectionHeader("Waiting for reply", color: .orange)
                    rows(for: waitingFiltered)
                }
                if !streamingFiltered.isEmpty {
                    if !waitingFiltered.isEmpty { groupDivider }
                    sectionHeader("Running", color: .green)
                    rows(for: streamingFiltered)
                }
                if !finalizedFiltered.isEmpty {
                    if !waitingFiltered.isEmpty || !streamingFiltered.isEmpty { groupDivider }
                    rows(for: finalizedFiltered)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func rows(for sessions: [SessionSummary]) -> some View {
        ForEach(sessions) { session in
            SessionRow(
                session: session,
                isHovered: hoveredSessionId == session.id,
                isStreaming: state.streamingSessions.contains(session.id),
                isWaiting: state.waitingSessions.contains(session.id)
            ) {
                sessionToDelete = session
                showDeleteConfirmation = true
            }
            .contentShape(Rectangle())
            .onHover { hovered in hoveredSessionId = hovered ? session.id : nil }
            .onTapGesture(count: 2) { state.openWindowAction?(session.id) }
            .contextMenu {
                Button("Open") { state.openWindowAction?(session.id) }
                Button("Copy ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
                Divider()
                Button("Delete\u{2026}", role: .destructive) {
                    sessionToDelete = session
                    showDeleteConfirmation = true
                }
            }
        }
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var groupDivider: some View {
        Divider().padding(.horizontal, 4).padding(.vertical, 6)
    }

    // MARK: - Agents tab

    private var agentSections: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Open folder button
                if !agentsFolderPath.isEmpty {
                    HStack {
                        Text((agentsFolderPath as NSString).abbreviatingWithTildeInPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            let path = (agentsFolderPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: {
                            Label("Open folder", systemImage: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.05))

                    Divider()
                }

                if discoveredAgentNames.isEmpty {
                    VStack(spacing: 10) {
                        Spacer().frame(height: 20)
                        Image(systemName: "person.2.wave.2")
                            .font(.largeTitle).foregroundStyle(.tertiary)
                        Text("No agents configured")
                            .font(.headline).foregroundStyle(.secondary)
                        Text("Set an agents folder in Settings\nto see your agents here.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        Spacer().frame(height: 20)
                    }
                } else {
                    ForEach(discoveredAgentNames, id: \.self) { agentName in
                        AgentSectionRow(
                            agentName: agentName,
                            sessions: sessions(forAgent: agentName)
                        ) { session in
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        }
                    }
                    let others = unassignedSessions
                    if !others.isEmpty {
                        AgentSectionRow(agentName: "Others", sessions: others) { session in
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Placeholders

    private var remotePlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "cloud").font(.largeTitle).foregroundStyle(.tertiary)
            Text("Remote Sessions").font(.headline).foregroundStyle(.secondary)
            Text("Connect to remote cagent instances\nto see their sessions here.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text(searchText.isEmpty
                 ? "No \(selectedTab.rawValue.lowercased()) sessions"
                 : "No results")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Session Row

private struct SessionStatusDot: View {
    enum Status { case streaming, waiting }
    let status: Status
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(status == .streaming ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
            .scaleEffect(pulsing ? 1.3 : 0.8)
            .opacity(pulsing ? 1 : 0.55)
            .animation(
                .easeInOut(duration: status == .streaming ? 0.65 : 1.1)
                    .repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    let isHovered: Bool
    let isStreaming: Bool
    let isWaiting: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(session.title.isEmpty ? "Untitled" : session.title)
                        .lineLimit(1).fontWeight(.medium)
                    if isStreaming {
                        SessionStatusDot(status: .streaming)
                    } else if isWaiting {
                        SessionStatusDot(status: .waiting)
                    }
                }

                HStack(spacing: 8) {
                    if isStreaming {
                        Text("Running\u{2026}").font(.caption).foregroundStyle(.green)
                    } else if isWaiting {
                        Text("Waiting for reply").font(.caption).foregroundStyle(.orange)
                    } else {
                        Text(formattedDate).font(.caption).foregroundStyle(.secondary)
                        Text("\(session.numMessages) msgs").font(.caption).foregroundStyle(.tertiary)
                        if let dir = session.workingDir {
                            Text(URL(fileURLWithPath: dir).lastPathComponent)
                                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete session")
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: session.createdAt) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: session.createdAt) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return session.createdAt
    }
}

// MARK: - Agent Section Row

private struct AgentSectionRow: View {
    @EnvironmentObject var state: AppState
    let agentName: String
    let sessions: [SessionSummary]
    let onDelete: (SessionSummary) -> Void

    @State private var isExpanded = false
    @State private var hoveredSessionId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 12)
                    Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                    Text(agentName).font(.subheadline.weight(.semibold))
                    Spacer()
                    if !sessions.isEmpty {
                        Text("\(sessions.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 30).padding(.vertical, 6)
                } else {
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            isHovered: hoveredSessionId == session.id,
                            isStreaming: state.streamingSessions.contains(session.id),
                            isWaiting: state.waitingSessions.contains(session.id),
                            onDelete: { onDelete(session) }
                        )
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                        .onHover { hovered in hoveredSessionId = hovered ? session.id : nil }
                        .onTapGesture(count: 2) { state.openWindowAction?(session.id) }
                        .contextMenu {
                            Button("Open") { state.openWindowAction?(session.id) }
                            Button("Copy ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(session.id, forType: .string)
                            }
                            Divider()
                            Button("Delete\u{2026}", role: .destructive) { onDelete(session) }
                        }
                    }
                }
            }

            Divider().padding(.horizontal, 4)
        }
    }
}
