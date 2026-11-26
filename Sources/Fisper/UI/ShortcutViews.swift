import SwiftUI

extension Shortcut {
    func sameKeys(_ o: Shortcut) -> Bool { keyCode == o.keyCode && deviceMods == o.deviceMods && genericMods == o.genericMods }
}

/// Key caps for a shortcut: [⌃][⌥][Space]
struct ShortcutKeys: View {
    let shortcut: Shortcut
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.parts.enumerated()), id: \.offset) { _, p in KeyCap(label: p, size: size) }
        }
    }
}

/// Click "Change", press any keys, done. Works for required and optional shortcuts.
struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    var allowModifierOnly = true
    var optional = false
    @StateObject private var recorder = ShortcutRecorder()
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if recorder.isRecording {
                    Group {
                        if recorder.live.isEmpty {
                            Text("Press keys…").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.forest)
                                .opacity(pulse ? 0.45 : 1)
                                .animation(.easeInOut(duration: 0.7).repeatForever(), value: pulse)
                                .onAppear { pulse = true }
                        } else {
                            HStack(spacing: 4) { ForEach(Array(recorder.live.enumerated()), id: \.offset) { _, p in KeyCap(label: p) } }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Theme.forest, lineWidth: 1.5))
                    Button("Cancel") { recorder.stop() }
                } else {
                    if let s = shortcut { ShortcutKeys(shortcut: s) } else { Text("None").foregroundStyle(Theme.text3) }
                    Button(shortcut == nil ? "Set…" : "Change…") {
                        pulse = false
                        recorder.allowModifierOnly = allowModifierOnly
                        recorder.start { new in shortcut = new }
                    }
                    if optional && shortcut != nil {
                        Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.text3).help("Turn off")
                    }
                }
            }
            if recorder.isRecording {
                Text(allowModifierOnly ? "Hold any keys, then let go · esc to cancel" : "Press a key combo · esc to cancel")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if !recorder.isRecording, let s = shortcut, !s.isModifierOnly, allowModifierOnly {
                Text("Tap types \(s.keyLabel) as usual · hold to dictate").font(.system(size: 10.5)).foregroundStyle(Theme.text3)
            }
            if let m = recorder.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.orange)
            }
        }
        .onDisappear { recorder.stop() }
    }
}

extension ShortcutField {
    /// For a shortcut that must always exist (the dictation key).
    init(required: Binding<Shortcut>) {
        self._shortcut = Binding<Shortcut?>(get: { required.wrappedValue }, set: { if let v = $0 { required.wrappedValue = v } })
        self.allowModifierOnly = true
        self.optional = false
    }
}
