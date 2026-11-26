import Cocoa
import Carbon.HIToolbox

/// Global keyboard listener built on a CGEventTap.
/// Detects hold-to-talk on a modifier key (fn / right ⌥ / right ⌘ / ⌃⌥), Space while held (lock hands-free),
/// Esc (cancel) and ⌃⌘V (paste last transcript). Self-heals if macOS disables the tap.
@MainActor
final class HotkeyManager {
    enum KeyEvent { case pressed, released, spaceWhileHeld, otherKeyWhileHeld, escape, pasteLast }

    /// Return true to swallow the key event.
    var handler: ((KeyEvent) -> Bool)?
    var choice: HotkeyChoice = .fn { didSet { if oldValue != choice { isDown = false } } }
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

    // Device-dependent modifier bits (IOLLEvent.h)
    private static let rightOptionBit: UInt64 = 0x40
    private static let rightCommandBit: UInt64 = 0x10
    private static let rightShiftBit: UInt64 = 0x04
    private static let rightControlBit: UInt64 = 0x2000

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            let down = hotkeyState(flags: flags)
            if down != isDown {
                // only start when the hotkey is pressed on its own (no ⌘/⇧ etc. already held)
                if down && !otherModifiersClear(flags) { return Unmanaged.passUnretained(event) }
                isDown = down
                _ = handler?(down ? .pressed : .released)
            }
        case .keyDown:
            if keycode == Int64(kVK_Escape) {
                if handler?(.escape) == true { swallowedKeyUps.insert(keycode); return nil }
            } else if keycode == Int64(kVK_ANSI_V) && flags.contains(.maskCommand) && flags.contains(.maskControl)
                        && !flags.contains(.maskShift) && !flags.contains(.maskAlternate) {
                if handler?(.pasteLast) == true { swallowedKeyUps.insert(keycode); return nil }
            } else if isDown {
                if keycode == Int64(kVK_Space) {
                    if handler?(.spaceWhileHeld) == true { swallowedKeyUps.insert(keycode); return nil }
                } else {
                    _ = handler?(.otherKeyWhileHeld)
                }
            }
        case .keyUp:
            if swallowedKeyUps.remove(keycode) != nil { return nil }
        default: break
        }
        return Unmanaged.passUnretained(event)
    }

    private func hotkeyState(flags: CGEventFlags) -> Bool {
        switch choice {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return flags.rawValue & Self.rightOptionBit != 0
        case .rightCommand: return flags.rawValue & Self.rightCommandBit != 0
        case .rightShift: return flags.rawValue & Self.rightShiftBit != 0
        case .rightControl: return flags.rawValue & Self.rightControlBit != 0
        case .controlOption: return flags.contains(.maskControl) && flags.contains(.maskAlternate)
        case .optionCommand: return flags.contains(.maskAlternate) && flags.contains(.maskCommand)
        }
    }

    private func otherModifiersClear(_ flags: CGEventFlags) -> Bool {
        var others: CGEventFlags = [.maskShift, .maskCommand, .maskControl, .maskAlternate]
        switch choice {
        case .fn: break
        case .rightOption: others.remove(.maskAlternate)
        case .rightCommand: others.remove(.maskCommand)
        case .rightShift: others.remove(.maskShift)
        case .rightControl: others.remove(.maskControl)
        case .controlOption: others.remove(.maskControl); others.remove(.maskAlternate)
        case .optionCommand: others.remove(.maskAlternate); others.remove(.maskCommand)
        }
        return flags.intersection(others).isEmpty
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { mgr.handle(type: type, event: event) }
}
