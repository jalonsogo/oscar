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
        .background(.regularMaterial)
    }

    @State private var hoveredSessionId: String? = nil

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { session in
                    SessionRow(
                        session: session,
                        isHovered: hoveredSessionId == session.id
                    ) {
                        sessionToDelete = session
                        showDeleteConfirmation = true
                    }
                    .contentShape(Rectangle())
                    .onHover { hovered in
                        hoveredSessionId = hovered ? session.id : nil
                    }
                    .onTapGesture(count: 2) {
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
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
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
    let isHovered: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
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

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete session")
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isHovered ? Color.accentColor.opacity(0.15) : Color.clear
        )
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
