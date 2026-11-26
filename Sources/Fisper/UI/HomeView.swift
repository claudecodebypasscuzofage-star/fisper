import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @State private var showHowTo = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Good evening" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return "\(part), \(Demo.firstName)"
    }

    var body: some View {
        let stats = state.stats
        PageScroll {
            HStack(alignment: .center) {
                Text(greeting).font(.system(size: 26, weight: .bold)).tracking(-0.4)
                Spacer()
                StatsPill(streak: stats.streak, words: stats.totalWords, wpm: stats.wpm)
            }

            if !Demo.isOn && (!state.accessibilityGranted || state.micStatus != .authorized || !state.hotkeyActive) {
                PermissionBanner()
            }

            HeroCard(showHowTo: $showHowTo)

            TryItCard()

            HistoryList()
        }
        .sheet(isPresented: $showHowTo) { HowToSheet() }
    }
}

struct StatsPill: View {
    let streak: Int, words: Int, wpm: Int
    var body: some View {
        HStack(spacing: 0) {
            item("🔥", streak == 1 ? "1 day" : "\(streak) days")
            divider
            item("🚀", "\(words.formatted()) words")
            divider
            item("🏅", wpm > 0 ? "\(wpm) WPM" : "— WPM")
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Theme.text2)
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(Capsule().fill(Theme.cardAlt))
        .overlay(Capsule().stroke(Theme.border))
    }
    private func item(_ e: String, _ t: String) -> some View {
        HStack(spacing: 5) { Text(e); Text(t) }.padding(.horizontal, 9)
    }
    private var divider: some View { Rectangle().fill(Theme.border).frame(width: 1, height: 13) }
}

struct HeroCard: View {
    @EnvironmentObject var prefs: Preferences
    @Binding var showHowTo: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hold \(prefs.hotkey.keyLabel) and just talk.")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.5)
                Text("Release to insert polished text wherever your cursor is. Fisper removes filler words, fixes grammar and follows you when you change your mind mid-sentence.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Show me how") { showHowTo = true }.buttonStyle(PrimaryButton())
                    shortcut("Hands-free", [prefs.hotkey.keyLabel, prefs.hotkey.keyLabel])
                    shortcut("Cancel", ["esc"])
                    shortcut("Paste last", ["⌃", "⌘", "V"])
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            HeroGlyph().frame(width: 116, height: 116)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.forest.opacity(0.16), Theme.forest.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.forest.opacity(0.18)))
    }

    private func shortcut(_ label: String, _ keys: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in KeyCap(label: k, size: 10.5) }
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.text2).padding(.leading, 2)
        }
        .fixedSize()
    }
}

/// Animated waveform orb on the home screen.
struct HeroGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(Theme.forest.gradient).shadow(color: Theme.forest.opacity(0.35), radius: 18, y: 8)
                Circle().stroke(.white.opacity(0.25), lineWidth: 1).padding(6)
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { i in
                        let h = 0.35 + 0.55 * abs(sin(t * 1.6 + Double(i) * 0.75)) * (1 - abs(Double(i) - 3) / 5)
                        Capsule().fill(.white).frame(width: 5, height: 70 * h)
                    }
                }
            }
        }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text("Finish setup to dictate everywhere").font(.system(size: 13.5, weight: .semibold))
                if state.micStatus != .authorized {
                    row("Microphone access", "Fisper needs to hear you.") {
                        if state.micStatus == .notDetermined { Permissions.requestMicrophone { _ in } } else { Permissions.openMicrophoneSettings() }
                    }
                }
                if !state.accessibilityGranted {
                    row("Accessibility access", "Lets Fisper listen for your shortcut and paste text.") {
                        Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warnBG))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.warnBorder))
    }
    private func row(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button("Grant", action: action).buttonStyle(SecondaryButton())
        }
    }
}

/// A scratch field to try dictation right inside the app.
struct TryItCard: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Try it").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                Spacer()
                if !state.testFieldText.isEmpty {
                    Button("Clear") { state.testFieldText = "" }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
            }
            ZStack(alignment: .topLeading) {
                if state.testFieldText.isEmpty {
                    Text("Click here, hold \(prefs.hotkey.keyLabel) and say something like “um so I think we should meet Tuesday, no wait, Wednesday at three”")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text3)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $state.testFieldText)
                    .font(.system(size: 13.5))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 64, maxHeight: 140)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.forest.opacity(0.6) : Theme.border, lineWidth: focused ? 1.5 : 1))
        }
    }
}

// MARK: - History

struct HistoryList: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""

    var body: some View {
        let items = filtered
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
        let days = groups.keys.sorted(by: >)
        VStack(alignment: .leading, spacing: 14) {
            if !state.history.items.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.text3).font(.system(size: 12))
                    TextField("Search history", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardAlt))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }
            if items.isEmpty {
                EmptyHistory(searching: !query.isEmpty)
            }
            ForEach(days.prefix(30), id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayLabel(day)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.8)
                    VStack(spacing: 0) {
                        let rows = groups[day]!.sorted { $0.date > $1.date }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, t in
                            HistoryRow(t: t)
                            if idx < rows.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
                }
            }
        }
        .padding(.top, 6)
    }

    private var filtered: [Transcript] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.history.items }
        return state.history.items.filter { $0.text.lowercased().contains(q) || ($0.appName ?? "").lowercased().contains(q) }
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "TODAY" }
        if cal.isDateInYesterday(d) { return "YESTERDAY" }
        let f = DateFormatter(); f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEEE, MMM d" : "MMM d, yyyy"
        return f.string(from: d).uppercased()
    }
}

struct EmptyHistory: View {
    @EnvironmentObject var prefs: Preferences
    let searching: Bool
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : "waveform").font(.system(size: 22)).foregroundStyle(Theme.text3)
            Text(searching ? "No matches" : "Your dictations will show up here").font(.system(size: 13.5, weight: .medium))
            if !searching {
                Text("Hold \(prefs.hotkey.keyLabel) anywhere — in Messages, Mail, Notes, Slack, your code editor, ChatGPT…")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

struct HistoryRow: View {
    @EnvironmentObject var state: AppState
    let t: Transcript
    @State private var hover = false
    @State private var copied = false

    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "hh:mm a"; return f }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(Self.timeFmt.string(from: t.date))
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(Theme.text3)
                .frame(width: 66, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                if t.text.isEmpty {
                    Text("Transcription failed").font(.system(size: 13.5)).foregroundStyle(Theme.danger)
                } else {
                    Text(t.text).font(.system(size: 13.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hover, let app = t.appName {
                    Text("\(app) · \(t.words) words\(t.polishedBy.map { " · \($0)" } ?? "")\(t.latencyMs > 0 ? " · \(t.latencyMs) ms" : "")")
                        .font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if !t.text.isEmpty {
                    iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                        state.copy(t); copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                }
                if t.audioFile != nil { iconButton("arrow.clockwise", help: "Transcribe again") { state.retry(t) } }
                iconButton("trash", help: "Delete") { state.delete(t) }
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Copy") { state.copy(t) }
            if t.audioFile != nil { Button("Transcribe Again") { state.retry(t) } }
            Divider()
            Button("Delete", role: .destructive) { state.delete(t) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5)).foregroundStyle(Theme.text2)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.cardAlt))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - How-to sheet

struct HowToSheet: View {
    @EnvironmentObject var prefs: Preferences
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How to use Fisper").font(Theme.serif(26))
            tip("mic", "Push to talk", "Hold \(prefs.hotkey.keyLabel), speak, release. Text appears where your cursor is.")
            tip("lock", "Hands-free", "Double-tap \(prefs.hotkey.keyLabel) — or press space while holding it — to keep recording. Press \(prefs.hotkey.keyLabel) again (or ✓) to finish.")
            tip("escape", "Cancel", "Press Esc while recording to throw it away.")
            tip("doc.on.clipboard", "Paste last", "⌃⌘V pastes your last dictation again.")
            tip("arrow.uturn.backward", "Change your mind", "“Let's meet Tuesday — no, Wednesday” → “Let's meet Wednesday.”")
            tip("list.bullet", "Lists & new lines", "Say “first… second…” for lists, or “new line” / “new paragraph”.")
            if prefs.hotkey == .fn {
                Text("Tip: if the emoji picker pops up when you press fn, set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            HStack { Spacer(); Button("Got it") { dismiss() }.buttonStyle(PrimaryButton()) }
        }
        .padding(28)
        .frame(width: 480)
        .background(Theme.canvas)
    }
    private func tip(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Theme.forest).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(body).font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
