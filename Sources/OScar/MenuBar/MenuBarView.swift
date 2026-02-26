import SwiftUI
import AppKit

/// Content of the MenuBarExtra popover window.
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @State private var showQuitConfirmation = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()

                if state.serverStatus.isRunning {
                    SessionListView()
                        .frame(height: 380)
                } else {
                    serverStatusView
                        .frame(height: 380)
                }

                Divider()
                footer
            }

            if showQuitConfirmation {
                quitOverlay
                    .zIndex(1)
            }
        }
        .frame(width: 320)
        .background(.clear)
        .alert(item: $state.alert) { info in
            Alert(title: Text("OScar"), message: Text(info.message))
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("OScar")
                    .fontWeight(.semibold)
            }

            Spacer()

            Button {
                Task { await state.loadSessions() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!state.serverStatus.isRunning)

            Button {
                NotificationCenter.default.post(name: .oscOpenQuickEntry, object: nil)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(!state.serverStatus.isRunning)
            .help("New conversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text("\(state.sessions.count) sessions")
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Settings") {
                state.openSettingsAction?()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button("Quit") {
                showQuitConfirmation = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var quitOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Quit OScar?")
                    .font(.headline)
                Text("The cagent server and all active sessions will be stopped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showQuitConfirmation = false
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.bordered)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            .padding(24)
            .zIndex(2)
        }
    }

    private var serverStatusView: some View {
        VStack(spacing: 16) {
            Spacer()

            switch state.serverStatus {
            case .launching:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Starting cagent\u{2026}")
                        .foregroundStyle(.secondary)
                }

            case .error(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    HStack {
                        Button("Retry") {
                            Task { await state.start() }
                        }
                        Button("Install cagent") {
                            CagentProcess.openCagentInstallPage()
                        }
                    }
                }

            case .stopped:
                VStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Server stopped")
                        .foregroundStyle(.secondary)
                    Button("Start") { Task { await state.start() } }
                }

            case .running:
                EmptyView()
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        switch state.serverStatus {
        case .running: return .green
        case .launching: return .yellow
        case .error: return .red
        case .stopped: return .gray
        }
    }
}
