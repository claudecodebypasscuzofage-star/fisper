import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        NavigationSplitView {
            Group {
                if Demo.isOn { DemoSidebar() } else { Sidebar() }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 226, max: 280)
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(prefs.accent.color)
        .id(prefs.accent)            // re-render everything when the accent changes
        .overlay {
            if !prefs.onboarded { OnboardingView().transition(.opacity) }
        }
    }

    @ViewBuilder private var page: some View {
        switch state.selectedPage {
        case .home: HomeView()
        case .insights: InsightsView()
        case .dictionary: DictionaryView()
        case .snippets: SnippetsView()
        case .style: StyleView()
        case .general: GeneralSettings()
        case .dictation: DictationSettings()
        case .audio: AudioSettings()
        case .writing: WritingSettings()
        case .appearance: AppearanceSettings()
        case .privacy: PrivacySettings()
        case .advanced: AdvancedSettings()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var state: AppState

    private var selection: Binding<AppState.Page?> {
        Binding(get: { state.selectedPage }, set: { if let p = $0 { state.selectedPage = p } })
    }

    var body: some View {
        List(selection: selection) {
            Section {
                row(.home, "Home", "house")
                row(.insights, "Insights", "chart.bar.xaxis")
                row(.dictionary, "Dictionary", "character.book.closed")
                row(.snippets, "Snippets", "text.badge.plus")
                row(.style, "Style", "textformat")
            } header: {
                HStack(spacing: 8) {
                    FisperMark(size: 14)
                    Text("Fisper").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("LOCAL").font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Theme.forest)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.forestSoft))
                }
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
            .collapsible(false)

            Section("Settings") {
                row(.general, "General", "gearshape")
                row(.dictation, "Dictation", "mic")
                row(.audio, "Audio & Noise", "waveform")
                row(.writing, "Writing & AI", "wand.and.sparkles")
                row(.appearance, "Appearance", "paintpalette")
                row(.privacy, "Privacy", "hand.raised")
                row(.advanced, "Advanced", "wrench.and.screwdriver")
            }
            .collapsible(false)
        }
        .listStyle(.sidebar)
        .modifier(DemoSidebarBackground())
        .safeAreaInset(edge: .bottom) {
            EngineStatusCard().padding(10)
        }
    }

    private func row(_ page: AppState.Page, _ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).tag(page)
    }
}

/// Static replica of the sidebar for offscreen screenshot renders (the native List can't draw offscreen).
struct DemoSidebar: View {
    @EnvironmentObject var state: AppState
    private let main: [(AppState.Page, String, String)] = [(.home, "Home", "house"), (.insights, "Insights", "chart.bar.xaxis"),
        (.dictionary, "Dictionary", "character.book.closed"), (.snippets, "Snippets", "text.badge.plus"), (.style, "Style", "textformat")]
    private let settings: [(AppState.Page, String, String)] = [(.general, "General", "gearshape"), (.dictation, "Dictation", "mic"),
        (.audio, "Audio & Noise", "waveform"), (.writing, "Writing & AI", "wand.and.sparkles"), (.appearance, "Appearance", "paintpalette"),
        (.privacy, "Privacy", "hand.raised"), (.advanced, "Advanced", "wrench.and.screwdriver")]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                FisperMark(size: 14)
                Text("Fisper").font(.system(size: 17, weight: .semibold))
                Text("LOCAL").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(Theme.forest)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.forestSoft))
            }
            .padding(.leading, 10).padding(.top, 52).padding(.bottom, 12)
            ForEach(main, id: \.0) { row($0) }
            Text("Settings").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3).padding(.leading, 10).padding(.top, 16).padding(.bottom, 4)
            ForEach(settings, id: \.0) { row($0) }
            Spacer()
            EngineStatusCard()
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }
    private func row(_ r: (AppState.Page, String, String)) -> some View {
        let sel = state.selectedPage == r.0
        return HStack(spacing: 9) {
            Image(systemName: r.2).frame(width: 18).foregroundStyle(sel ? .white : Theme.forest)
            Text(r.1).foregroundStyle(sel ? .white : Theme.text)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(sel ? Theme.forest : .clear))
    }
}

/// Offscreen screenshot rendering can't draw the system sidebar material, so demo renders get a solid one.
struct DemoSidebarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if Demo.isOn { content.scrollContentBackground(.hidden).background(Theme.sidebar) } else { content }
    }
}

struct EngineStatusCard: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences
    var body: some View {
        let (color, title, detail) = status
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 22, height: 22)
                Circle().fill(color).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.background.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.border.opacity(0.6)))
        .onTapGesture { if !state.accessibilityGranted || state.micStatus != .authorized { state.selectedPage = .advanced } }
    }
    private var status: (Color, String, String) {
        if Demo.isOn { return (Theme.success, "Ready", "Whisper Turbo · on-device") }
        if !state.accessibilityGranted { return (.orange, "Needs Accessibility", "Click to fix") }
        if state.micStatus != .authorized && state.micStatus != .notDetermined { return (.orange, "Microphone is off", "Click to fix") }
        switch state.whisper.state {
        case .ready: return (Theme.success, "Ready · hold \(prefs.hotkey.keyLabel)", "\(WhisperModelInfo.info(for: prefs.modelID).title) · on-device")
        case .starting: return (.yellow, "Warming up…", "Loading speech model")
        case .missingModel: return (.orange, "No speech model", "Download one in Dictation")
        case .failed: return (.red, "Speech engine error", "See Advanced")
        case .stopped: return (.gray, "Speech engine stopped", "")
        }
    }
}

// MARK: - Shared page chrome

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 26, weight: .bold)).tracking(-0.4)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text2) }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle; self.trailing = EmptyView() }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: 740)
                .padding(.horizontal, 40)
                .padding(.top, 34)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}
