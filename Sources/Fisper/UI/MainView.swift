import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: Preferences

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 212)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.canvas)
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1)
                page
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 44)
            .padding([.trailing, .bottom], 8)
        }
        .background(Theme.sidebar)
        .overlay {
            if !prefs.onboarded { OnboardingView().transition(.opacity) }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var page: some View {
        switch state.selectedPage {
        case .home: HomeView()
        case .insights: InsightsView()
        case .dictionary: DictionaryView()
        case .snippets: SnippetsView()
        case .style: StyleView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                FisperMark(size: 15)
                Text("Fisper").font(.system(size: 19, weight: .semibold)).tracking(-0.3)
                Text("Local")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.lilacText)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lilac))
            }
            .padding(.leading, 12)
            .padding(.top, 52)
            .padding(.bottom, 18)

            NavItem(page: .home, title: "Home", icon: "square.grid.2x2")
            NavItem(page: .insights, title: "Insights", icon: "chart.bar")
            NavItem(page: .dictionary, title: "Dictionary", icon: "character.book.closed")
            NavItem(page: .snippets, title: "Snippets", icon: "scissors")
            NavItem(page: .style, title: "Style", icon: "textformat")

            Spacer()

            PrivacyCard()
                .padding(.horizontal, 8)
                .padding(.bottom, 10)

            EngineStatusRow()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            NavItem(page: .settings, title: "Settings", icon: "gearshape")
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/claudecodebypasscuzofage-star/fisper#readme")!)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle").frame(width: 18)
                    Text("Help")
                    Spacer()
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
    }
}

struct NavItem: View {
    @EnvironmentObject var state: AppState
    let page: AppState.Page
    let title: String
    let icon: String
    @State private var hover = false

    var body: some View {
        let selected = state.selectedPage == page
        Button { state.selectedPage = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13.5, weight: selected ? .medium : .regular))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.selection : (hover ? Theme.selection.opacity(0.5) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.horizontal, 8)
    }
}

struct PrivacyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("100% on-device").font(.system(size: 12.5, weight: .semibold))
            }
            Text("Your voice never leaves this Mac. No account, no cloud, no word limits.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
    }
}

struct EngineStatusRow: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let (color, text) = status
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
        }
    }
    private var status: (Color, String) {
        if Demo.isOn { return (Color(hex: 0x2BB673), "Ready · Whisper Turbo") }
        if !state.accessibilityGranted { return (.orange, "Needs Accessibility access") }
        switch state.whisper.state {
        case .ready: return (Color(hex: 0x2BB673), "Ready · \(WhisperModelInfo.info(for: state.prefs.modelID).title)")
        case .starting: return (.yellow, "Starting speech engine…")
        case .missingModel: return (.orange, "Download a speech model")
        case .failed: return (.red, "Speech engine error")
        case .stopped: return (.gray, "Speech engine stopped")
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
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 22, weight: .semibold)).tracking(-0.3)
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
                .frame(maxWidth: 720)
                .padding(.horizontal, 40)
                .padding(.top, 36)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}
