import SwiftUI

/// First-run setup: permissions, shortcut, speech model.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var models = AppState.shared.models
    @State private var step = 0

    var body: some View {
        ZStack {
            Theme.sidebar.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    FisperMark(size: 16)
                    Text("Fisper").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule().fill(i <= step ? Theme.forest : Theme.border).frame(width: i == step ? 18 : 7, height: 7)
                        }
                    }
                }
                .padding(.bottom, 26)

                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: shortcut
                    default: model
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)

                HStack {
                    if step > 0 { Button("Back") { withAnimation { step -= 1 } }.buttonStyle(SecondaryButton()) }
                    Spacer()
                    if step < 3 {
                        Button(step == 0 ? "Get started" : "Continue") { withAnimation { step += 1 } }.buttonStyle(PrimaryButton())
                    } else {
                        Button("Start dictating") { withAnimation { prefs.onboarded = true } }.buttonStyle(PrimaryButton())
                            .disabled(!WhisperModelInfo.info(for: prefs.modelID).isDownloaded)
                    }
                }
            }
            .padding(34)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border))
            .shadow(color: .black.opacity(0.12), radius: 30, y: 10)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            (Text("Don't type,\n") + Text("just speak.").italic()).font(Theme.serif(46)).tracking(-0.8)
            Text("Fisper turns your voice into clean, polished writing in any app — and everything runs locally on your Mac. Free, private, no account, no limits.")
                .font(.system(size: 14.5)).foregroundStyle(Theme.text2).lineSpacing(3)
            HStack(spacing: 18) {
                feature("bolt.fill", "Instant", "~1s from release to text")
                feature("lock.fill", "Private", "Nothing leaves your Mac")
                feature("wand.and.stars", "Polished", "Fillers & typos removed")
            }
            .padding(.top, 8)
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.forest)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Two quick permissions").font(Theme.serif(30))
            Text("Fisper needs to hear you, and to type for you. Both stay on this Mac.").font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            permCard(icon: "mic.fill", title: "Microphone", detail: "To hear what you say while you hold the shortcut.",
                     granted: state.micStatus == .authorized) {
                if state.micStatus == .notDetermined { Permissions.requestMicrophone { _ in } } else { Permissions.openMicrophoneSettings() }
            }
            permCard(icon: "keyboard.fill", title: "Accessibility", detail: "To notice your shortcut in any app and paste the text where your cursor is.",
                     granted: state.accessibilityGranted) {
                Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
            }
            if !state.accessibilityGranted {
                Text("In System Settings → Privacy & Security → Accessibility, switch on Fisper. This page updates by itself.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
        }
    }

    private func permCard(icon: String, title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.forest)
                .frame(width: 38, height: 38).background(Circle().fill(Theme.forestSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color(hex: 0x2BB673))
            } else {
                Button("Allow", action: action).buttonStyle(PrimaryButton())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your dictation key").font(Theme.serif(30))
            Text("Hold it anywhere to talk, release to paste. Double-tap for hands-free.").font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            VStack(spacing: 8) {
                ForEach(Array(Shortcut.presets.prefix(4)), id: \.self) { h in
                    let on = prefs.hotkey.sameKeys(h)
                    Button { prefs.hotkey = h } label: {
                        HStack {
                            Text(h.title).font(.system(size: 13.5, weight: .medium))
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.forest : Theme.text3)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.forest : Theme.border, lineWidth: on ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text("Or pick your own keys").font(.system(size: 13.5, weight: .medium))
                    Spacer()
                    ShortcutField(required: $prefs.hotkey)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Shortcut.presets.prefix(4).contains { prefs.hotkey.sameKeys($0) } ? Theme.border : Theme.forest))
            }
            if prefs.hotkey.isFn {
                InfoNote(text: "So the emoji picker doesn't pop up: System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.",
                         button: "Open") { Permissions.openKeyboardSettings() }
            }
        }
    }

    private var model: some View {
        let m = WhisperModelInfo.info(for: prefs.modelID)
        let _ = models.revision
        return VStack(alignment: .leading, spacing: 14) {
            Text("Speech engine").font(Theme.serif(30))
            Text("Fisper uses OpenAI's Whisper running on your Mac's GPU. The model downloads once.").font(.system(size: 13.5)).foregroundStyle(Theme.text2)
            HStack(spacing: 14) {
                Image(systemName: "waveform").font(.system(size: 16)).foregroundStyle(Theme.forest)
                    .frame(width: 38, height: 38).background(Circle().fill(Theme.forestSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.system(size: 14, weight: .semibold))
                    Text("\(m.detail) · \(m.sizeMB) MB").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                }
                Spacer()
                if m.isDownloaded {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color(hex: 0x2BB673))
                } else if let p = models.progress[m.id] {
                    ProgressView(value: p).frame(width: 90)
                } else {
                    Button("Download") { models.download(m) }.buttonStyle(PrimaryButton())
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            Text("Auto-correct uses \(state.polisher.appleAvailable ? "Apple Intelligence on this Mac" : "built-in rules") — you can add a local Ollama model later in Settings.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
    }
}
