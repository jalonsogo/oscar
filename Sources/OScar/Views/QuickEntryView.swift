import SwiftUI
import AppKit

/// Floating quick-entry window. Opens via menu bar "+" or global hotkey.
/// Creates a session and opens a ConversationView window pre-filled with the query.
struct QuickEntryView: View {
    @EnvironmentObject var state: AppState

    @State private var query: String = ""
    @State private var isCreating: Bool = false
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    var prefillQuery: String = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundStyle(Color.blue)

                TextField("Ask OScar anything\u{2026}", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .focused($focused)
                    .onSubmit { Task { await create() } }

                if isCreating {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button {
                        Task { await create() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(query.isEmpty ? Color.secondary : Color.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(query.isEmpty)
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.25), radius: 20, y: 8)
        .onAppear {
            focused = true
            if !prefillQuery.isEmpty { query = prefillQuery }
        }
    }

    // MARK: - Actions

    private func create() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isCreating = true
        error = nil

        let parsed = parseQueryPrefix(text)

        do {
            let title = String(parsed.query.prefix(60))
            let session = try await state.createSession(title: title)
            var payload = "\(session.id)|\(parsed.query)"
            if let agent = parsed.effectiveAgentName {
                payload += "|\(agent)"
            }
            state.openWindowAction?(payload)
        } catch {
            self.error = error.localizedDescription
            isCreating = false
        }
    }
}
