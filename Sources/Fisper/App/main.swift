import Cocoa

// Headless modes (useful for testing without permissions):
//   Fisper --selftest a.wav [b.wav …]      transcribe + clean files and print the results
//   Fisper --render-ui <dir>               render every screen to PNGs
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest") {
    let files = Array(args.dropFirst(i + 1))
    MainActor.assumeIsolated { SelfTest.run(files: files) }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--render-ui"), i + 1 < args.count {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    MainActor.assumeIsolated { SnapshotRenderer.run(outDir: args[i + 1]) }
} else {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
