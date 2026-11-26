import Cocoa

// Headless modes (useful for testing without permissions):
//   Fisper --selftest a.wav [b.wav …]      transcribe + clean files and print the results
//   Fisper --render-ui <dir>               render every screen to PNGs
let args = CommandLine.arguments
if args.contains("--test-learn") {
    MainActor.assumeIsolated {
        let cases: [(String, String)] = [
            ("let Ria know the docs are ready", "Hey team, let Priya know the docs are ready. Thanks"),   // name fix inside surrounding text
            ("ship it on iphone first", "ship it on iPhone first"),                                    // casing fix
            ("we should meet at the office", "we should meet at an office"),                           // grammar edit → ignore
            ("send it to John", "send it to John and Mary tomorrow"),                                  // user kept typing → ignore
            ("the cubernetes cluster is down", "the Kubernetes cluster is down"),                      // jargon fix
            ("call me later", "call me"),                                                              // deletion → ignore
        ]
        for (a, b) in cases {
            let r = EditLearner.singleCorrection(original: EditLearner.tokens(a), edited: EditLearner.tokens(b))
            print("\(a)  ⟶  \(b)\n    learned: \(r.map { "\($0.0) → \($0.1)" } ?? "nothing")")
        }
    }
    exit(0)
} else if let i = args.firstIndex(of: "--enhance"), i + 2 < args.count {
    // Fisper --enhance in.wav out.wav [off|light|auto|always]
    let mode = NoiseMode(rawValue: i + 3 < args.count ? args[i + 3] : "auto") ?? .auto
    guard let s = AudioUtil.samples(fromWAV: URL(fileURLWithPath: args[i + 1])) else { print("cannot read"); exit(1) }
    let t0 = Date()
    let (out, r) = AudioEnhancer.processWithReport(s, options: .init(noise: mode))
    try? AudioUtil.wavData(out).write(to: URL(fileURLWithPath: args[i + 2]))
    print(String(format: "enhanced %.1fs in %.0f ms · SNR %.1f dB · isolated %@ · gain %+.1f dB", Double(s.count) / 16000, Date().timeIntervalSince(t0) * 1000, r.snrDB, r.isolated ? "yes" : "no", r.gainDB))
    exit(0)
} else if let i = args.firstIndex(of: "--selftest") {
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
