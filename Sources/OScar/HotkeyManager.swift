import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey using Carbon's RegisterEventHotKey.
/// No Accessibility permission required.
/// When triggered, posts .oscOpenQuickEntry on the main thread.
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// Default: ⌥⌘O — Option+Command+O (keyCode 31, Carbon modifiers 2304)
    static let defaultKeyCode:  Int = 31    // kVK_ANSI_O
    static let defaultModifiers: Int = 2304  // optionKey (0x0800) | cmdKey (0x0100)

    private var hotKeyRef:    EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Reads hotkeyKeyCode / hotkeyModifiers from UserDefaults and registers.
    func registerFromDefaults() {
        let kc   = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let mods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        register(keyCode: UInt32(kc), modifiers: UInt32(mods))
    }

    /// Registers (or re-registers) a new hotkey combination.
    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The callback captures nothing — safe as @convention(c).
        // Carbon delivers hotkey events on the main thread via the RunLoop.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .oscOpenQuickEntry, object: nil)
                }
                return noErr
            },
            1, &spec, nil, &eventHandler
        )

        let hotkeyID = EventHotKeyID(signature: OSType(0x4F534B59), id: 1) // 'OSKY'
        RegisterEventHotKey(keyCode, modifiers, hotkeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef    { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let h   = eventHandler { RemoveEventHandler(h);     eventHandler = nil }
    }
}
