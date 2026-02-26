import SwiftUI

/// Full conversation window for a single session.
struct ConversationView: View {
    let sessionId: String
    let initialQuery: String?
    /// Agent name override for this session (e.g. "claude", "claude-box").
    /// When nil the global `AppState.agentName` setting is used.
    let agentOverride: String?

    @EnvironmentObject var state: AppState
    @State private var messages: [DisplayMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var agentStatus: AgentStatus = .idle
    @State private var sessionTitle: String = "New conversation"
    @State private var tokenInfo: String = ""
    @State private var showSwitcher: Bool = false
    @FocusState private var isInputFocused: Bool
    @State private var streamingTask: Task<Void, Never>?

    init(sessionId: String, initialQuery: String? = nil, agentOverride: String? = nil) {
        self.sessionId = sessionId
        self.initialQuery = initialQuery
        self.agentOverride = agentOverride
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(sessionTitle)
        .onAppear {
            isInputFocused = true
            // Load existing conversation history from the local SQLite DB
            let history = SessionStore.loadMessages(sessionId: sessionId)
            messages = history.map { msg in
                DisplayMessage(
                    role: msg.role == "user" ? .user : .assistant,
                    content: msg.content
                )
            }
            if let query = initialQuery, !query.isEmpty {
                inputText = query
                Task { await send() }
            }
        }
        .onDisappear {
            streamingTask?.cancel()
            state.markIdle(sessionId)
        }
    }

    // MARK: - Subviews

    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(sessionTitle)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if !tokenInfo.isEmpty {
                Text(tokenInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch agentStatus {
            case .idle:
                EmptyView()
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

            // Session switcher
            if !state.sessions.isEmpty {
                Button {
                    showSwitcher.toggle()
                } label: {
                    HStack(spacing: 3) {
                        if let idx = state.sessions.firstIndex(where: { $0.id == sessionId }) {
                            Text("\(idx + 1) / \(state.sessions.count)")
                                .monospacedDigit()
                        }
                        Image(systemName: showSwitcher ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSwitcher, arrowEdge: .top) {
                    SessionSwitcherView(currentSessionId: sessionId)
                        .environmentObject(state)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

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
                    state.markIdle(sessionId)
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
        state.markStreaming(sessionId)

        messages.append(DisplayMessage(role: .user, content: text))

        let placeholder = DisplayMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(placeholder)
        let assistantId = placeholder.id

        streamingTask = Task { @MainActor in
            let chatMessages = [ChatMessage(role: "user", content: text)]
            let stream = state.client.chat(
                sessionId: sessionId,
                agentName: agentOverride ?? state.agentName,
                messages: chatMessages
            )

            for await event in stream {
                guard !Task.isCancelled else { break }
                handleEvent(event, assistantMsgId: assistantId)
            }

            isStreaming = false
            agentStatus = .idle
            state.markWaiting(sessionId)
            finishAssistantMessage(id: assistantId)
            Task { await state.loadSessions() }
        }
    }

    // MARK: - Event Handling

    @MainActor
    private func handleEvent(_ event: CagentEvent, assistantMsgId: UUID) {
        switch event {
        case .agentChoice(let content, _):
            appendToMessage(id: assistantMsgId, chunk: content)

        case .agentChoiceReasoning(let content):
            // Show reasoning inline for now
            appendToMessage(id: assistantMsgId, chunk: content)

        case .toolCall(_, let name, let arguments):
            agentStatus = .runningTool(name)
            messages.append(DisplayMessage(
                role: .tool,
                content: arguments,
                toolName: name,
                isStreaming: true
            ))

        case .toolResponse(let name, let response, let isError):
            agentStatus = .thinking
            if let idx = messages.lastIndex(where: {
                $0.role == .tool && $0.toolName == name && $0.isStreaming
            }) {
                messages[idx].content = response
                messages[idx].isError = isError
                messages[idx].isStreaming = false
            }

        case .sessionTitle(let title, _):
            sessionTitle = title

        case .tokenUsage(let input, let output, let cost):
            let costStr = cost > 0 ? String(format: " \u{00B7} $%.4f", cost) : ""
            tokenInfo = "\(input)\u{2191} \(output)\u{2193}\(costStr)"

        case .error(let message):
            messages.append(DisplayMessage(role: .system, content: "\u{26A0} \(message)", isError: true))
            isStreaming = false
            agentStatus = .idle
            state.markWaiting(sessionId)

        case .maxIterationsReached:
            messages.append(DisplayMessage(
                role: .system,
                content: "Maximum iterations reached."
            ))
            isStreaming = false
            agentStatus = .idle
            state.markWaiting(sessionId)

        case .streamStopped:
            isStreaming = false
            agentStatus = .idle
            state.markWaiting(sessionId)

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

// MARK: - Session Switcher

private struct SessionSwitcherView: View {
    let currentSessionId: String
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.sessions.enumerated()), id: \.element.id) { index, session in
                    Button {
                        dismiss()
                        if session.id != currentSessionId {
                            state.openWindowAction?(session.id)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(dotColor(for: session.id))
                                .frame(width: 7, height: 7)

                            Text(session.title.isEmpty ? "Untitled" : session.title)
                                .lineLimit(1)
                                .fontWeight(session.id == currentSessionId ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 24, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            session.id == currentSessionId
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < state.sessions.count - 1 {
                        Divider().padding(.horizontal, 8)
                    }
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 320)
    }

    private func dotColor(for id: String) -> Color {
        if state.streamingSessions.contains(id) { return .green }
        if state.waitingSessions.contains(id)   { return .orange }
        return Color(NSColor.tertiaryLabelColor)
    }
}

// MARK: - Agent Status

enum AgentStatus {
    case idle
    case thinking
    case runningTool(String)
}

// MARK: - Message Bubble

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
        case .user:
            return .blue
        case .assistant:
            return Color(NSColor.controlBackgroundColor)
        case .tool:
            return Color(NSColor.textBackgroundColor)
        case .thinking:
            return Color.purple.opacity(0.12)
        case .system:
            return message.isError ? Color.red.opacity(0.1) : Color.gray.opacity(0.1)
        }
    }

    private var bubbleForeground: Color {
        message.role == .user ? .white : .primary
    }
}
