import Cocoa
import Carbon.HIToolbox

/// Global keyboard listener built on a CGEventTap.
/// Hold-to-talk on any user-recorded shortcut (modifier-only or key combo), Space while held (lock hands-free),
/// Esc (cancel), a paste-last shortcut and an optional hands-free toggle shortcut. Self-heals if macOS disables the tap.
@MainActor
final class HotkeyManager {
    enum KeyEvent { case pressed, released, spaceWhileHeld, otherKeyWhileHeld, escape, pasteLast, toggle }

    /// Return true to swallow the key event.
    var handler: ((KeyEvent) -> Bool)?
    var shortcut: Shortcut = .fnKey { didSet { if oldValue != shortcut { isDown = false } } }
    var pasteLastShortcut: Shortcut? = .defaultPasteLast
    var toggleShortcut: Shortcut?
    /// While the user records a new shortcut, the tap stays out of the way.
    var paused = false
    private(set) var isDown = false
    private(set) var isInstalled = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?
    private var swallowedKeyUps = Set<Int64>()
    nonisolated static let syntheticMarker: Int64 = 0x46495350  // "FISP" – marks events we post ourselves

    func start() {
        install()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
    }

    private func checkHealth() {
        if tap == nil { install(); return }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            Log.info("hotkey: tap was disabled — re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func install() {
        guard tap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: hotkeyTapCallback, userInfo: refcon) else {
            if isInstalled { Log.info("hotkey: tap lost") }
            isInstalled = false
            return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        isInstalled = true
        Log.info("hotkey: event tap installed")
    }

    func reinstall() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil; source = nil; isInstalled = false
        install()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if paused || event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        let raw = event.flags.rawValue
        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let generic = raw & Shortcut.genericMask
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch type {
        case .flagsChanged:
            guard shortcut.isModifierOnly else { break }
            let down = modifierShortcutHeld(raw)
            if down != isDown {
                // only start when the shortcut is pressed on its own (no other modifiers already held)
                if down && (generic & ~shortcut.impliedGeneric) != 0 { return Unmanaged.passUnretained(event) }
                isDown = down
                _ = handler?(down ? .pressed : .released)
            }
        case .keyDown:
            if matches(pasteLastShortcut, keycode, generic) {
                if isRepeat || handler?(.pasteLast) == true { swallowedKeyUps.insert(Int64(keycode)); return nil }
            }
            if matches(toggleShortcut, keycode, generic) {
                if !isRepeat { _ = handler?(.toggle) }
                swallowedKeyUps.insert(Int64(keycode)); return nil
            }
            if !shortcut.isModifierOnly && matches(shortcut, keycode, generic) {
                if !isDown && !isRepeat { isDown = true; _ = handler?(.pressed) }
                swallowedKeyUps.insert(Int64(keycode)); return nil
            }
            if keycode == kVK_Escape {
                if handler?(.escape) == true { swallowedKeyUps.insert(Int64(keycode)); return nil }
            } else if isDown {
                if keycode == kVK_Space && shortcut.keyCode != kVK_Space {
                    if handler?(.spaceWhileHeld) == true { swallowedKeyUps.insert(Int64(keycode)); return nil }
                } else {
                    _ = handler?(.otherKeyWhileHeld)
                }
            }
        case .keyUp:
            if !shortcut.isModifierOnly && keycode == shortcut.keyCode && isDown {
                isDown = false
                _ = handler?(.released)
                swallowedKeyUps.remove(Int64(keycode))
                return nil
            }
            if swallowedKeyUps.remove(Int64(keycode)) != nil { return nil }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }

    private func modifierShortcutHeld(_ raw: UInt64) -> Bool {
        if shortcut.deviceMods != 0 { return raw & shortcut.deviceMods == shortcut.deviceMods }
        return shortcut.genericMods != 0 && raw & shortcut.genericMods == shortcut.genericMods
    }

    /// Key combos match on the exact set of ⌃⌥⇧⌘ (fn and Caps Lock are ignored — F-keys carry fn on laptops).
    private func matches(_ s: Shortcut?, _ keycode: Int, _ generic: UInt64) -> Bool {
        guard let s, let k = s.keyCode, k == keycode else { return false }
        return generic == s.genericMods
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { mgr.handle(type: type, event: event) }
}
