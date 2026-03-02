import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - SwiftUI wrapper

/// A click-to-record hotkey field. Displays the current shortcut as a badge;
/// click to enter recording mode, then press the desired key combo.
struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var keyCode:  Int
    @Binding var modifiers: Int

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let v = HotkeyRecorderNSView()
        v.keyCode   = keyCode
        v.modifiers = modifiers
        v.onChange  = { kc, mods in
            keyCode   = kc
            modifiers = mods
        }
        return v
    }

    func updateNSView(_ v: HotkeyRecorderNSView, context: Context) {
        guard !v.isRecording else { return }
        v.keyCode   = keyCode
        v.modifiers = modifiers
        v.refresh()
    }
}

// MARK: - Underlying NSView

final class HotkeyRecorderNSView: NSView {
    var keyCode:   Int = HotkeyManager.defaultKeyCode
    var modifiers: Int = HotkeyManager.defaultModifiers
    var onChange:  ((Int, Int) -> Void)?
    private(set) var isRecording = false

    private let pill  = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 5
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.leadingAnchor .constraint(equalTo: leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor),
            pill.topAnchor     .constraint(equalTo: topAnchor),
            pill.bottomAnchor  .constraint(equalTo: bottomAnchor),
        ])

        label.font        = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.alignment   = .center
        label.isEditable  = false
        label.isSelectable = false
        label.backgroundColor = .clear
        label.isBordered  = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            label.leadingAnchor .constraint(greaterThanOrEqualTo: pill.leadingAnchor,  constant:  8),
            label.trailingAnchor.constraint(lessThanOrEqualTo:    pill.trailingAnchor, constant: -8),
        ])

        refresh()
    }

    func refresh() {
        if isRecording {
            label.stringValue = "Press shortcut\u{2026}"
            label.textColor   = .controlAccentColor
            pill.layer?.borderWidth     = 1.5
            pill.layer?.borderColor     = NSColor.controlAccentColor.cgColor
            pill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else {
            label.stringValue = shortcutString(keyCode: keyCode, modifiers: modifiers)
            label.textColor   = .labelColor
            pill.layer?.borderWidth     = 1
            pill.layer?.borderColor     = NSColor.separatorColor.cgColor
            pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    // MARK: First-responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isRecording = true
        refresh()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        if isRecording { isRecording = false; refresh() }
        return true
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            window?.makeFirstResponder(nil)   // cancel on second click
        } else {
            window?.makeFirstResponder(self)  // start recording
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Escape cancels without saving
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        // Require at least one modifier
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty else { return }

        let kc    = Int(event.keyCode)
        let cMods = carbonModifiers(from: event.modifierFlags)
        onChange?(kc, cMods)
        window?.makeFirstResponder(nil)
    }

    // MARK: Helpers

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= Int(cmdKey) }
        if flags.contains(.option)  { m |= Int(optionKey) }
        if flags.contains(.control) { m |= Int(controlKey) }
        if flags.contains(.shift)   { m |= Int(shiftKey) }
        return m
    }

    private func shortcutString(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & Int(controlKey) != 0 { s += "⌃" }
        if modifiers & Int(optionKey)  != 0 { s += "⌥" }
        if modifiers & Int(shiftKey)   != 0 { s += "⇧" }
        if modifiers & Int(cmdKey)     != 0 { s += "⌘" }
        s += keyLabel(keyCode)
        return s
    }

    // swiftlint:disable cyclomatic_complexity
    private func keyLabel(_ keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:  return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab:    return "Tab"
        case kVK_F1:     return "F1"
        case kVK_F2:     return "F2"
        case kVK_F3:     return "F3"
        case kVK_F4:     return "F4"
        case kVK_F5:     return "F5"
        case kVK_F6:     return "F6"
        case kVK_F7:     return "F7"
        case kVK_F8:     return "F8"
        case kVK_F9:     return "F9"
        case kVK_F10:    return "F10"
        case kVK_F11:    return "F11"
        case kVK_F12:    return "F12"
        default:         return "?"
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
