import AppKit
import SwiftUI

/// Owns the NSStatusItem (menu bar icon + popover) for the lifetime of the app.
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    private weak var windowManager: WindowManager?

    func setup(state: AppState, windowManager: WindowManager) {
        self.windowManager = windowManager
        NSLog("[OScar] creating NSStatusItem")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        statusItem.autosaveName = "com.oscarapp.oscar.statusitem"
        NSLog("[OScar] statusItem.button = %@", String(describing: statusItem.button))
        updateIcon(status: state.serverStatus)

        if let button = statusItem.button {
            NSLog("[OScar] configuring button")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            NSLog("[OScar] WARNING: button is nil!")
        }

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.animates = true

        // Use NSVisualEffectView as root so the popover gets the frosted-glass
        // menu material instead of a plain white background.
        let hosting = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(state)
                .task { await state.startIfNeeded() }
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let vc = NSViewController()
        let effectView = NSVisualEffectView()
        effectView.material = .popover
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

        // Update icon whenever server status changes
        Task { @MainActor in
            for await _ in state.$serverStatus.values {
                self.updateIcon(status: state.serverStatus)
            }
        }
    }

    func updateIcon(status: ServerStatus) {
        guard let button = statusItem?.button else { return }

        // Try SF Symbol, fall back to text so the button is always visible
        if let image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "OScar") {
            NSLog("[OScar] SF Symbol loaded OK")
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            NSLog("[OScar] SF Symbol nil — using text fallback")
            button.image = nil
            button.title = "OSc"
        }

        if case .launching = status { button.appearsDisabled = true } else { button.appearsDisabled = false }
    }

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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
