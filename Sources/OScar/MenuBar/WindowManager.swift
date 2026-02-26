import AppKit
import SwiftUI

/// Borderless NSWindow that can still become key (required for text input).
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Opens and tracks conversation + quick-entry windows using AppKit directly.
/// This avoids SwiftUI's WindowGroup which auto-opens on launch.
@MainActor
final class WindowManager {
    private var conversationWindows: [String: NSWindow] = [:]
    private var quickEntryWindow: NSWindow?   // Strong ref — prevents autorelease double-free
    private var quickEntryKeyMonitor: Any?    // Local key monitor for Escape
    private var settingsWindow: NSWindow?     // Strong ref — same reason
    private weak var state: AppState?

    func setup(state: AppState) {
        self.state = state
        state.openWindowAction = { [weak self] payload in
            self?.open(payload: payload)
        }
        state.openSettingsAction = { [weak self] in
            self?.openSettings()
        }
        NotificationCenter.default.addObserver(
            forName: .oscOpenQuickEntry,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.openQuickEntry() }
        }
    }

    // MARK: - Open

    func open(payload: String) {
        let parts = payload.split(separator: "|", maxSplits: 2).map(String.init)
        let sessionId = parts[0]
        let query = parts.count > 1 ? parts[1] : nil
        let agentOverride = parts.count > 2 ? parts[2] : nil
        openConversation(sessionId: sessionId, initialQuery: query, agentOverride: agentOverride)
        // Defer QuickEntry close to the next main-actor turn so that
        // create() has fully returned before the window (and its SwiftUI
        // hierarchy) is torn down — prevents an autorelease double-free.
        Task { @MainActor [weak self] in self?.closeQuickEntry() }
    }

    private func closeQuickEntry() {
        if let monitor = quickEntryKeyMonitor {
            NSEvent.removeMonitor(monitor)
            quickEntryKeyMonitor = nil
        }
        quickEntryWindow?.close()
        quickEntryWindow = nil
    }

    func openConversation(sessionId: String, initialQuery: String? = nil, agentOverride: String? = nil) {
        // Bring existing window to front if already open
        if let existing = conversationWindows[sessionId] {
            bringToFront(existing)
            return
        }

        guard let state else { return }

        let view = ConversationView(sessionId: sessionId, initialQuery: initialQuery, agentOverride: agentOverride)
            .environmentObject(state)

        let window = makeWindow(title: "OScar", size: NSSize(width: 900, height: 700), autosaveName: "conversation-\(sessionId)")
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "OScar"

        conversationWindows[sessionId] = window
        bringToFront(window)

        // Remove from tracking when closed; revert to accessory if no windows remain
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.conversationWindows.removeValue(forKey: sessionId)
            }
        }
    }

    private func bringToFront(_ window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKey()
    }

    func openSettings() {
        if let existing = settingsWindow {
            bringToFront(existing)
            return
        }
        guard let state else { return }

        let size = NSSize(width: 660, height: 580)
        // Settings uses a plain titled window (no fullSizeContentView) so
        // the SwiftUI TabView tab bar is not obscured by the title area.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "OScar Settings"
        window.minSize = size
        window.tabbingMode = .disallowed
        // Explicitly set content size — frame.height includes title bar so
        // size-comparison checks are unreliable. Always enforce here.
        window.setContentSize(size)
        window.center()
        window.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(state)
        )

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.settingsWindow = nil }
        }

        settingsWindow = window
        bringToFront(window)
    }

    func openQuickEntry(prefillQuery: String = "") {
        guard let state else { return }

        // Close any existing quick-entry window before creating a new one.
        quickEntryWindow?.close()
        quickEntryWindow = nil

        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 580, height: 100)),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let view = QuickEntryView(prefillQuery: prefillQuery)
            .environmentObject(state)

        // Same as makeWindow: we own this via quickEntryWindow, so prevent double-free.
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .floating
        window.center()
        window.orderFrontRegardless()
        window.makeKey()

        // Escape key closes the window
        quickEntryKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closeQuickEntry()
                return nil // consume the event
            }
            return event
        }

        quickEntryWindow = window
    }

    // MARK: - Private

    private func makeWindow(title: String, size: NSSize, autosaveName: String? = nil) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // We manage lifetime via conversationWindows dict, so ARC owns this window.
        // isReleasedWhenClosed defaults to true, which causes AppKit to call [self release]
        // inside close() — resulting in a double-free when our dict also releases it.
        window.isReleasedWhenClosed = false
        window.title = title
        window.titlebarAppearsTransparent = false
        window.minSize = size

        // Set autosave name so the user's resized frame is remembered across sessions.
        // Then enforce the minimum size in case a stale saved frame is smaller than
        // our default — setFrameAutosaveName restores the saved rect immediately and
        // can override the contentRect set above.
        let name = autosaveName ?? title
        window.setFrameAutosaveName(name)
        if window.frame.width < size.width || window.frame.height < size.height {
            window.setContentSize(size)
        }
        window.center()
        return window
    }
}
