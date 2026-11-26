import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var models = AppState.shared.models
    @State private var mics: [AudioInputDevice] = Demo.isOn ? [] : AudioDevices.inputDevices()
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmClear = false

    var body: some View {
        PageScroll {
            PageHeader(title: "Settings")

            Section("General") {
                SettingRow("Push-to-talk shortcut", detail: "Hold to talk. Double-tap, or add space, for hands-free.") {
                    Picker("", selection: $prefs.hotkey) {
                        ForEach(HotkeyChoice.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 200)
                }
                if prefs.hotkey == .fn && Permissions.globeKeyUsage != 0 {
                    InfoNote(text: "Your 🌐 key is set to open something when pressed. Set “Press 🌐 key to” → Do Nothing so it doesn't pop up while you dictate.",
                             button: "Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                }
                SettingToggle("Launch Fisper at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LoginItem.set(v) }
                SettingToggle("Show the flow bar when idle", detail: "The little pill at the bottom of your screen.", isOn: $prefs.showIdleBar)
                SettingToggle("Sound effects", isOn: $prefs.playSounds)
                SettingToggle("Mute other audio while dictating", isOn: $prefs.muteWhileDictating)
            }

            Section("Microphone") {
                SettingRow("Input", detail: "Current default: \(Demo.isOn ? "MacBook Pro Microphone" : AudioDevices.defaultInputName())") {
                    Picker("", selection: $prefs.microphoneUID) {
                        Text("System default").tag("")
                        ForEach(mics) { Text($0.name).tag($0.uid) }
                    }.labelsHidden().frame(width: 220)
                }
                .onAppear { if !Demo.isOn { mics = AudioDevices.inputDevices() } }
            }

            Section("Speech recognition") {
                ForEach(WhisperModelInfo.all) { m in ModelRow(model: m, models: models) }
                SettingRow("Language", detail: "Pick your language for best accuracy. Auto-detect works with Whisper Turbo.") {
                    Picker("", selection: $prefs.language) {
                        ForEach(supportedLanguages, id: \.code) { Text($0.name).tag($0.code) }
                    }.labelsHidden().frame(width: 180)
                }
            }

            Section("Auto-correct & formatting") {
                SettingRow("AI clean-up", detail: aiDetail) {
                    Picker("", selection: $prefs.polishEngine) {
                        ForEach(PolishEngine.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 240)
                }
                if prefs.polishEngine == .ollama || prefs.polishEngine == .auto {
                    SettingRow("Ollama model", detail: state.polisher.ollamaAvailable ? "Installed: \(state.polisher.ollamaModels.joined(separator: ", "))" : "Ollama isn't running. Install from ollama.com, then run: ollama pull qwen2.5:3b") {
                        TextField("qwen2.5:3b", text: $prefs.ollamaModel).textFieldStyle(.roundedBorder).frame(width: 180)
                    }
                }
                SettingToggle("Remove filler words", detail: "um, uh, stutters and repeated words", isOn: $prefs.removeFillers)
                SettingToggle("Voice commands", detail: "Say “new line” or “new paragraph”.", isOn: $prefs.voiceCommands)
                SettingToggle("Smart spacing & capitalization", detail: "Looks at the text around your cursor.", isOn: $prefs.smartSpacing)
                SettingToggle("Restore my clipboard after pasting", isOn: $prefs.restoreClipboard)
            }

            Section("Permissions") {
                PermissionRow(title: "Microphone", granted: state.micStatus == .authorized) {
                    if state.micStatus == .notDetermined { Permissions.requestMicrophone { _ in } } else { Permissions.openMicrophoneSettings() }
                }
                PermissionRow(title: "Accessibility (shortcut + paste)", granted: state.accessibilityGranted) {
                    Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
                }
            }

            Section("Data") {
                SettingToggle("Keep recordings for “Transcribe again”", detail: "Last 50 dictations, stored only on this Mac.", isOn: $prefs.keepAudio)
                HStack(spacing: 10) {
                    Button("Open data folder") { NSWorkspace.shared.open(Paths.support) }.buttonStyle(SecondaryButton())
                    Button("Clear history…") { confirmClear = true }.buttonStyle(SecondaryButton())
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Text("Fisper \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · open source · speech by whisper.cpp · runs 100% offline")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
        .confirmationDialog("Delete all dictation history and saved recordings?", isPresented: $confirmClear) {
            Button("Delete everything", role: .destructive) { state.clearHistory() }
        } message: { Text("This can't be undone.") }
    }

    private var aiDetail: String {
        let resolved = state.polisher.resolvedEngine(prefs.polishEngine, ollamaModel: prefs.ollamaModel)
        let active: String
        switch resolved {
        case .apple: active = "Using Apple Intelligence (on-device)."
        case .ollama: active = "Using Ollama · \(prefs.ollamaModel)."
        default: active = "Using built-in rules only."
        }
        return "Fixes self-corrections, grammar and lists. \(active) Apple Intelligence: \(state.polisher.appleStatus)."
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.8)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control
    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title; self.detail = detail; self.control = control()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5))
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 9)
    }
}

struct SettingToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) { self.title = title; self.detail = detail; self._isOn = isOn }
    var body: some View {
        SettingRow(title, detail: detail) { Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small) }
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
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.forestSoft.opacity(0.5)))
        .padding(.vertical, 4)
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        SettingRow(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color(hex: 0x2BB673))
            } else {
                Button("Grant access", action: action).buttonStyle(PrimaryButton())
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
        SettingRow(model.title, detail: "\(model.detail) · \(model.sizeMB) MB\(models.errors[model.id].map { " · ⚠︎ \($0)" } ?? "")") {
            if let p = models.progress[model.id] {
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 110)
                    Text("\(Int(p * 100))%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text2).frame(width: 34)
                    Button { models.cancel(model.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.text3)
                }
            } else if !downloaded {
                Button("Download") { models.download(model) }.buttonStyle(SecondaryButton())
            } else if active {
                Label(state.whisper.state == .ready || Demo.isOn ? "In use" : "Loading…", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.forest)
            } else {
                HStack(spacing: 6) {
                    Button("Use") { prefs.modelID = model.id }.buttonStyle(SecondaryButton())
                    Button { models.delete(model) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Theme.text3)
                }
            }
        }
    }
}
