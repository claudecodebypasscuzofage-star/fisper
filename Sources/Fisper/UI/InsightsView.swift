import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let s = state.stats
        PageScroll {
            PageHeader(title: "Insights", subtitle: "How much talking has saved you. Computed locally from your history.")

            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        BigNumber(value: s.wpm > 0 ? "\(s.wpm)" : "—", label: "WORDS PER MINUTE")
                        WPMGauge(wpm: s.wpm).frame(height: 78).padding(.top, 8)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        BigNumber(value: s.totalWords.formatted(), label: "TOTAL WORDS DICTATED")
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        Text(booksLine(s.totalWords)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                        HStack(spacing: 14) {
                            mini("\(s.dictations.formatted())", "dictations")
                            mini("\(s.todayWords.formatted())", "today")
                            mini(s.minutesSaved >= 60 ? "\(s.minutesSaved / 60)h \(s.minutesSaved % 60)m" : "\(s.minutesSaved)m", "saved vs typing")
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Where you talk").font(Theme.serif(22))
                            Spacer()
                        }
                        UsageBars(perCategory: s.perCategory)
                    }
                }
                .frame(maxWidth: 300)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.streak == 1 ? "1 day streak" : "\(s.streak) day streak").font(Theme.serif(22))
                            Spacer()
                            Text("LONGEST | \(s.longestStreak) DAYS").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                        }
                        StreakHeatmap(perDay: s.perDay)
                    }
                }
            }
            YourVoiceCard()
        }
    }

    private func booksLine(_ words: Int) -> String {
        if words >= 90_000 { return "You've dictated about \(words / 90_000) book\(words / 90_000 == 1 ? "" : "s") worth of text!" }
        if words >= 300 { return "That's about \(words / 300) page\(words / 300 == 1 ? "" : "s") you didn't have to type." }
        return "Hold your shortcut and start talking — the numbers add up fast."
    }

    private func mini(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 14, weight: .semibold))
            Text(l).font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
    }
}

struct BigNumber: View {
    let value: String, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 28, weight: .medium)).tracking(-0.5)
            Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.8)
        }
    }
}

struct WPMGauge: View {
    let wpm: Int
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * 2)
            let frac = min(1, Double(wpm) / 220)
            ZStack {
                Arc(fraction: 1).stroke(Theme.forestSoft, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                Arc(fraction: frac).stroke(Theme.forest, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                VStack(spacing: 0) {
                    Text(label).font(.system(size: 11)).foregroundStyle(Theme.text3)
                    Text("\(Int(frac * 100))%").font(.system(size: 17, weight: .semibold))
                }
                .offset(y: geo.size.height * 0.18)
            }
            .frame(width: w, height: w / 2 + 8)
            .frame(maxWidth: .infinity)
        }
    }
    private var label: String { wpm >= 120 ? "Speedy" : wpm >= 60 ? "Talk speed" : "Of 220 wpm" }
}

struct Arc: Shape {
    var fraction: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radius = min(r.width / 2, r.height) - 8
        p.addArc(center: CGPoint(x: r.midX, y: r.maxY - 4), radius: radius, startAngle: .degrees(180),
                 endAngle: .degrees(180 + 180 * fraction), clockwise: false)
        return p
    }
}

struct UsageBars: View {
    let perCategory: [AppCategory: Int]
    var body: some View {
        let total = max(1, perCategory.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 11) {
            ForEach(AppCategory.allCases) { c in
                let v = perCategory[c] ?? 0
                let frac = Double(v) / Double(total)
                HStack(spacing: 10) {
                    Image(systemName: c.icon).frame(width: 18).foregroundStyle(Theme.text2).font(.system(size: 12))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.forestSoft.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4).fill(Theme.forest.opacity(0.35 + 0.65 * frac))
                                .frame(width: max(v > 0 ? 28 : 0, g.size.width * frac))
                            Text("\(Int(frac * 100))%").font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(frac > 0.25 ? .white : Theme.text2).padding(.leading, 7)
                        }
                    }
                    .frame(height: 20)
                    Text(c.shortTitle).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.text3)
                        .frame(width: 64, alignment: .leading).lineLimit(1)
                }
            }
        }
    }
}

struct StreakHeatmap: View {
    let perDay: [Date: Int]
    private let weeks = 16
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1 // 0 = Sunday
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        let maxV = max(1, perDay.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { d in
                        Text(d).font(.system(size: 9)).foregroundStyle(Theme.text3).frame(height: 13)
                    }
                }
                .frame(width: 24)
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let v = perDay[day] ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day > today ? Color.clear : color(v, maxV))
                                .frame(width: 13, height: 13)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(day == today ? Theme.forest : .clear, lineWidth: 1.2))
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less").font(.system(size: 10)).foregroundStyle(Theme.text3)
                ForEach([0, 1, 2, 3], id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(color(i == 0 ? 0 : i, 3)).frame(width: 10, height: 10)
                }
                Text("More").font(.system(size: 10)).foregroundStyle(Theme.text3)
            }
        }
    }
    private func color(_ v: Int, _ maxV: Int) -> Color {
        if v == 0 { return Theme.hairline }
        let f = Double(v) / Double(maxV)
        return Theme.forest.opacity(0.3 + 0.7 * f)
    }
}


struct YourVoiceCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let p = state.personal.profile
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your voice").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text("Fisper adapts to these").font(.system(size: 11)).foregroundStyle(Theme.text3)
                }
                HStack(alignment: .top, spacing: 28) {
                    stat("\(p.avgWords)", "words per dictation")
                    stat("\(p.learnedWords.count)", "names & terms picked up")
                    stat("\(p.correctionsLearned)", "corrections learned")
                }
                if !p.fillers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WORDS FISPER REMOVES FOR YOU").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                        Chips(items: p.fillers.map { "“\($0.word)” ×\($0.count)" })
                    }
                }
                if !p.learnedWords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NAMES & JARGON YOU USE").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                        Chips(items: Array(p.learnedWords.prefix(14)))
                    }
                }
                if !p.topWords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR FAVORITE WORDS").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                        Chips(items: p.topWords.prefix(8).map(\.word))
                    }
                }
                if p.dictations < 3 {
                    Text("Dictate a few times and Fisper will start learning your names, phrasing and habits.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                }
            }
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 22, weight: .semibold))
            Text(l).font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
    }
}

struct Chips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { t in
                Text(t).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.forestSoft))
                    .foregroundStyle(Theme.text)
            }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); widest = max(widest, x)
        }
        return CGSize(width: min(maxW, widest), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
