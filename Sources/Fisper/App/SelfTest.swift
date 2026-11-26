import Cocoa

/// `Fisper --selftest file.wav …` — runs the exact dictation pipeline on audio files (no mic / permissions needed).
@MainActor
enum SelfTest {
    static func run(files: [String]) {
        let state = AppState.shared
        let model = Preferences.shared.modelID
        print("Fisper self-test · model \(model)")
        state.whisper.start(modelID: model)
        state.polisher.refreshAvailability()
        Task {
            let t0 = Date()
            while !state.whisper.isReady {
                if case .failed(let msg) = state.whisper.state { print("engine failed: \(msg)"); exit(1) }
                if state.whisper.state == .missingModel { print("model missing"); exit(1) }
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Date().timeIntervalSince(t0) > 120 { print("engine timeout"); exit(1) }
            }
            print(String(format: "engine ready in %.2fs", Date().timeIntervalSince(t0)))
            try? await Task.sleep(nanoseconds: 1_500_000_000) // let Ollama/Apple availability resolve
            let engine = state.polisher.resolvedEngine(state.prefs.polishEngine, ollamaModel: state.prefs.ollamaModel)
            print("AI polish: \(engine.title) · apple=\(state.polisher.appleStatus) · ollama=\(state.polisher.ollamaModels)")
            state.polisher.prewarm(engine, ollamaModel: state.prefs.ollamaModel)
            for f in files {
                guard let samples = AudioUtil.samples(fromWAV: URL(fileURLWithPath: f)) else { print("✗ cannot read \(f)"); continue }
                let a = AudioUtil.analyze(samples)
                let s0 = Date()
                do {
                    let raw = try await state.whisper.transcribe(samples: AudioUtil.prepared(samples), language: state.prefs.language, prompt: "")
                    let s1 = Date()
                    let (final, by) = await state.pipeline(raw: raw, voiced: a.voicedSeconds, bundleID: nil)
                    let s2 = Date()
                    print("\n▶ \((f as NSString).lastPathComponent)  (\(String(format: "%.1f", Double(samples.count) / 16000))s audio, voiced \(String(format: "%.1f", a.voicedSeconds))s)")
                    print("  raw   : \(raw)")
                    print("  final : \(final.replacingOccurrences(of: "\n", with: "⏎"))")
                    print(String(format: "  timing: whisper %.0f ms · cleanup %.0f ms (%@)", s1.timeIntervalSince(s0) * 1000, s2.timeIntervalSince(s1) * 1000, by))
                } catch {
                    print("✗ \(f): \(error.localizedDescription)")
                }
            }
            state.whisper.stop()
            exit(0)
        }
    }
}
