import Cocoa
import SwiftUI

/// `Fisper --render-ui <dir>` — renders each screen to a PNG (with sample data) for docs and visual checks.
@MainActor
enum SnapshotRenderer {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let state = AppState.shared
        let prefs = state.prefs
        let demo = ProcessInfo.processInfo.environment["FISPER_DEMO"] == "1"
        if demo { seedDemo(state) }
        let wasOnboarded = prefs.onboarded
        prefs.onboarded = true

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            let suffix = appearance == .aqua ? "" : "-dark"
            for page in AppState.Page.allCases {
                state.selectedPage = page
                render(MainView().environmentObject(state).environmentObject(prefs), size: NSSize(width: 1040, height: 720),
                       to: dir.appendingPathComponent("\(page.rawValue)\(suffix).png"), appearance: appearance)
            }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        prefs.onboarded = false
        render(MainView().environmentObject(state).environmentObject(prefs), size: NSSize(width: 1040, height: 720),
               to: dir.appendingPathComponent("onboarding.png"), appearance: .aqua)
        prefs.onboarded = true

        // flow bar states
        let bars: [(String, AnyView)] = [
            ("bar-idle", AnyView(IdlePill(hovering: false, keyLabel: "fn"))),
            ("bar-hover", AnyView(IdlePill(hovering: true, keyLabel: "fn"))),
            ("bar-recording", AnyView(RecordingPill(levels: (0..<28).map { i in Float(0.35 + 0.6 * abs(sin(Double(i) * 0.7))) }, handsFree: false, onCancel: {}, onDone: {}))),
            ("bar-handsfree", AnyView(RecordingPill(levels: (0..<28).map { i in Float(0.3 + 0.6 * abs(cos(Double(i) * 0.5))) }, handsFree: true, onCancel: {}, onDone: {}))),
            ("bar-processing", AnyView(ProcessingPill())),
            ("bar-notice", AnyView(NoticePill(message: "We couldn't hear you", isError: true))),
        ]
        for (name, v) in bars {
            render(ZStack { Color(hex: 0xD9D6CE); v }.frame(width: 300, height: 70), size: NSSize(width: 300, height: 70),
                   to: dir.appendingPathComponent("\(name).png"), appearance: .aqua)
        }
        prefs.onboarded = wasOnboarded
        print("rendered to \(dir.path)")
        exit(0)
    }

    private static func render<V: View>(_ view: V, size: NSSize, to url: URL, appearance: NSAppearance.Name) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: appearance)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    private static func seedDemo(_ state: AppState) {
        let now = Date()
        let samples: [(Double, String, String, String)] = [
            (-300, "Can you let the team know the launch is slipping to Monday? We're still waiting on legal to sign off on the new terms page.", "Slack", "com.tinyspeck.slackmacgap"),
            (-1900, "hey are you free for lunch tomorrow? let's do 12 if that works for you", "Messages", "com.apple.MobileSMS"),
            (-5200, "Refactor the audio recorder so it reuses the converter, and add a unit test for the silence trimming.", "Cursor", "com.todesktop.230313mzl4w4u92"),
            (-90_000, "Hi Marcus,\n\nThanks for the quick turnaround. I've attached the revised deck — let me know if anything looks off.", "Mail", "com.apple.mail"),
            (-91_000, "For the trip we need:\n- Sunscreen\n- Towels\n- Snacks", "Notes", "com.apple.Notes"),
            (-180_000, "Summarize this article in three bullet points and suggest a title.", "ChatGPT", "com.openai.chat"),
        ]
        for (dt, text, app, bundle) in samples {
            var t = Transcript(text: text, raw: "demo", appName: app, bundleID: bundle, duration: Double(text.split(separator: " ").count) / 2.6)
            t.date = now.addingTimeInterval(dt)
            t.polishedBy = "Apple Intelligence"
            state.history.items.append(t)
        }
    }
}
