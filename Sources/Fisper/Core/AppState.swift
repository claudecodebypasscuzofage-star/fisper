import Cocoa
import Combine
import AVFoundation

/// The dictation brain: hotkey → record → transcribe (Whisper) → clean (rules + local AI) → paste.
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
    @Published var selectedPage: Page = .home
    @Published var testFieldText = ""
    @Published var testFieldFocused = false

    enum Page: String, CaseIterable, Identifiable { case home, insights, dictionary, snippets, style, settings
        var id: String { rawValue }
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

    var lastTranscript: Transcript? { history.items.first { !$0.text.isEmpty } }

    // MARK: Lifecycle

    func boot() {
        Log.trim()
        Log.info("Fisper boot. model=\(prefs.modelID) hotkey=\(prefs.hotkey.rawValue)")
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
        prefs.$modelID.dropFirst().removeDuplicates().sink { [weak self] id in
            self?.whisper.start(modelID: id)
        }.store(in: &bag)
        whisper.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        polisher.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        history.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)

        whisper.start(modelID: prefs.modelID)
        polisher.refreshAvailability()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let engine = self.polisher.resolvedEngine(self.prefs.polishEngine, ollamaModel: self.prefs.ollamaModel)
            self.polisher.prewarm(engine, ollamaModel: self.prefs.ollamaModel)
        }

        // Poll permissions so the UI updates the moment the user flips a switch in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        pruneAudio()
    }

    func shutdown() {
        if mutedOutput { AudioDevices.setOutputMuted(false) }
        history.flush(); dictionary.flush(); snippets.flush()
        whisper.stop()
    }

    func refreshPermissions() {
        let ax = Permissions.accessibility
        if ax != accessibilityGranted {
            accessibilityGranted = ax
            if ax { hotkeys.reinstall() }
        }
        let mic = Permissions.microphone
        if mic != micStatus { micStatus = mic }
        if hotkeyActive != hotkeys.isInstalled { hotkeyActive = hotkeys.isInstalled }
    }

    // MARK: Hotkey state machine

    private func handle(_ ev: HotkeyManager.KeyEvent) -> Bool {
        switch ev {
        case .pressed:
            switch phase {
            case .recording(let handsFree):
                if handsFree {
                    stopAndTranscribe(reason: "hotkey (hands-free)")
                } else if let pending = pendingTapCancel {
                    // second tap of a double-tap → lock into hands-free
                    pending.cancel(); pendingTapCancel = nil
                    phase = .recording(handsFree: true)
                    Sounds.play("lock")
                }
            case .processing:
                // previous dictation still finishing — start the new one anyway; results paste in order
                startRecording(handsFree: false)
            default:
                startRecording(handsFree: false)
            }
            return false
        case .released:
            guard case .recording(let handsFree) = phase, !handsFree else { return false }
            let held = Date().timeIntervalSince(pressTime)
            if held < 0.28 {
                // a quick tap: wait briefly for a second tap (double-tap = hands-free), otherwise discard
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingTapCancel = nil
                    if case .recording(false) = self.phase { self.cancel(silent: true) }
                }
                pendingTapCancel = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
            } else {
                stopAndTranscribe(reason: "released")
            }
            return false
        case .spaceWhileHeld:
            if case .recording(false) = phase {
                phase = .recording(handsFree: true)
                Sounds.play("lock")
                return true
            }
            return false
        case .otherKeyWhileHeld:
            // the user is using a keyboard shortcut with fn (e.g. fn+arrow), not dictating
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
            _ = Paster.insert(t.text, restoreClipboard: prefs.restoreClipboard)
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
        let model = WhisperModelInfo.info(for: prefs.modelID)
        if !model.isDownloaded {
            showNotice("Download a speech model in Fisper Settings", isError: true)
            selectedPage = .settings
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
        polisher.ensureWarm(polisher.resolvedEngine(prefs.polishEngine, ollamaModel: prefs.ollamaModel), ollamaModel: prefs.ollamaModel)
        levels = Array(repeating: 0, count: levels.count)
        phase = .recording(handsFree: handsFree)
        Sounds.play("start")
        if prefs.muteWhileDictating, AudioDevices.isOutputMuted() == false {
            // let the start chime play before muting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, case .recording = self.phase else { return }
                AudioDevices.setOutputMuted(true); self.mutedOutput = true
            }
        }
        maxDurationWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.stopAndTranscribe(reason: "max duration") }
        maxDurationWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 10 * 60, execute: w)
    }

    func cancel(silent: Bool) {
        maxDurationWork?.cancel()
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
            let samples = self.recorder.stop()
            self.restoreOutput()
            Sounds.play("stop")
            let target = self.targetApp
            let id = UUID(); self.processingID = id
            Task { await self.process(samples: samples, target: target, releasedAt: releasedAt, jobID: id) }
        }
    }

    // MARK: Processing

    private func process(samples: [Float], target: NSRunningApplication?, releasedAt: Date, jobID: UUID) async {
        let analysis = AudioUtil.analyze(samples)
        let duration = Double(samples.count) / AudioRecorder.sampleRate
        Log.info(String(format: "audio: %.2fs, voiced %.2fs, peak %.4f", duration, analysis.voicedSeconds, analysis.peakRMS))
        guard analysis.voicedSeconds >= 0.2, analysis.peakRMS > 0.004 else {
            finish(jobID) { self.showNotice("We couldn't hear you", isError: true) }
            return
        }

        let audioName = prefs.keepAudio ? saveAudio(samples) : nil
        let prepared = AudioUtil.prepared(samples)
        let raw: String
        do {
            if whisper.state == .starting {
                for _ in 0..<150 where whisper.state == .starting { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            raw = try await whisper.transcribe(samples: prepared, language: prefs.language, prompt: whisperPrompt())
        } catch {
            Log.info("transcription failed: \(error.localizedDescription)")
            let entry = Transcript(text: "", raw: "", appName: target?.localizedName, bundleID: target?.bundleIdentifier,
                                   duration: duration, audioFile: audioName, polishedBy: "failed")
            history.items.insert(entry, at: 0)
            finish(jobID) { self.showNotice("Transcription failed — retry from History", isError: true) }
            return
        }

        let (text, by) = await pipeline(raw: raw, voiced: analysis.voicedSeconds, bundleID: target?.bundleIdentifier)
        guard !cancelledJobs.contains(jobID) else { return } // cancelled with Esc
        if text.isEmpty {
            finish(jobID) { self.showNotice("We couldn't hear you", isError: true) }
            return
        }

        var final = text
        if prefs.smartSpacing { final = TextCleaner.adaptToContext(final, before: FocusInspector.textBeforeCursor()) }

        let result = Paster.insert(final, restoreClipboard: prefs.restoreClipboard)
        let latency = Int(Date().timeIntervalSince(releasedAt) * 1000)
        Log.info("dictation: \(text.count) chars, \(latency) ms, by \(by), app=\(target?.bundleIdentifier ?? "-")")

        let entry = Transcript(text: text, raw: raw, appName: target?.localizedName, bundleID: target?.bundleIdentifier,
                               duration: max(analysis.voicedSeconds, min(duration, analysis.voicedSeconds * 1.6)),
                               latencyMs: latency, audioFile: audioName, polishedBy: by)
        history.items.insert(entry, at: 0)
        if history.items.count > 5000 { history.items.removeLast(history.items.count - 5000) }

        finish(jobID) {
            if result == .copiedOnly {
                self.showNotice("Copied — grant Accessibility so Fisper can paste", isError: true)
            } else {
                self.phase = .idle
            }
        }
    }

    private func finish(_ jobID: UUID, _ block: () -> Void) {
        // don't clobber a new recording that started while we were processing
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
        // voice commands first, so the AI sees real line breaks instead of the words "new paragraph"
        var out = TextCleaner.clean(t, removeFillers: prefs.removeFillers, voiceCommands: prefs.voiceCommands)
        var by = "Rules"

        let engine = polisher.resolvedEngine(prefs.polishEngine, ollamaModel: prefs.ollamaModel)
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

    private func whisperPrompt() -> String {
        // Bias recognition toward the user's vocabulary (names, jargon). Kept short: Whisper's prompt window is small.
        let terms = dictionary.items.map(\.vocabularyTerm).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return "" }
        return Array(terms.prefix(40)).joined(separator: ", ") + "."
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
            let analysis = AudioUtil.analyze(samples)
            guard let raw = try? await whisper.transcribe(samples: AudioUtil.prepared(samples), language: prefs.language,
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

    private func saveAudio(_ samples: [Float]) -> String? {
        let name = "\(Int(Date().timeIntervalSince1970 * 1000)).wav"
        do { try AudioUtil.wavData(samples).write(to: Paths.audio.appendingPathComponent(name)); return name } catch { return nil }
    }

    /// Keep audio only for the latest 50 dictations.
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
        // typing at ~40 wpm vs. speaking
        s.minutesSaved = max(0, Int(Double(s.totalWords) / 40.0 - speechSeconds / 60))
        // streaks
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
