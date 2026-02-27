import SwiftUI

/// Full conversation window — sidebar on the left, chat on the right.
struct ConversationView: View {
    let initialSessionId: String
    let initialQuery: String?
    /// Agent name override for the first session (e.g. "claude", "claude-box").
    let agentOverride: String?

    @EnvironmentObject var state: AppState

    // Active session — can be changed by clicking the sidebar
    @State private var currentSessionId: String
    @State private var messages: [DisplayMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var agentStatus: AgentStatus = .idle
    @State private var sessionTitle: String = "New conversation"
    @State private var tokenInfo: String = ""
    @State private var currentAgentName: String = ""
    @State private var currentModelName: String = ""
    @State private var streamingTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    init(sessionId: String, initialQuery: String? = nil, agentOverride: String? = nil) {
        self.initialSessionId = sessionId
        self.initialQuery = initialQuery
        self.agentOverride = agentOverride
        self._currentSessionId = State(initialValue: sessionId)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                titleBar
                Divider()
                messageList
                Divider()
                inputBar
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(sessionTitle)
        .onAppear {
            isInputFocused = true
            loadHistory(for: currentSessionId)
            if let query = initialQuery, !query.isEmpty {
                inputText = query
                Task { await send() }
            }
        }
        .onDisappear {
            streamingTask?.cancel()
            state.markIdle(currentSessionId)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(state.sessions.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.sessions) { session in
                        SidebarSessionRow(
                            session: session,
                            isSelected:  session.id == currentSessionId,
                            isStreaming: state.streamingSessions.contains(session.id),
                            isWaiting:   state.waitingSessions.contains(session.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { switchToSession(session.id) }
                    }
                }
            }
        }
        .frame(width: 210)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(sessionTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                switch agentStatus {
                case .idle: EmptyView()
                case .thinking:
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Thinking\u{2026}").font(.caption).foregroundStyle(.secondary)
                    }
                case .runningTool(let name):
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Running \(name)\u{2026}").font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            if !tokenInfo.isEmpty {
                Text(tokenInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message OScar\u{2026}", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .onSubmit {
                    guard !isStreaming else { return }
                    Task { await send() }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                if isStreaming {
                    streamingTask?.cancel()
                    isStreaming = false
                    agentStatus = .idle
                    state.markIdle(currentSessionId)
                } else {
                    Task { await send() }
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(sendButtonColor)
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && inputText.isEmpty)
        }
        .padding(12)
    }

    private var sendButtonColor: Color {
        if isStreaming { return .red }
        return inputText.isEmpty ? .secondary : .blue
    }

    // MARK: - Session switching

    @MainActor
    private func switchToSession(_ newId: String) {
        guard newId != currentSessionId else { return }

        streamingTask?.cancel()
        state.markIdle(currentSessionId)

        currentSessionId = newId
        messages = []
        inputText = ""
        isStreaming = false
        agentStatus = .idle
        tokenInfo = ""
        currentAgentName = ""
        currentModelName = ""

        loadHistory(for: newId)
        isInputFocused = true
    }

    private func loadHistory(for id: String) {
        let history = SessionStore.loadMessages(sessionId: id)
        messages = history.map { msg in
            DisplayMessage(
                role: msg.role == "user" ? .user : .assistant,
                content: msg.content
            )
        }
        guard let session = state.sessions.first(where: { $0.id == id }) else { return }
        sessionTitle = session.title.nilIfEmpty ?? "New conversation"

        // Show what we have immediately from the session summary
        let agentName = state.sessionAgentMap[id] ?? state.agentName
        currentAgentName = agentName
        currentModelName = ""
        tokenInfo = buildTokenInfo(
            agent: agentName, model: nil,
            input: session.inputTokens, output: session.outputTokens, cost: nil
        )

        // Fetch full detail (model + cost) from the API asynchronously
        Task { await fetchSessionMetadata(for: id) }
    }

    @MainActor
    private func fetchSessionMetadata(for id: String) async {
        guard let detail = try? await state.client.getSession(id) else { return }
        guard currentSessionId == id else { return }  // Session switched while fetching

        let assistantMessages = detail.messages.filter { $0.message.role == "assistant" }
        let agentName = assistantMessages.last?.agentName?.nilIfEmpty ?? currentAgentName
        let model = assistantMessages.last?.message.model
        let totalCost = assistantMessages.compactMap { $0.message.cost }.reduce(0, +)

        currentAgentName = agentName
        if let model, !model.isEmpty { currentModelName = model }
        let session = state.sessions.first(where: { $0.id == id })
        tokenInfo = buildTokenInfo(
            agent: currentAgentName,
            model: currentModelName.nilIfEmpty,
            input: session?.inputTokens ?? 0,
            output: session?.outputTokens ?? 0,
            cost: totalCost > 0 ? totalCost : nil
        )
    }

    private func buildTokenInfo(agent: String, model: String?, input: Int64, output: Int64, cost: Double?) -> String {
        var parts: [String] = []
        if !agent.isEmpty { parts.append(agent) }
        if let model, !model.isEmpty { parts.append(model) }
        parts.append("\(input)\u{2191} \(output)\u{2193}")
        if let cost, cost > 0 { parts.append(String(format: "$%.4f", cost)) }
        return parts.joined(separator: "  \u{00B7}  ")
    }

    // MARK: - Scroll

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Send

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isStreaming = true
        agentStatus = .thinking
        state.markStreaming(currentSessionId)

        messages.append(DisplayMessage(role: .user, content: text))

        let placeholder = DisplayMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        let assistantId = placeholder.id

        let sid = currentSessionId
        streamingTask = Task { @MainActor in
            // Use stored agent for this session, fall back to override or global setting
            let agent = state.sessionAgentMap[sid] ?? agentOverride ?? state.agentName
            currentAgentName = agent
            let chatMessages = [ChatMessage(role: "user", content: text)]
            let stream = state.client.chat(sessionId: sid, agentName: agent, messages: chatMessages)

            for await event in stream {
                guard !Task.isCancelled else { break }
                handleEvent(event, assistantMsgId: assistantId)
            }

            isStreaming = false
            agentStatus = .idle
            state.markWaiting(sid)
            finishAssistantMessage(id: assistantId)
            Task { await state.loadSessions() }
        }
    }

    // MARK: - Event handling

    @MainActor
    private func handleEvent(_ event: CagentEvent, assistantMsgId: UUID) {
        switch event {
        case .agentChoice(let content, _, let model):
            if let model { currentModelName = model }
            appendToMessage(id: assistantMsgId, chunk: content)

        case .agentChoiceReasoning(let content):
            appendToMessage(id: assistantMsgId, chunk: content)

        case .toolCall(_, let name, let arguments):
            agentStatus = .runningTool(name)
            messages.append(DisplayMessage(role: .tool, content: arguments, toolName: name, isStreaming: true))

        case .toolResponse(let name, let response, let isError):
            agentStatus = .thinking
            if let idx = messages.lastIndex(where: { $0.role == .tool && $0.toolName == name && $0.isStreaming }) {
                messages[idx].content = response
                messages[idx].isError = isError
                messages[idx].isStreaming = false
            }

        case .sessionTitle(let title, _):
            sessionTitle = title

        case .tokenUsage(let input, let output, let cost, let model):
            if let model { currentModelName = model }
            tokenInfo = buildTokenInfo(
                agent: currentAgentName, model: currentModelName.nilIfEmpty,
                input: input, output: output, cost: cost > 0 ? cost : nil
            )

        case .error(let message):
            messages.append(DisplayMessage(role: .system, content: "\u{26A0} \(message)", isError: true))
            isStreaming = false
            agentStatus = .idle
            state.markWaiting(currentSessionId)

        case .maxIterationsReached:
            messages.append(DisplayMessage(role: .system, content: "Maximum iterations reached."))
            isStreaming = false
            agentStatus = .idle
            state.markWaiting(currentSessionId)

        case .streamStopped:
            isStreaming = false
            agentStatus = .idle
            state.markWaiting(currentSessionId)

        default:
            break
        }
    }

    @MainActor
    private func appendToMessage(id: UUID, chunk: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].content += chunk
        }
    }

    @MainActor
    private func finishAssistantMessage(id: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].isStreaming = false
        }
    }
}

// MARK: - Sidebar row

private struct SidebarSessionRow: View {
    let session: SessionSummary
    let isSelected: Bool
    let isStreaming: Bool
    let isWaiting: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "Untitled" : session.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("\(session.numMessages) msgs")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if isStreaming {
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if isWaiting {
                        Text("Waiting")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if isStreaming { return .green }
        if isWaiting   { return .orange }
        return Color(NSColor.tertiaryLabelColor)
    }
}

// MARK: - Agent status

enum AgentStatus {
    case idle
    case thinking
    case runningTool(String)
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: DisplayMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if let toolName = message.toolName {
                    Label(toolName, systemImage: "wrench")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Group {
                    if message.content.isEmpty && message.isStreaming {
                        ProgressView()
                            .scaleEffect(0.6)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        Text(message.content)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .background(bubbleBackground)
                .foregroundStyle(bubbleForeground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:      return .blue
        case .assistant: return Color(NSColor.controlBackgroundColor)
        case .tool:      return Color(NSColor.textBackgroundColor)
        case .thinking:  return Color.purple.opacity(0.12)
        case .system:    return message.isError ? Color.red.opacity(0.1) : Color.gray.opacity(0.1)
        }
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .primary
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
