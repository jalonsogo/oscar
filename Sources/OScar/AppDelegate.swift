import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var menuBarController: MenuBarController!
    private var windowManager: WindowManager!

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Run as menu-bar-only app — no Dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[OScar] applicationDidFinishLaunching")
        state = AppState()
        windowManager = WindowManager()
        menuBarController = MenuBarController()

        windowManager.setup(state: state)
        NSLog("[OScar] calling menuBarController.setup")
        menuBarController.setup(state: state, windowManager: windowManager)
        NSLog("[OScar] setup complete")

        Task { @MainActor in
            await state.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app — stay alive when all windows are closed
        return false
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
    ) -> Bool {
        if let sessionID = SpotlightIndexer.sessionID(from: userActivity) {
            NotificationCenter.default.post(
                name: .oscOpenSession,
                object: nil,
                userInfo: ["payload": sessionID]
            )
            return true
        }
        return false
    }
}
