import AppKit
import AppIntents
import CoreSpotlight

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var menuBarController: MenuBarController!
    private var windowManager: WindowManager!
    /// Strong reference — must stay alive so Spotlight keeps showing "Search in Oscar".
    private var searchActivity: NSUserActivity?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Run as menu-bar-only app — no Dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[OScar] applicationDidFinishLaunching")

        // Seed default values so UserDefaults.integer(forKey:) returns them before
        // the user has visited Settings (register(defaults:) never overwrites stored values).
        UserDefaults.standard.register(defaults: [
            "hotkeyKeyCode":   HotkeyManager.defaultKeyCode,
            "hotkeyModifiers": HotkeyManager.defaultModifiers
        ])

        state = AppState()
        state.applyAppearance()
        windowManager = WindowManager()
        menuBarController = MenuBarController()

        windowManager.setup(state: state)
        NSLog("[OScar] calling menuBarController.setup")
        menuBarController.setup(state: state, windowManager: windowManager)
        NSLog("[OScar] setup complete")

        // Register the global hotkey (⌥⌘O by default, configurable in Settings).
        HotkeyManager.shared.registerFromDefaults()

        Task { @MainActor in
            await state.start()
        }

        // Advertise search continuation so "Search in Oscar" appears in Spotlight
        // alongside "Search in Finder" / "Search the Web".
        let activity = NSUserActivity(activityType: CSQueryContinuationActionType)
        activity.isEligibleForSearch = true
        activity.title = "Ask Oscar"
        activity.becomeCurrent()
        searchActivity = activity

        // Tell Siri/Spotlight about the "Ask Oscar" phrase shortcuts.
        OScarShortcuts.updateAppShortcutParameters()
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
        // Tap on a "Search in Oscar" Spotlight result — create a new session
        if userActivity.activityType == CSQueryContinuationActionType,
           let rawQuery = userActivity.userInfo?[CSSearchQueryString] as? String,
           !rawQuery.isEmpty {
            let parsed = parseQueryPrefix(rawQuery)
            var userInfo: [String: String] = ["query": parsed.query]
            if let agent = parsed.effectiveAgentName { userInfo["agentName"] = agent }
            NotificationCenter.default.post(name: .oscOpenWithQuery, object: nil, userInfo: userInfo)
            return true
        }
        // Tap on an indexed session result — open that session
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
