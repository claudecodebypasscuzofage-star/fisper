import SwiftUI
import AVFoundation

// Native, System Settings–style grouped forms. Every page binds straight to Preferences, so changes apply instantly.

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: Content
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.forest.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 20, weight: .bold))
                        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                    }
                }
                .padding(.vertical, 4)
            }
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }
}

private struct Hint: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var prefs: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        SettingsPage(title: "General", subtitle: "Your shortcut and how Fisper behaves.", icon: "gearshape.fill") {
            Section("Shortcut") {
                LabeledContent {
                    ShortcutField(required: $prefs.hotkey)
                } label: {
                    Text("Hold to dictate")
                    Hint(text: "Any key or combo: fn, right ⌥, left ⌃ + left ⌥, ⌃⌥ Space, F5…")
                }
                LabeledContent("Quick presets") {
                    Menu(Shortcut.presets.first { $0.sameKeys(prefs.hotkey) }?.title ?? "Custom") {
                        ForEach(Shortcut.presets, id: \.self) { p in Button(p.title) { prefs.hotkey = p } }
                    }
                    .fixedSize()
                }
                if prefs.hotkey.isFn && Permissions.globeKeyUsage != 0 {
                    LabeledContent {
                        Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                    } label: {
                        Text("Set “Press 🌐 key to” → Do Nothing")
                        Hint(text: "Otherwise macOS opens the emoji picker or Dictation when you tap fn.")
                    }
                }
                Toggle(isOn: $prefs.doubleTapHandsFree) {
                    Text("Double-tap for hands-free")
                    Hint(text: "Tap \(prefs.hotkey.keyLabel) twice to keep recording without holding it.")
                }
                Toggle("\(prefs.hotkey.keyLabel) + Space locks hands-free", isOn: $prefs.spaceLocksHandsFree)
                LabeledContent {
                    Slider(value: $prefs.minHoldSeconds, in: 0.1...0.7, step: 0.05).frame(width: 180)
                } label: {
                    Text("Ignore taps shorter than \(String(format: "%.2f", prefs.minHoldSeconds)) s")
                    Hint(text: "Prevents accidental recordings when you just brush the key.")
                }
                Stepper(value: $prefs.maxRecordingMinutes, in: 1...30, step: 1) {
                    Text("Stop automatically after \(Int(prefs.maxRecordingMinutes)) min")
                }
            }
            Section("More shortcuts") {
                LabeledContent {
                    ShortcutField(shortcut: $prefs.toggleShortcut, allowModifierOnly: false, optional: true)
                } label: {
                    Text("Start / stop hands-free")
                    Hint(text: "Press once to start, again to finish — no holding.")
                }
                LabeledContent {
                    ShortcutField(shortcut: $prefs.pasteLastShortcut, allowModifierOnly: false, optional: true)
                } label: {
                    Text("Paste last dictation")
                }
                LabeledContent("Cancel dictation") { KeyCap(label: "esc") }
            }
            Section("App") {
                Toggle("Launch Fisper at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.set(v) }
                Toggle("Show menu bar icon", isOn: $prefs.showMenuBarIcon)
            }
            Section {
                ExcludedAppsEditor()
            } header: {
                Text("Don't listen in these apps")
            } footer: {
                Hint(text: "Useful for games or apps where you use \(prefs.hotkey.keyLabel) for something else.")
            }
        }
    }
}

struct ExcludedAppsEditor: View {
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        if prefs.excludedApps.isEmpty {
            Text("No apps excluded").foregroundStyle(Theme.text2)
        }
        ForEach(prefs.excludedApps, id: \.self) { bid in
            HStack {
                AppIcon(bundleID: bid).frame(width: 18, height: 18)
                Text(appName(bid))
                Spacer()
                Button { prefs.excludedApps.removeAll { $0 == bid } } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.text3)
            }
        }
        Menu("Add app…") {
            ForEach(runningApps, id: \.self) { bid in
                Button(appName(bid)) { if !prefs.excludedApps.contains(bid) { prefs.excludedApps.append(bid) } }
            }
        }
        .fixedSize()
    }
    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { $0 != Bundle.main.bundleIdentifier && !prefs.excludedApps.contains($0) }
            .sorted { appName($0) < appName($1) }
    }
    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bid
    }
}

struct AppIcon: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app")
        }
    }
}

// MARK: - Dictation

struct DictationSettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var models = AppState.shared.models

    var body: some View {
        SettingsPage(title: "Dictation", subtitle: "Speech recognition and how text is inserted.", icon: "mic.fill") {
            Section("Speech model") {
                ForEach(WhisperModelInfo.all) { m in ModelRow(model: m, models: models) }
            }
            Section("Recognition") {
                Picker("Language", selection: $prefs.language) {
                    ForEach(supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
                }
                Toggle(isOn: $prefs.fastMode) {
                    Text("Fast mode")
                    Hint(text: "Sizes Whisper's context to your clip — about 3× faster on short dictations.")
                }
                Toggle(isOn: $prefs.streaming) {
                    Text("Transcribe while you speak")
                    Hint(text: "Long dictations are processed in the background as you talk, so they finish instantly.")
                }
            }
            Section("Inserting text") {
                Picker("Method", selection: $prefs.pasteMethod) {
                    ForEach(PasteMethod.allCases) { Text($0.title).tag($0) }
                }
                if prefs.pasteMethod == .paste {
                    Toggle("Restore my clipboard afterwards", isOn: $prefs.restoreClipboard)
                }
                Toggle(isOn: $prefs.smartSpacing) {
                    Text("Smart spacing & capitalization")
                    Hint(text: "Reads the text before your cursor to add a space or continue a sentence in lowercase.")
                }
                Toggle("Add a space after each dictation", isOn: $prefs.addTrailingSpace)
                Toggle(isOn: $prefs.pressReturnAfter) {
                    Text("Press Return after inserting")
                    Hint(text: "Sends messages automatically in chat apps. Careful in documents.")
                }
            }
        }
    }
}

struct ModelRow: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var state: AppState
    let model: WhisperModelInfo
    @ObservedObject var models: ModelManager

    var body: some View {
        let _ = models.revision
        let downloaded = model.isDownloaded
        let active = prefs.modelID == model.id
        LabeledContent {
            if let p = models.progress[model.id] {
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 110)
                    Text("\(Int(p * 100))%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).frame(width: 34)
                    Button { models.cancel(model.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.text3)
                }
            } else if !downloaded {
                Button("Download") { models.download(model) }
            } else if active {
                Label(state.whisper.state == .ready || Demo.isOn ? "In use" : "Loading…", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.forest)
            } else {
                HStack(spacing: 8) {
                    Button("Use") { prefs.modelID = model.id }
                    Button { models.delete(model) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
        } label: {
            Text(model.title)
            Hint(text: "\(model.detail) · \(model.sizeMB) MB\(models.errors[model.id].map { " · ⚠︎ \($0)" } ?? "")")
        }
    }
}

// MARK: - Audio & noise

struct AudioSettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var mics: [AudioInputDevice] = Demo.isOn ? [] : AudioDevices.inputDevices()

    var body: some View {
        SettingsPage(title: "Audio & Noise", subtitle: "Microphone, background-noise removal and quiet-speech boost.", icon: "waveform") {
            Section("Microphone") {
                Picker("Input", selection: $prefs.microphoneUID) {
                    Text("System default (\(Demo.isOn ? "MacBook Pro Microphone" : AudioDevices.defaultInputName()))").tag("")
                    ForEach(mics) { Text($0.name).tag($0.uid) }
                }
                .onAppear { if !Demo.isOn { mics = AudioDevices.inputDevices() } }
                Toggle("Mute other audio while dictating", isOn: $prefs.muteWhileDictating)
            }
            Section {
                Picker("Background noise", selection: $prefs.noiseMode) {
                    ForEach(NoiseMode.allCases) { Text($0.title).tag($0) }
                }
                Hint(text: prefs.noiseMode.detail)
                if prefs.noiseMode == .auto || prefs.noiseMode == .always {
                    LabeledContent {
                        Slider(value: $prefs.isolationStrength, in: 0.5...1.0, step: 0.05).frame(width: 180)
                    } label: {
                        Text("Isolation strength · \(Int(prefs.isolationStrength * 100))%")
                        Hint(text: "85% measured best for accuracy. Higher removes more noise but can blur words.")
                    }
                }
                Toggle(isOn: $prefs.boostQuietSpeech) {
                    Text("Boost quiet & mumbled speech")
                    Hint(text: "Evens out your volume so whispering or speaking far from the mic still works.")
                }
            } header: {
                Text("Noise & clarity")
            } footer: {
                if !AudioEnhancer.isolationAvailable {
                    Hint(text: "Voice isolation isn't available on this Mac; Fisper will use filtering only.")
                }
            }
            if let r = state.lastAudioReport {
                Section("Last dictation") {
                    LabeledContent("Signal-to-noise", value: String(format: "%.0f dB · %@", r.snrDB, r.snrDB < AudioEnhancer.noisyThresholdDB ? "noisy room" : "clean"))
                    LabeledContent("Voice isolation", value: r.isolated ? "Applied" : "Not needed")
                    LabeledContent("Volume boost", value: String(format: "%+.0f dB", r.gainDB))
                    LabeledContent("Processing time", value: "\(r.ms) ms")
                }
            }
        }
    }
}

// MARK: - Writing & AI

struct WritingSettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        SettingsPage(title: "Writing & AI", subtitle: "How much Fisper corrects, and the on-device model that does it.", icon: "wand.and.sparkles") {
            Section("Auto-correct") {
                Picker("Correction", selection: $prefs.correctionLevel) {
                    ForEach(CorrectionLevel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Hint(text: prefs.correctionLevel.detail)
                Toggle(isOn: $prefs.smartSkipAI) {
                    Text("Fast mode: only use AI when needed")
                    Hint(text: "Clean sentences are inserted instantly; the AI only runs for fillers, self-corrections, lists, numbers or grammar issues.")
                }
                Toggle("Remove filler words (um, uh) and stutters", isOn: $prefs.removeFillers)
                Toggle("Turn spoken lists into bullet points", isOn: $prefs.formatLists)
                Toggle("Write numbers as digits", isOn: $prefs.numbersAsDigits)
                Toggle(isOn: $prefs.voiceCommands) {
                    Text("Voice commands")
                    Hint(text: "Say “new line” or “new paragraph”.")
                }
            }
            Section {
                Toggle(isOn: $prefs.matchMyStyle) {
                    Text("Match my writing style")
                    Hint(text: "Tells the AI your habits in each kind of app (sentence length, contractions, exclamation marks) — never your actual messages.")
                }
                Toggle(isOn: $prefs.learnFromEdits) {
                    Text("Learn from my corrections")
                    Hint(text: "If you fix a word right after dictating (“Ria” → “Priya”), Fisper adds it to your Dictionary.")
                }
                Toggle(isOn: $prefs.learnVocabulary) {
                    Text("Learn names & jargon I use")
                    Hint(text: "Words you say often are hinted to the speech model so they're recognized correctly.")
                }
            } header: {
                Text("Personalization")
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if prefs.customInstructions.isEmpty {
                        Text("e.g. Use British spelling. Never use exclamation marks. Write “OK”, not “okay”. My company is spelled AcmeCo.")
                            .foregroundStyle(Theme.text3).padding(.top, 1).padding(.leading, 5).allowsHitTesting(false)
                    }
                    TextEditor(text: $prefs.customInstructions)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70)
                }
                .font(.system(size: 13))
            } header: {
                Text("Your rules")
            } footer: {
                Hint(text: "Plain-English preferences the AI follows on every dictation. For names and spellings, the Dictionary is more reliable.")
            }
            Section("Engine") {
                Picker("AI clean-up", selection: $prefs.polishEngine) {
                    ForEach(PolishEngine.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Active now", value: activeName)
                LabeledContent("Apple Intelligence", value: state.polisher.appleStatus)
                if state.polisher.ollamaAvailable {
                    Picker("Ollama model", selection: $prefs.ollamaModel) {
                        ForEach(state.polisher.ollamaModels, id: \.self) { Text($0).tag($0) }
                        if !state.polisher.ollamaModels.contains(prefs.ollamaModel) { Text(prefs.ollamaModel).tag(prefs.ollamaModel) }
                    }
                } else {
                    LabeledContent("Ollama", value: "Not running")
                    Hint(text: "Optional. Install from ollama.com, then run “ollama pull qwen2.5:3b” for great results.")
                }
                Button("Refresh engines") { state.polisher.refreshAvailability() }
            }
        }
    }

    private var activeName: String {
        switch state.activeEngine {
        case .apple: return "Apple Intelligence"
        case .ollama: return "Ollama · \(prefs.ollamaModel)"
        default: return "Built-in rules"
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Colors, the flow bar and sounds.", icon: "paintpalette.fill") {
            Section("Look") {
                Picker("Appearance", selection: $prefs.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Accent color") {
                HStack(spacing: 14) {
                    ForEach(AccentChoice.allCases.filter { $0 != .custom }) { a in
                        Button { prefs.accent = a } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(a == .system ? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)) : AnyShapeStyle(a.color))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.primary.opacity(prefs.accent == a ? 0.85 : 0), lineWidth: 2).padding(-4))
                                Text(a.title).font(.system(size: 10.5)).foregroundStyle(Theme.text2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(spacing: 5) {
                        ColorPicker("", selection: Binding(get: { prefs.customAccent.color },
                                                           set: { prefs.customAccent = RGBAColor($0); prefs.accent = .custom }),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .overlay(Circle().stroke(Color.primary.opacity(prefs.accent == .custom ? 0.85 : 0), lineWidth: 2).padding(-4).allowsHitTesting(false))
                        Text("Custom").font(.system(size: 10.5)).foregroundStyle(Theme.text2)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Flow bar") {
                HStack {
                    Spacer()
                    BarPreview()
                    Spacer()
                }
                .padding(.vertical, 8)
                Picker("Style", selection: $prefs.barStyle) {
                    ForEach(BarStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    HStack {
                        Picker("", selection: Binding(get: { prefs.barCustomPosition == nil ? prefs.barPosition : nil },
                                                      set: { if let v = $0 { prefs.barCustomPosition = nil; prefs.barPosition = v } })) {
                            ForEach(BarPosition.allCases) { Text($0.title).tag(Optional($0)) }
                            if prefs.barCustomPosition != nil { Text("Custom").tag(BarPosition?.none) }
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                    }
                } label: {
                    Text("Position")
                    Hint(text: "Or just drag the bar anywhere on screen — it remembers.")
                }
                ColorPicker("Bar color", selection: Binding(get: { prefs.barColor.color }, set: { prefs.barColor = RGBAColor($0) }), supportsOpacity: false)
                ColorPicker("Waveform & text color", selection: Binding(get: { prefs.waveColor.color }, set: { prefs.waveColor = RGBAColor($0) }), supportsOpacity: false)
                LabeledContent("Opacity") {
                    Slider(value: $prefs.barOpacity, in: 0.4...1.0).frame(width: 180)
                }
                Button("Reset flow bar look") {
                    prefs.barColor = .midnight; prefs.waveColor = .white; prefs.barOpacity = 0.82; prefs.barScale = 1
                    prefs.barCustomPosition = nil; prefs.barPosition = .bottom; prefs.barStyle = .glass
                }
                LabeledContent("Size") {
                    Slider(value: $prefs.barScale, in: 0.8...1.4, step: 0.05).frame(width: 180)
                }
                Picker(selection: $prefs.idleBar) {
                    ForEach(IdleBarMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Show the bar")
                    Hint(text: "It always appears while you dictate. “Near the pointer” keeps it invisible until you move the mouse to it.")
                }
            }
            Section("Sound") {
                Toggle("Sound effects", isOn: $prefs.playSounds)
                if prefs.playSounds {
                    LabeledContent("Volume") {
                        HStack {
                            Slider(value: $prefs.soundVolume, in: 0.1...1.0).frame(width: 150)
                            Button { Sounds.play("start") } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }
}

/// Live preview of the flow bar in the chosen style, over a colorful "desktop".
struct BarPreview: View {
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let levels = (0..<28).map { i in Float(0.3 + 0.6 * abs(sin(t * 3 + Double(i) * 0.5))) }
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x7BA7D9), Color(hex: 0xC9A5E0), Color(hex: 0xF2C6A0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 300, height: 86)
                FlowPill(phase: .recording(handsFree: true), levels: levels, hovering: false, keyLabel: prefs.hotkey.keyLabel, style: prefs.barStyle,
                         barColor: prefs.barColor.color, waveColor: prefs.waveColor.color, opacity: prefs.barOpacity)
                    .scaleEffect(prefs.barScale)
            }
        }
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var confirmClear = false

    var body: some View {
        SettingsPage(title: "Privacy", subtitle: "Everything stays on this Mac. You decide what's kept.", icon: "hand.raised.fill") {
            Section {
                Label("Audio and text are processed on-device", systemImage: "checkmark.shield.fill")
                Label("No account, no analytics, no cloud", systemImage: "icloud.slash")
                Label("Network is only used to download models you choose", systemImage: "arrow.down.circle")
                Label("To learn from your corrections, Fisper re-reads only the text field it just typed into, a few seconds later", systemImage: "eye")
            }
            Section("History") {
                Picker("Keep dictation history", selection: $prefs.retention) {
                    ForEach(Retention.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: prefs.retention) { _, _ in state.applyRetention() }
                Toggle(isOn: $prefs.keepAudio) {
                    Text("Keep recordings for “Transcribe again”")
                    Hint(text: "Only the latest 50, stored in Fisper's folder.")
                }
                HStack {
                    Button("Show data folder") { NSWorkspace.shared.open(Paths.support) }
                    Button("Delete all history…", role: .destructive) { confirmClear = true }
                }
            }
        }
        .confirmationDialog("Delete all dictation history and saved recordings?", isPresented: $confirmClear) {
            Button("Delete everything", role: .destructive) { state.clearHistory() }
        } message: { Text("This can't be undone.") }
    }
}

// MARK: - Advanced

struct AdvancedSettings: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var confirmReset = false

    var body: some View {
        SettingsPage(title: "Advanced", subtitle: "Permissions, diagnostics and resets.", icon: "wrench.and.screwdriver.fill") {
            Section("Permissions") {
                PermissionRow(title: "Microphone", detail: "To hear you", granted: state.micStatus == .authorized || Demo.isOn) {
                    if state.micStatus == .notDetermined { Permissions.requestMicrophone { _ in } } else { Permissions.openMicrophoneSettings() }
                }
                PermissionRow(title: "Accessibility", detail: "To notice your shortcut and insert text", granted: state.accessibilityGranted || Demo.isOn) {
                    Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
                }
                LabeledContent("Keyboard listener", value: state.hotkeyActive || Demo.isOn ? "Active" : "Waiting for Accessibility")
            }
            Section {
                LabeledContent("Speech engine", value: engineText)
                LabeledContent("Voice isolation", value: AudioEnhancer.isolationAvailable ? "Available" : "Unavailable")
                HStack {
                    Button("Run test dictation") { state.runDiagnostics() }
                    Button("Restart speech engine") { state.whisper.start(modelID: prefs.modelID) }
                    Button("Open log") { NSWorkspace.shared.open(Paths.log) }
                }
                if let r = state.diagnosticResult {
                    Text(r).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text2).textSelection(.enabled)
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Hint(text: "The test speaks a sentence with the system voice and runs it through the full pipeline — no microphone needed.")
            }
            Section {
                Button("Show onboarding again") { prefs.onboarded = false; state.selectedPage = .home }
                Button("Reset all settings…", role: .destructive) { confirmReset = true }
            }
        }
        .confirmationDialog("Reset every setting to its default? Your history, dictionary and snippets are kept.", isPresented: $confirmReset) {
            Button("Reset settings", role: .destructive) { prefs.resetAll(); NSApp.terminate(nil) }
        } message: { Text("Fisper will quit; open it again to start fresh.") }
    }

    private var engineText: String {
        if Demo.isOn { return "Ready (Whisper Turbo)" }
        switch state.whisper.state {
        case .ready: return "Ready (\(WhisperModelInfo.info(for: prefs.modelID).title))"
        case .starting: return "Starting…"
        case .missingModel: return "No model downloaded"
        case .failed(let m): return m
        case .stopped: return "Stopped"
        }
    }
}

struct PermissionRow: View {
    let title: String
    var detail: String = ""
    let granted: Bool
    let action: () -> Void
    var body: some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
            } else {
                Button("Grant access", action: action).buttonStyle(PrimaryButton())
            }
        } label: {
            Text(title)
            if !detail.isEmpty { Hint(text: detail) }
        }
    }
}

struct InfoNote: View {
    let text: String
    var button: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Theme.forest)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button, let action { Button(button, action: action).buttonStyle(SecondaryButton()) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.forestSoft))
        .padding(.vertical, 4)
    }
}
