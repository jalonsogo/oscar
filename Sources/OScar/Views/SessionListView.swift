import SwiftUI

/// Shows all sessions with search and actions. Lives inside the MenuBarExtra popover.
struct SessionListView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText: String = ""
    @State private var sessionToDelete: SessionSummary? = nil
    @State private var showDeleteConfirmation: Bool = false

    var filtered: [SessionSummary] {
        guard !searchText.isEmpty else { return state.sessions }
        return state.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.workingDir ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if filtered.isEmpty {
                emptyState
            } else {
                sessionList
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

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Search sessions\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var sessionList: some View {
        List(filtered) { session in
            SessionRow(session: session)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.openWindowAction?(session.id)
                }
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
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No sessions yet" : "No results")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: SessionSummary
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title.isEmpty ? "Untitled" : session.title)
                .lineLimit(1)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(session.numMessages) msgs")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let dir = session.workingDir {
                    Text(URL(fileURLWithPath: dir).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isHovered
                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.3)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }

    private var formattedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: session.createdAt) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        // Fallback without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: session.createdAt) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return session.createdAt
    }
}
