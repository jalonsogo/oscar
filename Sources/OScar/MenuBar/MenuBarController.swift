import AppKit
import SwiftUI

/// Owns the NSStatusItem (menu bar icon + popover) for the lifetime of the app.
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var animationTimer: Timer?
    private var animationFrame = 0

    private weak var windowManager: WindowManager?
    private weak var appState: AppState?

    // MARK: - Icon images (loaded once from bundle; nil when running as bare binary)

    private lazy var staticIcon:   NSImage? = loadIcon("icon")
    private lazy var disabledIcon: NSImage? = loadIcon("icon-disabled")
    private lazy var askIcon:      NSImage? = loadIcon("icon-ask")
    private lazy var animFrames:  [NSImage] = {
        ["icon", "icon-2", "icon-3", "icon-4", "icon-5", "icon-6", "icon-7", "icon-8"]
            .compactMap { loadIcon($0) }
    }()

    private func loadIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "icons"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    private func fallbackIcon() -> NSImage? {
        let img = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "OScar")
        img?.isTemplate = true
        return img
    }

    // MARK: - Setup

    func setup(state: AppState, windowManager: WindowManager) {
        self.windowManager = windowManager
        self.appState = state

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        statusItem.autosaveName = "com.oscarapp.oscar.statusitem"

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateIcon(status: state.serverStatus)

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.animates = true

        let hosting = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(state)
                .task { await state.startIfNeeded() }
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let vc = NSViewController()
        let effectView = NSVisualEffectView()
        effectView.material = .windowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        vc.view = effectView

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hosting.view)
        vc.addChild(hosting)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        popover.contentViewController = vc

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }

        // React to server status changes
        Task { @MainActor in
            for await status in state.$serverStatus.values {
                guard state.streamingSessions.isEmpty else { continue }
                self.updateIcon(status: status)
            }
        }

        // Start / stop animation based on active streaming sessions
        Task { @MainActor in
            for await streaming in state.$streamingSessions.values {
                if streaming.isEmpty {
                    self.stopAnimation()
                } else {
                    self.startAnimation()
                }
            }
        }
    }

    // MARK: - Icon updates

    func updateIcon(status: ServerStatus) {
        guard let button = statusItem?.button else { return }
        let isDisabled: Bool
        if case .launching = status { isDisabled = true } else { isDisabled = false }

        let image = isDisabled
            ? (disabledIcon ?? fallbackIcon())
            : (staticIcon   ?? fallbackIcon())
        button.image = image
        button.title = image == nil ? "OSc" : ""
        button.appearsDisabled = isDisabled
    }

    // MARK: - Animation

    private func startAnimation() {
        guard animationTimer == nil, !animFrames.isEmpty else { return }
        animationFrame = 0
        statusItem?.button?.appearsDisabled = false
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceFrame() }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        if let state = appState {
            updateIcon(status: state.serverStatus)
        }
    }

    @MainActor private func advanceFrame() {
        guard let button = statusItem?.button else { return }
        button.image = animFrames[animationFrame % animFrames.count]
        animationFrame += 1
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    deinit {
        animationTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
