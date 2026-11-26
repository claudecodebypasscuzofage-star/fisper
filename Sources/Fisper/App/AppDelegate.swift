import Cocoa
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let state = AppState.shared
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private var flowBar: FlowBarController?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // single instance
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first {
            other.activate()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        setupStatusItem()
        state.boot()
        flowBar = FlowBarController()

        NotificationCenter.default.addObserver(forName: .fisperOpenWindow, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWindow() }
        }
        state.$phase.sink { [weak self] p in self?.updateStatusIcon(p) }.store(in: &bag)

        // Launched at login → stay quietly in the menu bar. Otherwise open the window.
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
        if !launchedAtLogin || !state.prefs.onboarded { showWindow() } else { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationWillTerminate(_ notification: Notification) { state.shutdown() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Window

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Fisper"
            w.isMovableByWindowBackground = true
            w.minSize = NSSize(width: 860, height: 580)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("FisperMain")
            w.contentView = NSHostingView(rootView: MainView().environmentObject(state).environmentObject(state.prefs))
            if !w.setFrameUsingName("FisperMain") { w.center() }
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        // keep running in the menu bar
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(.idle)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusIcon(_ phase: AppState.Phase) {
        let name: String
        switch phase {
        case .recording: name = "waveform.circle.fill"
        case .processing: name = "ellipsis.circle"
        default: name = "waveform"
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Fisper")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status: String
        switch state.whisper.state {
        case .ready: status = state.accessibilityGranted ? "Ready — hold \(state.prefs.hotkey.keyLabel) to dictate" : "Needs Accessibility permission"
        case .starting: status = "Starting speech engine…"
        case .missingModel: status = "Download a speech model in Settings"
        case .failed(let m): status = m
        case .stopped: status = "Speech engine stopped"
        }
        let head = NSMenuItem(title: status, action: nil, keyEquivalent: ""); head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())
        menu.addItem(item("Open Fisper", #selector(openWindow), "o"))
        let hands = item("Start Hands-free Dictation", #selector(toggleHandsFree), "")
        if case .recording = state.phase { hands.title = "Finish Dictation" }
        menu.addItem(hands)
        let paste = item("Paste Last Transcript", #selector(pasteLast), "v")
        paste.keyEquivalentModifierMask = [.control, .command]
        paste.isEnabled = state.lastTranscript != nil
        menu.addItem(paste)
        menu.addItem(.separator())

        let micMenu = NSMenu()
        let def = NSMenuItem(title: "System Default", action: #selector(selectMic(_:)), keyEquivalent: "")
        def.target = self; def.representedObject = ""; def.state = state.prefs.microphoneUID.isEmpty ? .on : .off
        micMenu.addItem(def)
        for d in AudioDevices.inputDevices() {
            let m = NSMenuItem(title: d.name, action: #selector(selectMic(_:)), keyEquivalent: "")
            m.target = self; m.representedObject = d.uid; m.state = state.prefs.microphoneUID == d.uid ? .on : .off
            micMenu.addItem(m)
        }
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: ""); micItem.submenu = micMenu
        menu.addItem(micItem)

        let keyMenu = NSMenu()
        for h in HotkeyChoice.allCases {
            let m = NSMenuItem(title: h.title, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            m.target = self; m.representedObject = h.rawValue; m.state = state.prefs.hotkey == h ? .on : .off
            keyMenu.addItem(m)
        }
        let keyItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: ""); keyItem.submenu = keyMenu
        menu.addItem(keyItem)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Quit Fisper", #selector(quit), "q"))
    }

    private func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; return i
    }

    @objc private func openWindow() { showWindow() }
    @objc private func openSettings() { state.selectedPage = .settings; showWindow() }
    @objc private func toggleHandsFree() { state.toggleHandsFree() }
    @objc private func pasteLast() {
        guard let t = state.lastTranscript else { return }
        _ = Paster.insert(t.text, restoreClipboard: state.prefs.restoreClipboard)
    }
    @objc private func selectMic(_ sender: NSMenuItem) { state.prefs.microphoneUID = sender.representedObject as? String ?? "" }
    @objc private func selectHotkey(_ sender: NSMenuItem) {
        if let h = HotkeyChoice(rawValue: sender.representedObject as? String ?? "") { state.prefs.hotkey = h }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Main menu (for ⌘Q, ⌘W, copy/paste in text fields)

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Fisper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); s.target = self
        appMenu.addItem(s)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Fisper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Fisper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        NSApp.mainMenu = main
    }
}
