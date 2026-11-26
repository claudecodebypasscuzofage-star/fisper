import Cocoa
import Combine
import AVFoundation

/// The dictation brain: hotkey → record → (stream) transcribe with Whisper → clean (rules + local AI) → insert.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable {
        case idle
        case recording(handsFree: Bool)
        case processing
        case notice(String, isError: Bool)
    }

    let prefs = Preferences.shared
    let whisper = WhisperServer()
    let polisher = AIPolisher()
    let models = ModelManager()
    let history = JSONStore<Transcript>(url: Paths.history)
    let dictionary = JSONStore<DictEntry>(url: Paths.dictionary, defaultItems: [
        DictEntry(word: "Fisper"), DictEntry(word: "Mac OS", replacement: "macOS"), DictEntry(word: "ChatGPT"),
    ])
    let snippets = JSONStore<Snippet>(url: Paths.snippets, defaultItems: [
        Snippet(trigger: "my signature", expansion: "Best,\n\(Demo.firstName)"),
    ])
    private let recorder = AudioRecorder()
    let hotkeys = HotkeyManager()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 28)
    @Published private(set) var accessibilityGranted = Permissions.accessibility
    @Published private(set) var micStatus = Permissions.microphone
    @Published private(set) var hotkeyActive = false
    @Published private(set) var lastAudioReport: AudioEnhancer.Report?
    @Published private(set) var diagnosticResult: String?
    @Published var selectedPage: Page = .home
    @Published var testFieldText = ""

    enum Page: String, CaseIterable, Identifiable {
        case home, insights, dictionary, snippets, style
        case general, dictation, audio, writing, appearance, privacy, advanced
        var id: String { rawValue }
        var isSettings: Bool { [.general, .dictation, .audio, .writing, .appearance, .privacy, .advanced].contains(self) }
    }

    private var pressTime = Date()
    private var pendingTapCancel: DispatchWorkItem?
    private var noticeWork: DispatchWorkItem?
    private var maxDurationWork: DispatchWorkItem?
    private var targetApp: NSRunningApplication?
    private var mutedOutput = false
    private var processingID = UUID()
    private var cancelledJobs = Set<UUID>()
    private var bag = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    // streaming
    private var streamTimer: Timer?
    private var streamCommitted = 0               // samples already sent to Whisper
    private var streamChunks: [Task<String, Never>] = []
    private var streamSession = UUID()

    var lastTranscript: Transcript? { history.items.first { !$0.text.isEmpty } }

    // MARK: Lifecycle

    func boot() {
        Log.trim()
        Log.info("Fisper boot. model=\(prefs.modelID) hotkey=\(prefs.hotkey.rawValue) ax=\(accessibilityGranted) mic=\(micStatus.rawValue)")
        hotkeys.choice = prefs.hotkey
        hotkeys.handler = { [weak self] ev in self?.handle(ev) ?? false }
        hotkeys.start()
        hotkeyActive = hotkeys.isInstalled

        recorder.onLevel = { [weak self] l in self?.pushLevel(l) }
        recorder.onInterrupted = { [weak self] in
            guard let self, case .recording = self.phase else { return }
            self.stopAndTranscribe(reason: "device change")
        }
        models.onFinished = { [weak self] id in
            guard let self else { return }
            if id == self.prefs.modelID || !WhisperModelInfo.info(for: self.prefs.modelID).isDownloaded {
                self.prefs.modelID = id
                self.whisper.start(modelID: id)
            }
        }

        prefs.$hotkey.dropFirst().sink { [weak self] h in self?.hotkeys.choice = h }.store(in: &bag)
        prefs.$modelID.dropFirst().removeDuplicates().sink { [weak self] id in self?.whisper.start(modelID: id) }.store(in: &bag)
        prefs.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.syncPolisherConfig() } }.store(in: &bag)
        whisper.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        polisher.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        history.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)

        syncPolisherConfig()
        whisper.start(modelID: prefs.modelID)
        polisher.refreshAvailability()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.polisher.prewarm(self.activeEngine, ollamaModel: self.prefs.ollamaModel)
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        applyRetention()
        pruneAudio()
    }

    func shutdown() {
        if mutedOutput { AudioDevices.setOutputMuted(false) }
        history.flush(); dictionary.flush(); snippets.flush()
        whisper.stop()
    }

    var activeEngine: PolishEngine { polisher.resolvedEngine(prefs.polishEngine, ollamaModel: prefs.ollamaModel) }

    private func syncPolisherConfig() {
        let c = AIPolisher.Config(level: prefs.correctionLevel, lists: prefs.formatLists, digits: prefs.numbersAsDigits, custom: prefs.customInstructions)
        if polisher.config != c { polisher.config = c }
    }

    func refreshPermissions() {
        let ax = Permissions.accessibility
        if ax != accessibilityGranted {
            accessibilityGranted = ax
            Log.info("permission: accessibility \(ax ? "granted" : "revoked")")
            if ax { hotkeys.reinstall() }
        }
        let mic = Permissions.microphone
        if mic != micStatus { micStatus = mic; Log.info("permission: microphone status \(mic.rawValue)") }
        if hotkeyActive != hotkeys.isInstalled { hotkeyActive = hotkeys.isInstalled }
    }

    // MARK: Hotkey state machine

    private func isExcludedFrontApp() -> Bool {
        guard let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return prefs.excludedApps.contains(b)
    }

    private func handle(_ ev: HotkeyManager.KeyEvent) -> Bool {
        switch ev {
        case .pressed:
            switch phase {
            case .recording(let handsFree):
                if handsFree {
                    stopAndTranscribe(reason: "hotkey (hands-free)")
                } else if let pending = pendingTapCancel {
                    pending.cancel(); pendingTapCancel = nil
                    phase = .recording(handsFree: true)
                    Sounds.play("lock")
                }
            default:
                if isExcludedFrontApp() { return false }
                startRecording(handsFree: false)
            }
            return false
        case .released:
            guard case .recording(let handsFree) = phase, !handsFree else { return false }
            let held = Date().timeIntervalSince(pressTime)
            if held < prefs.minHoldSeconds {
                if prefs.doubleTapHandsFree {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.pendingTapCancel = nil
                        if case .recording(false) = self.phase { self.cancel(silent: true) }
                    }
                    pendingTapCancel = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
                } else {
                    cancel(silent: true)
                }
            } else {
                stopAndTranscribe(reason: "released")
            }
            return false
        case .spaceWhileHeld:
            if prefs.spaceLocksHandsFree, case .recording(false) = phase {
                phase = .recording(handsFree: true)
                Sounds.play("lock")
                return true
            }
            return false
        case .otherKeyWhileHeld:
            if case .recording(false) = phase, Date().timeIntervalSince(pressTime) < 1.0 { cancel(silent: true) }
            return false
        case .escape:
            switch phase {
            case .recording: cancel(silent: false); return true
            case .processing: cancelledJobs.insert(processingID); phase = .idle; Sounds.play("cancel"); return true
            default: return false
            }
        case .pasteLast:
            guard let t = lastTranscript else { return false }
            insert(t.text)
            return true
        }
    }

    // MARK: Recording

    func toggleHandsFree() {
        switch phase {
        case .recording: stopAndTranscribe(reason: "button")
        default: startRecording(handsFree: true)
        }
    }

    func startRecording(handsFree: Bool) {
        if case .recording = phase { return }
        pendingTapCancel?.cancel(); pendingTapCancel = nil

        switch Permissions.microphone {
        case .notDetermined:
            Permissions.requestMicrophone { [weak self] _ in MainActor.assumeIsolated { self?.refreshPermissions() } }
            showNotice("Allow microphone access, then try again", isError: true)
            return
        case .denied, .restricted:
            showNotice("Microphone access is off — enable it in Settings", isError: true)
            return
        default: break
        }
        if !WhisperModelInfo.info(for: prefs.modelID).isDownloaded {
            showNotice("Download a speech model in Settings", isError: true)
            selectedPage = .dictation
            NotificationCenter.default.post(name: .fisperOpenWindow, object: nil)
            return
        }
        if case .failed = whisper.state { whisper.start(modelID: prefs.modelID) }
        if whisper.state == .stopped { whisper.start(modelID: prefs.modelID) }

        targetApp = NSWorkspace.shared.frontmostApplication
        FocusInspector.enableAccessibility(for: targetApp)
        do {
            try recorder.start(deviceUID: prefs.microphoneUID)
        } catch {
            Log.info("record start failed: \(error.localizedDescription)")
            showNotice("Couldn't start the microphone", isError: true)
            return
        }
        pressTime = Date()
        polisher.ensureWarm(activeEngine, ollamaModel: prefs.ollamaModel)
        levels = Array(repeating: 0, count: levels.count)
        phase = .recording(handsFree: handsFree)
        Sounds.play("start")
        startStreaming()
        if prefs.muteWhileDictating, AudioDevices.isOutputMuted() == false {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, case .recording = self.phase else { return }
                AudioDevices.setOutputMuted(true); self.mutedOutput = true
            }
        }
        maxDurationWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.stopAndTranscribe(reason: "max duration") }
        maxDurationWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + prefs.maxRecordingMinutes * 60, execute: w)
    }

    func cancel(silent: Bool) {
        maxDurationWork?.cancel()
        stopStreaming(discard: true)
        _ = recorder.stop()
        restoreOutput()
        phase = .idle
        if !silent { Sounds.play("cancel") }
    }

    private func restoreOutput() {
        if mutedOutput { AudioDevices.setOutputMuted(false); mutedOutput = false }
    }

    func stopAndTranscribe(reason: String) {
        guard case .recording = phase else { return }
        maxDurationWork?.cancel()
        let releasedAt = Date()
        phase = .processing
        // keep capturing a moment longer so the last syllable isn't clipped
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let committed = self.streamCommitted
            let chunks = self.streamChunks
            self.stopStreaming(discard: false)
            let samples = self.recorder.stop()
            self.restoreOutput()
            Sounds.play("stop")
            let target = self.targetApp
            let id = UUID(); self.processingID = id
            Task { await self.process(samples: samples, streamedUpTo: committed, chunks: chunks, target: target, releasedAt: releasedAt, jobID: id) }
        }
    }

    // MARK: Streaming (transcribe long dictations while you talk)

    /// Every second, if ≥ 12 s of untranscribed audio has piled up and there's a pause, send it to Whisper now.
    /// At release only the last few seconds remain, so long dictations finish as fast as short ones.
    private func startStreaming() {
        streamCommitted = 0
        streamChunks = []
        streamSession = UUID()
        guard prefs.streaming else { return }
        let session = streamSession
        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.streamTick(session) }
        }
    }

    private func streamTick(_ session: UUID) {
        guard session == streamSession, case .recording = phase else { return }
        let total = recorder.sampleCount
        let pending = total - streamCommitted
        guard pending > Int(12 * AudioRecorder.sampleRate) else { return }
        let window = recorder.copySamples(streamCommitted..<total)
        // cut at a natural pause; if the speaker never pauses, force a cut at 25 s
        var cut = AudioUtil.quietSplitPoint(window)
        if cut == nil && pending > Int(25 * AudioRecorder.sampleRate) { cut = window.count - Int(0.5 * AudioRecorder.sampleRate) }
        guard let c = cut, c > Int(4 * AudioRecorder.sampleRate) else { return }
        let chunk = Array(window[0..<c])
        streamCommitted += c
        let previous = streamChunks.last
        let opts = prefs.enhancerOptions
        let language = prefs.language
        let fast = prefs.fastMode
        let basePrompt = whisperPrompt()
        Log.info(String(format: "stream: chunk %.1fs", Double(c) / AudioRecorder.sampleRate))
        let task = Task { @MainActor [weak self] () -> String in
            guard let self else { return "" }
            let prevText = await previous?.value ?? ""
            let cleaned = await Task.detached { AudioEnhancer.process(chunk, options: opts) }.value
            let prompt = (basePrompt + " " + String(prevText.suffix(200))).trimmingCharacters(in: .whitespaces)
            return (try? await self.whisper.transcribe(samples: AudioUtil.prepared(cleaned), language: language, prompt: prompt, fast: fast)) ?? ""
        }
        streamChunks.append(task)
    }

    private func stopStreaming(discard: Bool) {
        streamTimer?.invalidate(); streamTimer = nil
        if discard { streamSession = UUID(); streamChunks.forEach { $0.cancel() }; streamChunks = []; streamCommitted = 0 }
    }

    // MARK: Processing

    private func process(samples: [Float], streamedUpTo: Int, chunks: [Task<String, Never>], target: NSRunningApplication?,
                         releasedAt: Date, jobID: UUID) async {
        let duration = Double(samples.count) / AudioRecorder.sampleRate
        let audioName = prefs.keepAudio ? saveAudio(samples) : nil

        // only the part that wasn't streamed yet still needs work
        let tail = streamedUpTo > 0 ? Array(samples[min(streamedUpTo, samples.count)...]) : samples
        let opts = prefs.enhancerOptions
        let (enhanced, report) = await Task.detached { AudioEnhancer.processWithReport(tail, options: opts) }.value
        lastAudioReport = report
        // speech detection runs on the raw audio: the volume boost would make room noise look like speech
        let rawAnalysis = AudioUtil.analyze(tail)
        var analysis = AudioUtil.analyze(enhanced)
        analysis.voicedSeconds = min(analysis.voicedSeconds, max(rawAnalysis.voicedSeconds, 0) + 0.5)
        analysis.peakRMS = rawAnalysis.peakRMS
        Log.info(String(format: "audio: %.2fs (tail %.2fs), voiced %.2fs, snr %.1f dB, isolated %@, gain %+.1f dB, enhance %d ms",
                        duration, Double(tail.count) / AudioRecorder.sampleRate, analysis.voicedSeconds, report.snrDB,
                        report.isolated ? "yes" : "no", report.gainDB, report.ms))

        var parts: [String] = []
        for c in chunks { parts.append(await c.value) }
        let streamedText = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        let tailHasSpeech = analysis.voicedSeconds >= 0.2 && analysis.peakRMS > 0.004
        if streamedText.isEmpty && !tailHasSpeech {
            finish(jobID) { self.showNotice("We couldn't hear you", isError: true) }
            return
        }

        var raw = streamedText
        if tailHasSpeech {
            do {
                if whisper.state == .starting {
                    for _ in 0..<150 where whisper.state == .starting { try? await Task.sleep(nanoseconds: 100_000_000) }
                }
                let prompt = (whisperPrompt() + " " + String(streamedText.suffix(200))).trimmingCharacters(in: .whitespaces)
                let t = try await whisper.transcribe(samples: AudioUtil.prepared(enhanced), language: prefs.language, prompt: prompt, fast: prefs.fastMode)
                let cleanedTail = TextCleaner.isLikelyHallucination(t, voicedSeconds: analysis.voicedSeconds) && !streamedText.isEmpty ? "" : t
                raw = [streamedText, cleanedTail].filter { !$0.isEmpty }.joined(separator: " ")
            } catch {
                Log.info("transcription failed: \(error.localizedDescription)")
                if streamedText.isEmpty {
                    let entry = Transcript(text: "", raw: "", appName: target?.localizedName, bundleID: target?.bundleIdentifier,
                                           duration: duration, audioFile: audioName, polishedBy: "failed")
                    history.items.insert(entry, at: 0)
                    finish(jobID) { self.showNotice("Transcription failed — retry from History", isError: true) }
                    return
                }
            }
        }

        let voiced = max(analysis.voicedSeconds, streamedUpTo > 0 ? Double(streamedUpTo) / AudioRecorder.sampleRate * 0.7 : 0)
        let (text, by) = await pipeline(raw: raw, voiced: voiced, bundleID: target?.bundleIdentifier)
        guard !cancelledJobs.contains(jobID) else { return }
        if text.isEmpty {
            finish(jobID) { self.showNotice("We couldn't hear you", isError: true) }
            return
        }

        var final = text
        if prefs.smartSpacing { final = TextCleaner.adaptToContext(final, before: FocusInspector.textBeforeCursor()) }
        if prefs.addTrailingSpace, !final.hasSuffix("\n") { final += " " }

        let result = insert(final)
        let latency = Int(Date().timeIntervalSince(releasedAt) * 1000)
        Log.info("dictation: \(text.count) chars, \(latency) ms, by \(by), streamed \(chunks.count) chunks, app=\(target?.bundleIdentifier ?? "-")")

        if prefs.retention != .never {
            let entry = Transcript(text: text, raw: raw, appName: target?.localizedName, bundleID: target?.bundleIdentifier,
                                   duration: max(voiced, min(duration, voiced * 1.6)),
                                   latencyMs: latency, audioFile: audioName, polishedBy: by)
            history.items.insert(entry, at: 0)
            if history.items.count > 5000 { history.items.removeLast(history.items.count - 5000) }
        }

        finish(jobID) {
            switch result {
            case .copiedOnly where self.prefs.pasteMethod == .clipboard: self.showNotice("Copied to clipboard", isError: false)
            case .copiedOnly: self.showNotice("Copied — grant Accessibility so Fisper can paste", isError: true)
            case .pasted: self.phase = .idle
            }
        }
    }

    @discardableResult
    private func insert(_ text: String) -> Paster.Result {
        switch prefs.pasteMethod {
        case .clipboard:
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            return .copiedOnly
        case .type:
            guard Permissions.accessibility else { return Paster.insert(text, restoreClipboard: false) }
            Paster.type(text)
        case .paste:
            let r = Paster.insert(text, restoreClipboard: prefs.restoreClipboard)
            if r == .copiedOnly { return r }
        }
        if prefs.pressReturnAfter { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Paster.pressReturn() } }
        return .pasted
    }

    private func finish(_ jobID: UUID, _ block: () -> Void) {
        if case .recording = phase { return }
        guard processingID == jobID, !cancelledJobs.contains(jobID) else { return }
        block()
    }

    /// raw Whisper text → final text. Shared by live dictation, retry and self-test.
    func pipeline(raw: String, voiced: Double, bundleID: String?) async -> (String, String) {
        var t = TextCleaner.stripNoise(raw)
        if TextCleaner.isLikelyHallucination(t, voicedSeconds: voiced) { return ("", "Rules") }
        if let snip = TextCleaner.exactSnippet(t, snippets: snippets.items) { return (snip, "Snippet") }

        t = TextCleaner.applyDictionary(t, entries: dictionary.items)
        var out = TextCleaner.clean(t, removeFillers: prefs.removeFillers, voiceCommands: prefs.voiceCommands)
        var by = "Rules"

        let engine = activeEngine
        if engine != .off, let polished = await polisher.polish(out, engine: engine, ollamaModel: prefs.ollamaModel) {
            out = polished
            by = engine == .apple ? "Apple Intelligence" : "Ollama"
        }

        out = TextCleaner.fixSpacing(out)
        out = TextCleaner.applyDictionary(out, entries: dictionary.items)
        out = TextCleaner.applyStyle(out, prefs.style(for: AppCategory.of(bundleID: bundleID)))
        out = TextCleaner.expandSnippets(out, snippets: snippets.items)
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), by)
    }

    func whisperPrompt() -> String {
        let terms = dictionary.items.map(\.vocabularyTerm).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return Array(terms.prefix(40)).joined(separator: ", ") + "."
    }

    // MARK: Diagnostics

    /// Speaks a test sentence with the system voice, then runs it through the whole pipeline.
    func runDiagnostics() {
        diagnosticResult = "Running…"
        Task {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fisper-diag.aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "Um, so I think we should meet on Tuesday, no wait, Wednesday at three."]
            try? say.run(); say.waitUntilExit()
            guard let samples = AudioUtil.samples(fromWAV: url) else { diagnosticResult = "Couldn't generate test audio"; return }
            let t0 = Date()
            let opts = prefs.enhancerOptions
            let (enh, rep) = await Task.detached { AudioEnhancer.processWithReport(samples, options: opts) }.value
            do {
                let raw = try await whisper.transcribe(samples: AudioUtil.prepared(enh), language: prefs.language, prompt: whisperPrompt(), fast: prefs.fastMode)
                let t1 = Date()
                let (final, by) = await pipeline(raw: raw, voiced: 3, bundleID: nil)
                let t2 = Date()
                diagnosticResult = """
                Heard: \(raw)
                Wrote: \(final)
                Speech \(Int(t1.timeIntervalSince(t0) * 1000)) ms · clean-up \(Int(t2.timeIntervalSince(t1) * 1000)) ms (\(by)) · audio prep \(rep.ms) ms
                """
            } catch {
                diagnosticResult = "Speech engine error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Notices & levels

    func showNotice(_ text: String, isError: Bool) {
        noticeWork?.cancel()
        phase = .notice(text, isError: isError)
        if isError { Sounds.play("cancel") }
        let w = DispatchWorkItem { [weak self] in
            guard let self, case .notice = self.phase else { return }
            self.phase = .idle
        }
        noticeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: w)
    }

    private func pushLevel(_ l: Float) {
        guard case .recording = phase else { return }
        var lv = levels
        lv.removeFirst()
        lv.append(l)
        levels = lv
    }

    // MARK: History actions

    func retry(_ entry: Transcript) {
        guard let name = entry.audioFile, let samples = AudioUtil.samples(fromWAV: Paths.audio.appendingPathComponent(name)) else {
            showNotice("No audio saved for this one", isError: true); return
        }
        Task {
            let opts = prefs.enhancerOptions
            let enhanced = await Task.detached { AudioEnhancer.process(samples, options: opts) }.value
            let analysis = AudioUtil.analyze(enhanced)
            guard let raw = try? await whisper.transcribe(samples: AudioUtil.prepared(enhanced), language: prefs.language,
                                                          prompt: whisperPrompt(), fast: false) else {
                showNotice("Retry failed", isError: true); return
            }
            let (text, by) = await pipeline(raw: raw, voiced: analysis.voicedSeconds, bundleID: entry.bundleID)
            if let i = history.items.firstIndex(where: { $0.id == entry.id }) {
                history.items[i].text = text; history.items[i].raw = raw; history.items[i].polishedBy = by
                if history.items[i].duration < 0.5 { history.items[i].duration = analysis.voicedSeconds }
            }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            showNotice("Re-transcribed and copied", isError: false)
        }
    }

    func delete(_ entry: Transcript) {
        if let f = entry.audioFile { try? FileManager.default.removeItem(at: Paths.audio.appendingPathComponent(f)) }
        history.items.removeAll { $0.id == entry.id }
    }

    func copy(_ entry: Transcript) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    func clearHistory() {
        for e in history.items { if let f = e.audioFile { try? FileManager.default.removeItem(at: Paths.audio.appendingPathComponent(f)) } }
        history.items.removeAll()
    }

    func applyRetention() {
        switch prefs.retention {
        case .forever: return
        case .never: if !history.items.isEmpty { clearHistory() }
        default:
            let cutoff = Date().addingTimeInterval(-Double(prefs.retention.rawValue) * 86_400)
            let old = history.items.filter { $0.date < cutoff }
            for e in old { delete(e) }
        }
    }

    private func saveAudio(_ samples: [Float]) -> String? {
        let name = "\(Int(Date().timeIntervalSince1970 * 1000)).wav"
        do { try AudioUtil.wavData(samples).write(to: Paths.audio.appendingPathComponent(name)); return name } catch { return nil }
    }

    private func pruneAudio() {
        let keep = Set(history.items.prefix(50).compactMap(\.audioFile))
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: Paths.audio.path) else { return }
        for f in files where !keep.contains(f) { try? FileManager.default.removeItem(at: Paths.audio.appendingPathComponent(f)) }
        for i in history.items.indices.dropFirst(50) where history.items[i].audioFile != nil { history.items[i].audioFile = nil }
    }

    // MARK: Stats

    struct Stats {
        var totalWords = 0
        var wpm = 0
        var streak = 0
        var longestStreak = 0
        var todayWords = 0
        var dictations = 0
        var minutesSaved = 0
        var perDay: [Date: Int] = [:]
        var perCategory: [AppCategory: Int] = [:]
    }

    var stats: Stats {
        var s = Stats()
        let cal = Calendar.current
        var speechSeconds = 0.0
        var wpmWords = 0
        for t in history.items where !t.text.isEmpty {
            let w = t.words
            s.totalWords += w
            s.dictations += 1
            let day = cal.startOfDay(for: t.date)
            s.perDay[day, default: 0] += w
            s.perCategory[AppCategory.of(bundleID: t.bundleID), default: 0] += w
            if t.duration > 0.8 && w >= 3 { speechSeconds += t.duration; wpmWords += w }
        }
        s.wpm = speechSeconds > 5 ? Int(Double(wpmWords) / (speechSeconds / 60)) : 0
        s.todayWords = s.perDay[cal.startOfDay(for: Date())] ?? 0
        s.minutesSaved = max(0, Int(Double(s.totalWords) / 40.0 - speechSeconds / 60))
        let days = Set(s.perDay.keys)
        var d = cal.startOfDay(for: Date())
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        while days.contains(d) { s.streak += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        var longest = 0, run = 0, prev: Date?
        for day in days.sorted() {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == day { run += 1 } else { run = 1 }
            longest = max(longest, run); prev = day
        }
        s.longestStreak = longest
        return s
    }
}

extension Notification.Name {
    static let fisperOpenWindow = Notification.Name("fisperOpenWindow")
}
