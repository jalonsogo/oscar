import SwiftUI
import AppKit

/// Content of the MenuBarExtra popover window.
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @State private var showQuitConfirmation = false
    @State private var selectedTab: SessionTab = .local

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()

                if state.serverStatus.isRunning {
                    SessionListView(selectedTab: $selectedTab)
                        .frame(height: 390)
                } else {
                    serverStatusView
                        .frame(height: 390)
                }

                Divider()
                footer
            }

            if showQuitConfirmation {
                quitOverlay
                    .zIndex(1)
            }
        }
        .frame(width: 340)
        .background(.clear)
        .alert(item: $state.alert) { info in
            Alert(title: Text("OScar"), message: Text(info.message))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Title + server status dot
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("OScar")
                    .font(.headline)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                iconButton("rectangle.stack") {
                    selectedTab = .local
                }
                .help("Sessions")

                iconButton("arrow.clockwise") {
                    Task { await state.loadSessions() }
                }
                .disabled(!state.serverStatus.isRunning)
                .help("Reload sessions")

                iconButton("plus", isProminent: true) {
                    NotificationCenter.default.post(name: .oscOpenQuickEntry, object: nil)
                }
                .disabled(!state.serverStatus.isRunning)
                .help("New session")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            iconButton("gear") {
                state.openSettingsAction?()
            }
            .help("Settings")

            Spacer()

            iconButton("power") {
                showQuitConfirmation = true
            }
            .help("Quit OScar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func iconButton(
        _ systemName: String,
        isActive: Bool = false,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13))
                .foregroundStyle(isProminent ? .white : (isActive ? Color.accentColor : Color(NSColor.secondaryLabelColor)))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isProminent
                              ? Color.black
                              : (isActive
                                 ? Color.accentColor.opacity(0.12)
                                 : Color(NSColor.quaternaryLabelColor)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isActive && !isProminent ? Color.accentColor.opacity(0.45) : Color.clear,
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quit overlay

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
                    Button("Cancel") { showQuitConfirmation = false }
                        .keyboardShortcut(.escape, modifiers: [])
                        .buttonStyle(.bordered)

                    Button("Quit") { NSApplication.shared.terminate(nil) }
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

    // MARK: - Server status

    private var serverStatusView: some View {
        VStack(spacing: 16) {
            Spacer()

            switch state.serverStatus {
            case .launching:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Starting cagent\u{2026}").foregroundStyle(.secondary)
                }

            case .error(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    HStack {
                        Button("Retry") { Task { await state.start() } }
                        Button("Install cagent") { CagentProcess.openCagentInstallPage() }
                    }
                }

            case .stopped:
                VStack(spacing: 8) {
                    Image(systemName: "power").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Server stopped").foregroundStyle(.secondary)
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
        case .running:  return .green
        case .launching: return .yellow
        case .error:    return .red
        case .stopped:  return .gray
        }
    }
}
