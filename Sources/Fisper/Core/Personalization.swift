import Cocoa
import ApplicationServices

/// Everything Fisper learns about how *you* talk and write. All of it is computed locally from your own history.
@MainActor
final class Personalization: ObservableObject {
    struct Profile {
        var learnedWords: [String] = []                // names & jargon you say often
        var fillers: [(word: String, count: Int)] = []  // your verbal habits (from raw speech)
        var topWords: [(word: String, count: Int)] = []
        var avgWords = 0
        var correctionsLearned = 0
        var dictations = 0
    }

    @Published private(set) var profile = Profile()
    private var rebuildWork: DispatchWorkItem?

    func scheduleRebuild(history: [Transcript], dictionary: [DictEntry]) {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.profile = Self.build(history: history, dictionary: dictionary) }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Recent dictations from the same kind of app, used as tone examples for the AI.
    func styleExamples(for category: AppCategory, history: [Transcript]) -> [String] {
        history.lazy
            .filter { !$0.text.isEmpty && AppCategory.of(bundleID: $0.bundleID) == category && $0.raw != "demo" }
            .map(\.text)
            .filter { let n = $0.split(separator: " ").count; return n >= 6 && n <= 45 && !$0.contains("\n") }
            .prefix(3)
            .map { String($0) }
    }

    // MARK: Building the profile

    private static let fillerWords = ["um", "uh", "like", "you know", "basically", "actually", "literally", "i mean", "kind of", "sort of", "so yeah", "right"]

    static let stopWords: Set<String> = Set("""
    a an the and or but so if then than that this these those it its it's i i'm i've i'll i'd me my mine we we're us our you you're your
    he she they them their there here is are was were be been being am do does did done have has had having will would can could should
    shall may might must to of in on at by for with from about as into like through over after before under again further just also not
    no yes yeah ok okay all any both each few more most other some such only own same too very s t don't can't won't isn't aren't
    what which who whom when where why how up down out off then once get got go going gonna want wanna know think really one two three
    let's lets make made see say said thing things now well still even back way much many need new good time
    """.split(whereSeparator: { $0.isWhitespace }).map(String.init))

    static func build(history: [Transcript], dictionary: [DictEntry]) -> Profile {
        var p = Profile()
        let items = history.filter { !$0.text.isEmpty && $0.raw != "demo" }
        p.dictations = items.count
        p.correctionsLearned = dictionary.filter { $0.learned == true }.count
        guard !items.isEmpty else { return p }

        var wordCounts: [String: Int] = [:]
        var properCounts: [String: Int] = [:]
        var fillerCounts: [String: Int] = [:]
        var totalWords = 0
        let known = Set(dictionary.map { $0.vocabularyTerm.lowercased() })

        for t in items.prefix(1500) {
            let words = t.text.split(whereSeparator: { $0.isWhitespace })
            totalWords += words.count
            // names & jargon: capitalized or mixed-case tokens that aren't starting a sentence
            var sentenceStart = true
            for w in words {
                let token = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"“”'‘’()[]"))
                defer { sentenceStart = w.last.map { ".!?\n".contains($0) } ?? false }
                guard token.count >= 2, let first = token.first else { continue }
                let lower = token.lowercased()
                if !stopWords.contains(lower) && token.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) {
                    wordCounts[lower, default: 0] += 1
                }
                let mixed = token.dropFirst().contains(where: { $0.isUppercase }) || token.contains(where: { $0.isNumber }) && token.contains(where: { $0.isLetter })
                let capitalized = first.isUppercase && !sentenceStart
                if (mixed || capitalized) && !["I", "I'm", "I'll", "I've", "I'd", "OK"].contains(token) && !stopWords.contains(lower) && !known.contains(lower) {
                    properCounts[token, default: 0] += 1
                }
            }
            let raw = " " + t.raw.lowercased().replacingOccurrences(of: #"[^\p{L}\s']"#, with: " ", options: .regularExpression) + " "
            for f in fillerWords {
                let n = raw.components(separatedBy: " \(f) ").count - 1
                if n > 0 { fillerCounts[f, default: 0] += n }
            }
        }
        p.avgWords = totalWords / max(1, items.count)
        p.learnedWords = properCounts.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.prefix(30).map(\.key)
        p.topWords = wordCounts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
        p.fillers = fillerCounts.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        return p
    }
}

/// After Fisper pastes, it peeks at the same text field a few times. If you fixed a word ("Ria" → "Priya"),
/// it adds that correction to your Dictionary so it's right next time. Only the field Fisper typed into is read.
@MainActor
final class EditLearner {
    var onLearn: ((_ heard: String, _ correct: String) -> Void)?
    private var generation = 0

    func watch(element: AXUIElement, location: Int, inserted: String) {
        generation += 1
        let gen = generation
        let words = Self.tokens(inserted)
        guard words.count >= 1, words.count <= 120 else { return }
        for delay in [6.0, 15.0, 30.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, gen == self.generation else { return }
                if self.check(element: element, location: location, inserted: inserted, words: words) { self.generation += 1 }
            }
        }
    }

    /// Returns true when the watch is finished (learned something or text is gone).
    private func check(element: AXUIElement, location: Int, inserted: String, words: [String]) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return true }
        let ns = value as NSString
        guard ns.length < 200_000 else { return true }
        let start = max(0, min(location, ns.length) - 10)
        let end = min(ns.length, location + (inserted as NSString).length + 80)
        guard end > start else { return true }
        let region = ns.substring(with: NSRange(location: start, length: end - start))
        if region.contains(inserted.trimmingCharacters(in: .whitespaces)) { return false } // unchanged so far
        guard let (heard, fixed) = Self.singleCorrection(original: words, edited: Self.tokens(region)) else { return false }
        onLearn?(heard, fixed)
        return true
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"“”()[]")) }.filter { !$0.isEmpty }
    }

    /// Word-level LCS diff; accepts exactly one small substitution that looks like a name/jargon fix.
    static func singleCorrection(original a: [String], edited b: [String]) -> (String, String)? {
        let la = a.map { $0.lowercased() }, lb = b.map { $0.lowercased() }
        let n = la.count, m = lb.count
        guard n > 0, m > 0, n <= 150, m <= 220 else { return nil }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = la[i] == lb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        guard dp[0][0] >= max(1, Int(Double(n) * 0.6)) else { return nil }
        // walk the alignment into runs of deletions/insertions between matching words
        struct Run { var del: [String] = []; var add: [String] = [] }
        var runs: [Run] = [Run()]
        var casing: [(String, String)] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n && j < m && la[i] == lb[j] {
                if a[i] != b[j] && b[j].contains(where: { $0.isUppercase }) { casing.append((a[i], b[j])) }
                if !(runs.last!.del.isEmpty && runs.last!.add.isEmpty) { runs.append(Run()) }
                i += 1; j += 1
            } else if j >= m || (i < n && dp[i + 1][j] >= dp[i][j + 1]) {
                runs[runs.count - 1].del.append(a[i]); i += 1
            } else {
                runs[runs.count - 1].add.append(b[j]); j += 1
            }
        }
        // text that was already there before us, or typed after us, shows up as insert-only runs: ignore those
        if runs.contains(where: { !$0.del.isEmpty && $0.add.isEmpty }) { return nil }   // words deleted → not a spelling fix
        let subs = runs.filter { !$0.del.isEmpty && !$0.add.isEmpty }.map { ($0.del, $0.add) }
        // a pure capitalization fix of a non-sentence-start word ("iphone" → "iPhone", "github" → "GitHub")
        if subs.isEmpty, casing.count == 1, let c = casing.first, c.1.dropFirst().contains(where: { $0.isUppercase }) || !Personalization.stopWords.contains(c.0.lowercased()) {
            return c.0.count >= 2 ? c : nil
        }
        guard subs.count == 1 else { return nil }
        let (oldW, newW) = subs[0]
        guard oldW.count <= 2, newW.count <= 3 else { return nil }
        let heard = oldW.joined(separator: " "), fixed = newW.joined(separator: " ")
        guard heard.lowercased() != fixed.lowercased() || heard != fixed else { return nil }
        // only learn things that look like vocabulary, not grammar edits ("the" → "a")
        let looksLikeVocab = fixed.contains(where: { $0.isUppercase || $0.isNumber }) || !Personalization.stopWords.contains(fixed.lowercased())
        guard looksLikeVocab, heard.count >= 2, fixed.count >= 2, !Personalization.stopWords.contains(heard.lowercased()) || heard.lowercased() == fixed.lowercased() else { return nil }
        return (heard, fixed)
    }
}
