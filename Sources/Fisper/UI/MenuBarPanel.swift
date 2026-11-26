import SwiftUI

/// The menu bar popover: status, one-click dictation, last transcript and quick toggles.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    var openWindow: (AppState.Page?) -> Void = { _ in }
    var quit: () -> Void = {}
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                FisperMark(size: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fisper").font(.system(size: 14, weight: .semibold))
                    Text(statusText).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
                }
                Spacer()
                Button { openWindow(.general) } label: { Image(systemName: "gearshape").font(.system(size: 13)) }
                    .buttonStyle(.borderless).help("Settings")
            }

            Button { state.toggleHandsFree() } label: {
                HStack(spacing: 10) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill").font(.system(size: 13, weight: .semibold))
                    Text(isRecording ? "Finish dictation" : "Start dictation").font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    if !isRecording { KeyCap(label: prefs.hotkey.keyLabel, size: 10.5) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isRecording ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Theme.forest.gradient)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let last = state.lastTranscript {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("LAST DICTATION").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                        Spacer()
                        Text(last.date, style: .relative).font(.system(size: 10)).foregroundStyle(Theme.text3)
                    }
                    Text(last.text).font(.system(size: 12.5)).lineLimit(3).foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        Button(copied ? "Copied" : "Copy") {
                            state.copy(last); copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                        }
                        Text("⌃⌘V pastes it again").font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardAlt))
            }

            VStack(spacing: 8) {
                quickPicker("AI clean-up", icon: "wand.and.sparkles", selection: $prefs.correctionLevel, options: CorrectionLevel.allCases.map { ($0, $0.title) })
                quickPicker("Noise", icon: "waveform.badge.minus", selection: $prefs.noiseMode, options: NoiseMode.allCases.map { ($0, $0.title) })
                quickPicker("Language", icon: "globe", selection: $prefs.language, options: supportedLanguages.prefix(12).map { ($0.code, $0.name) })
            }

            Divider()
            HStack {
                Button("Open Fisper") { openWindow(nil) }
                Spacer()
                Button("Quit") { quit() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12.5))
        }
        .padding(16)
        .frame(width: 320)
        .tint(prefs.accent.color)
    }

    private var isRecording: Bool { if case .recording = state.phase { return true }; return false }

    private var statusText: String {
        if Demo.isOn { return "Ready — hold \(prefs.hotkey.keyLabel) in any app" }
        if !state.accessibilityGranted { return "Needs Accessibility permission" }
        switch state.whisper.state {
        case .ready: return "Ready — hold \(prefs.hotkey.keyLabel) in any app"
        case .starting: return "Warming up…"
        case .missingModel: return "Download a speech model"
        case .failed: return "Speech engine error"
        case .stopped: return "Stopped"
        }
    }

    private func quickPicker<T: Hashable>(_ title: String, icon: String, selection: Binding<T>, options: [(T, String)]) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.system(size: 12.5)).foregroundStyle(Theme.text)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
    }
}
