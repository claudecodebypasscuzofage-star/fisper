import Cocoa
import Carbon.HIToolbox

/// A user-recordable keyboard shortcut. Three shapes:
///  • modifier-only, side-specific — e.g. fn, right ⌥, left ⌃ + left ⌥   (deviceMods)
///  • modifier-only, either side   — e.g. ⌃⌥                             (genericMods, keyCode nil)
///  • key combo                    — e.g. ⌃⌥ Space, ⌘⇧ D, F5             (keyCode + genericMods)
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: Int?
    var deviceMods: UInt64 = 0
    var genericMods: UInt64 = 0
    var keyName: String?
    var presetTitle: String?

    // Device-dependent modifier bits (IOLLEvent.h) + the fn flag
    static let lCtrl: UInt64 = 0x01, lShift: UInt64 = 0x02, rShift: UInt64 = 0x04, lCmd: UInt64 = 0x08
    static let rCmd: UInt64 = 0x10, lOpt: UInt64 = 0x20, rOpt: UInt64 = 0x40, rCtrl: UInt64 = 0x2000
    static let fn: UInt64 = 0x800000
    static let deviceMask: UInt64 = 0x207F | fn
    // Device-independent modifier bits
    static let gCtrl: UInt64 = 0x40000, gShift: UInt64 = 0x20000, gOpt: UInt64 = 0x80000, gCmd: UInt64 = 0x100000
    static let genericMask: UInt64 = gCtrl | gShift | gOpt | gCmd

    var isModifierOnly: Bool { keyCode == nil }
    var isFn: Bool { keyCode == nil && deviceMods == Self.fn && genericMods == 0 }

    /// Generic modifiers this shortcut itself uses (so they're allowed to be held when it starts).
    var impliedGeneric: UInt64 {
        var g = genericMods
        if deviceMods & (Self.lCtrl | Self.rCtrl) != 0 { g |= Self.gCtrl }
        if deviceMods & (Self.lShift | Self.rShift) != 0 { g |= Self.gShift }
        if deviceMods & (Self.lOpt | Self.rOpt) != 0 { g |= Self.gOpt }
        if deviceMods & (Self.lCmd | Self.rCmd) != 0 { g |= Self.gCmd }
        return g
    }

    // MARK: Display

    /// Individual key caps, e.g. ["⌃", "⌥", "Space"] or ["right ⌥"].
    var parts: [String] {
        var p: [String] = []
        if deviceMods != 0 {
            if deviceMods & Self.fn != 0 { p.append("fn") }
            if deviceMods & Self.lCtrl != 0 { p.append("⌃") }
            if deviceMods & Self.rCtrl != 0 { p.append("right ⌃") }
            if deviceMods & Self.lOpt != 0 { p.append("⌥") }
            if deviceMods & Self.rOpt != 0 { p.append("right ⌥") }
            if deviceMods & Self.lShift != 0 { p.append("⇧") }
            if deviceMods & Self.rShift != 0 { p.append("right ⇧") }
            if deviceMods & Self.lCmd != 0 { p.append("⌘") }
            if deviceMods & Self.rCmd != 0 { p.append("right ⌘") }
        }
        if genericMods & Self.gCtrl != 0 { p.append("⌃") }
        if genericMods & Self.gOpt != 0 { p.append("⌥") }
        if genericMods & Self.gShift != 0 { p.append("⇧") }
        if genericMods & Self.gCmd != 0 { p.append("⌘") }
        if let keyName { p.append(keyName) }
        return p
    }

    /// Short inline label, e.g. "fn", "right ⌥", "⌃⌥", "⌃⌥ Space".
    var keyLabel: String {
        let p = parts
        if keyCode != nil {
            let mods = p.dropLast().joined()
            return mods.isEmpty ? (keyName ?? "?") : "\(mods) \(keyName ?? "?")"
        }
        if deviceMods == 0 { return p.joined() }
        return p.joined(separator: " + ")
    }

    var title: String { presetTitle ?? keyLabel }

    // MARK: Presets

    static let fnKey = Shortcut(deviceMods: fn, presetTitle: "fn (Globe)")
    static let rightOption = Shortcut(deviceMods: rOpt, presetTitle: "Right ⌥ Option")
    static let rightCommand = Shortcut(deviceMods: rCmd, presetTitle: "Right ⌘ Command")
    static let rightShift = Shortcut(deviceMods: rShift, presetTitle: "Right ⇧ Shift")
    static let rightControl = Shortcut(deviceMods: rCtrl, presetTitle: "Right ⌃ Control")
    static let controlOption = Shortcut(genericMods: gCtrl | gOpt, presetTitle: "⌃ Control + ⌥ Option")
    static let optionCommand = Shortcut(genericMods: gOpt | gCmd, presetTitle: "⌥ Option + ⌘ Command")
    static let presets: [Shortcut] = [fnKey, rightOption, rightCommand, rightShift, rightControl, controlOption, optionCommand]

    static let defaultPasteLast = Shortcut(keyCode: kVK_ANSI_V, genericMods: gCtrl | gCmd, keyName: "V")

    /// Migration from the 1.0/1.1 preset names.
    static func legacy(_ raw: String) -> Shortcut? {
        switch raw {
        case "fn": return fnKey
        case "rightOption": return rightOption
        case "rightCommand": return rightCommand
        case "rightShift": return rightShift
        case "rightControl": return rightControl
        case "controlOption": return controlOption
        case "optionCommand": return optionCommand
        default: return nil
        }
    }

    // MARK: Keys

    static let standaloneKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        kVK_Help, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
        kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadClear, kVK_ANSI_KeypadEquals, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadMultiply,
        kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadDecimal,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    ]

    static func name(forKeyCode code: Int, characters: String?) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "esc",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "Help",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_ANSI_KeypadEnter: "⌤", kVK_ANSI_KeypadClear: "⌧",
        ]
        if let s = special[code] { return s }
        if (kVK_ANSI_Keypad0...kVK_ANSI_Keypad9).contains(code) || [kVK_ANSI_KeypadEquals, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadMultiply,
            kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadDecimal].contains(code) {
            return "Keypad " + (characters ?? "?")
        }
        let c = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return c.isEmpty ? "Key \(code)" : c
    }
}

// MARK: - Recorder

/// Captures the next key combination pressed while Fisper's window is focused.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var live: [String] = []
    @Published var message: String?

    private var monitor: Any?
    private var peak: UInt64 = 0
    private var onCommit: ((Shortcut) -> Void)?
    var allowModifierOnly = true

    func start(onCommit: @escaping (Shortcut) -> Void) {
        stop()
        self.onCommit = onCommit
        isRecording = true
        message = nil
        live = []
        peak = 0
        AppState.shared.hotkeys.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if isRecording { isRecording = false }
        live = []
        AppState.shared.hotkeys.paused = false
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        let raw = UInt64(e.modifierFlags.rawValue)
        switch e.type {
        case .flagsChanged:
            let dev = raw & Shortcut.deviceMask
            if dev != 0 {
                peak |= dev
                live = Shortcut(deviceMods: peak).parts
            } else if peak != 0 {
                if allowModifierOnly {
                    commit(Shortcut(deviceMods: peak))
                } else {
                    message = "Add a key, e.g. ⌃⌘V."
                    peak = 0; live = []
                }
            }
            return nil
        case .keyDown:
            let generic = raw & Shortcut.genericMask
            let code = Int(e.keyCode)
            if code == kVK_Escape && generic == 0 { stop(); return nil }
            if generic == 0 && !Shortcut.standaloneKeys.contains(code) {
                message = "Add ⌃, ⌥ or ⌘ to that key — on its own it would stop you from typing it."
                return nil
            }
            commit(Shortcut(keyCode: code, genericMods: generic,
                            keyName: Shortcut.name(forKeyCode: code, characters: e.charactersIgnoringModifiers)))
            return nil
        default:
            return nil
        }
    }

    private func commit(_ s: Shortcut) {
        let cb = onCommit
        stop()
        cb?(s)
    }
}
