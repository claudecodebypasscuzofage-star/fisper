import Cocoa
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
            let tb = NSToolbar(identifier: "FisperMain")
            tb.showsBaselineSeparator = false
            w.toolbar = tb
            w.toolbarStyle = .unified
            w.title = "Fisper"
            w.isMovableByWindowBackground = false
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

    // MARK: Status item + popover

    private var popover: NSPopover?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(.idle)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.isVisible = state.prefs.showMenuBarIcon
        state.prefs.$showMenuBarIcon.sink { [weak self] v in self?.statusItem.isVisible = v }.store(in: &bag)
    }

    @objc private func togglePopover(_ sender: Any?) {
        if let p = popover, p.isShown { p.performClose(nil); return }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        let view = MenuBarPanel(openWindow: { [weak self] page in
            if let page { self?.state.selectedPage = page }
            self?.popover?.performClose(nil)
            self?.showWindow()
        }, quit: { NSApp.terminate(nil) })
            .environmentObject(state).environmentObject(state.prefs)
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        p.contentViewController = host
        popover = p
        if let button = statusItem.button { p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        p.contentViewController?.view.window?.makeKey()
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

    @objc private func openSettings() { state.selectedPage = .general; showWindow() }

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
