import Foundation

/// Deterministic text clean-up. Always runs — before and after the optional AI pass — so output is good even with AI off.
enum TextCleaner {

    // MARK: Hallucination / noise filtering

    private static let hallucinations: Set<String> = [
        "thank you", "thank you.", "thanks for watching", "thanks for watching!", "thank you for watching", "thank you for watching.",
        "you", "you.", "bye", "bye.", "bye!", "okay.", "so", "the end", "subscribe", "please subscribe", ".", "uh", "um", "hmm",
        "thanks.", "thank you so much.", "i'm sorry.", "music", "applause", "silence",
        "thanks for watching and see you next time", "please like and subscribe", "see you next time",
        "gracias por ver el video", "gracias por ver", "subtítulos realizados por la comunidad de amaraorg",
        "sous-titres réalisés para la communauté damaraorg", "untertitel der amaraorg-community", "untertitel im auftrag des zdf",
        "продолжение следует", "субтитры сделал dimatorzok", "ご視聴ありがとうございました",
    ]

    static func stripNoise(_ text: String) -> String {
        var t = text
        // [BLANK_AUDIO], (music), *laughs*, ♪ ...
        t = t.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*(music|applause|silence|laugh|noise|blank|inaudible|sigh|cough)[^)]*\)|\*[^*]{1,30}\*|♪+|♫+"#,
                                   with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper tends to invent stock phrases for near-silent clips.
    static func isLikelyHallucination(_ text: String, voicedSeconds: Double) -> Bool {
        let n = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if n.isEmpty { return true }
        // classic subtitle-credit hallucinations are never real dictation, regardless of length
        let squashed = n.replacingOccurrences(of: ".", with: "")
        if ["amaraorg", "subtítulos", "sous-titres", "untertitel", "субтитры", "ご視聴"].contains(where: { squashed.contains($0) }) { return true }
        if voicedSeconds < 2.5 && hallucinations.contains(squashed) { return true }
        if voicedSeconds < 1.2 && hallucinations.contains(n) { return true }
        if voicedSeconds < 1.2 && hallucinations.contains(n + ".") { return true }
        return false
    }

    // MARK: Repetition (Whisper decoding loops)

    private static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if ".!?\n".contains(ch) { out.append(cur); cur = "" }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    private static func key(_ s: String) -> String { normalizeForMatch(s) }

    static func hasRepetitionLoop(_ text: String) -> Bool {
        let ss = sentences(text).map(key).filter { !$0.isEmpty }
        guard ss.count >= 3 else { return false }
        var run = 1
        for i in 1..<ss.count {
            run = ss[i] == ss[i - 1] ? run + 1 : 1
            if run >= 3 { return true }
        }
        // the same phrase repeated many times anywhere
        let counts = Dictionary(ss.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.values.contains { $0 >= 4 }
    }

    /// Drop consecutive duplicate sentences ("Thanks so much. Thanks so much.") and a doubled opening word ("Hey. Hey, …").
    static func dedupeRepeats(_ text: String) -> String {
        var out: [String] = []
        for s in sentences(text) {
            if let last = out.last, key(last) == key(s), !key(s).isEmpty { continue }
            out.append(s)
        }
        var t = out.joined()
        t = t.replacingOccurrences(of: #"(?i)^(\w+)[.!,]\s+\1\b,?"#, with: "$1,", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Main rule pass

    static func clean(_ input: String, removeFillers: Bool, voiceCommands: Bool) -> String {
        var t = stripNoise(input)
        if t.isEmpty { return t }
        t = dedupeRepeats(t)

        if removeFillers {
            // um / uh / er / erm / ah / hmm (with trailing punctuation), not touching real words
            t = t.replacingOccurrences(of: #"(?i)(^|[\s,])(u+m+|u+h+|e+r+m+|e+h+|a+h+|h+m+|m+h*m+|uh-huh)(?=[\s,.!?]|$)[,]?"#,
                                       with: "$1", options: .regularExpression)
            // stutters: "the the", "I I", "to to" (keep legit doubles like "that that", "had had")
            t = t.replacingOccurrences(of: #"(?i)\b(?!that\b|had\b|is\b)(\w+)(\s+\1\b)+"#, with: "$1", options: .regularExpression)
        }

        if voiceCommands {
            t = applyVoiceCommands(t)
        }

        t = fixSpacing(t)
        t = capitalizeSentences(t)
        return t
    }

    static func applyVoiceCommands(_ text: String) -> String {
        var t = text
        // "new paragraph" / "new line" when spoken as a command (bounded by punctuation or the edges)
        t = t.replacingOccurrences(of: #"(?i)(^|[.!?,;:]\s*|\s)new paragraph[.!?,;:]?(\s+|$)"#, with: "$1\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)(^|[.!?,;:]\s*)next line[.!?,;:]?(\s+|$)"#, with: "$1\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)(^|[.!?,;:]\s*)new line[.!?,;:]?(\s+|$)"#, with: "$1\n", options: .regularExpression)
        // trailing commas/spaces before newlines
        t = t.replacingOccurrences(of: #"[ \t,]+\n"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        return t
    }

    static func fixSpacing(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #",\s*([.!?])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[\s,.;:]+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #",{2,}"#, with: ",", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\.{4,}"#, with: "...", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// "Yo, Are you there?" → "Yo, are you there?" (only for common words, so names stay capitalized)
    static func fixCapsAfterComma(_ text: String) -> String {
        var t = text
        let re = try! NSRegularExpression(pattern: #",\s+([A-Z][a-z']+)\b"#)
        for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
            guard let r = Range(m.range(at: 1), in: t) else { continue }
            let w = String(t[r])
            if commonLowerStarts.contains(w.lowercased()) && w != "I" { t.replaceSubrange(r, with: w.lowercased()) }
        }
        return t
    }

    static func capitalizeSentences(_ text: String) -> String {
        var chars = Array(text)
        var capNext = true
        for i in chars.indices {
            let c = chars[i]
            if capNext, c.isLetter {
                // don't capitalize things that look like URLs, handles or code ("iPhone", "eBay" are left alone too)
                let rest = String(chars[i..<min(chars.count, i + 12)])
                let looksSpecial = rest.hasPrefix("http") || rest.hasPrefix("www.") ||
                    (chars.count > i + 1 && chars[i + 1].isUppercase)
                if !looksSpecial { chars[i] = Character(c.uppercased()) }
                capNext = false
            } else if c == "." || c == "!" || c == "?" || c == "\n" {
                // "e.g." / decimals / domains: only treat as sentence end if followed by whitespace
                if c == "\n" || (i + 1 < chars.count && chars[i + 1].isWhitespace) { capNext = true }
            } else if !c.isWhitespace && !"\"'“‘(-•".contains(c) {
                capNext = false
            }
        }
        var s = String(chars)
        // standalone "i" -> "I"
        s = s.replacingOccurrences(of: #"(?<![\w'])i(?=('m|'d|'ll|'ve|\b))(?![\w.-]*\.(com|org|io))"#, with: "I", options: .regularExpression)
        return s
    }

    // MARK: Style (per app category)

    static func applyStyle(_ text: String, _ style: WritingStyle) -> String {
        switch style {
        case .formal:
            return text
        case .casual:
            return casualize(text)
        case .veryCasual:
            var t = casualize(text)
            // lowercase sentence starts (keep "I", acronyms and proper-looking mid-sentence words)
            var chars = Array(t)
            var start = true
            for i in chars.indices {
                let c = chars[i]
                if start, c.isLetter {
                    let nextIsUpper = i + 1 < chars.count && chars[i + 1].isUppercase
                    let isI = c == "I" && (i + 1 >= chars.count || !chars[i + 1].isLetter)
                    if !nextIsUpper && !isI { chars[i] = Character(c.lowercased()) }
                    start = false
                } else if ".!?\n".contains(c) {
                    start = true
                } else if !c.isWhitespace {
                    start = false
                }
            }
            t = String(chars)
            return t
        }
    }

    private static func casualize(_ text: String) -> String {
        var t = text
        // "Hey, are you…" -> "Hey are you…"
        t = t.replacingOccurrences(of: #"(?i)^(hey|hi|hello|yo|ok|okay|so|well|yeah|yes|no)\s*,\s*"#, with: "$1 ", options: .regularExpression)
        // drop a single trailing period (keep ? and !)
        if t.hasSuffix(".") && !t.hasSuffix("...") { t.removeLast() }
        return t
    }

    // MARK: Dictionary & snippets

    static func applyDictionary(_ text: String, entries: [DictEntry]) -> String {
        var t = text
        // explicit corrections first (longest first so "Mac OS X" wins over "Mac OS")
        for e in entries.filter(\.isCorrection).sorted(by: { $0.word.count > $1.word.count }) {
            let pattern = "(?i)(?<![\\w])" + NSRegularExpression.escapedPattern(for: e.word) + "(?![\\w])"
            t = t.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: e.replacement!), options: .regularExpression)
        }
        // vocabulary words: enforce the user's casing ("macos" -> "macOS")
        for e in entries where !e.isCorrection && e.word.count > 1 {
            let pattern = "(?i)(?<![\\w])" + NSRegularExpression.escapedPattern(for: e.word) + "(?![\\w])"
            t = t.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: e.word), options: .regularExpression)
        }
        return t
    }

    /// Normalize for comparing a spoken phrase with a snippet trigger.
    static func normalizeForMatch(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// If the whole utterance is a snippet trigger, return the expansion verbatim.
    static func exactSnippet(_ text: String, snippets: [Snippet]) -> String? {
        let n = normalizeForMatch(text)
        return snippets.first { normalizeForMatch($0.trigger) == n && !n.isEmpty }?.expansion
    }

    static func expandSnippets(_ text: String, snippets: [Snippet]) -> String {
        var t = text
        for s in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let words = normalizeForMatch(s.trigger).split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty else { continue }
            // tolerate punctuation/quotes between the words of the trigger
            let pattern = "(?i)[\"“']?(?<![\\w])" + words.joined(separator: "[\\s,.\"'“”-]+") + "(?![\\w])[\"”']?"
            t = t.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: s.expansion), options: .regularExpression)
        }
        return t
    }

    // MARK: Smart insertion

    private static let commonLowerStarts: Set<String> = [
        "the", "a", "an", "and", "but", "so", "then", "it", "it's", "we", "we're", "you", "you're", "they", "they're", "this", "that",
        "to", "of", "in", "for", "with", "on", "at", "my", "our", "your", "their", "also", "because", "which", "when", "if", "or", "as",
        "is", "are", "was", "were", "be", "have", "has", "can", "will", "would", "should", "could", "just", "not", "maybe", "actually",
        "there", "here", "what", "how", "why", "who", "where", "all", "some", "more", "from", "by", "about", "into", "like", "even",
        "still", "now", "only", "very", "really", "please", "thanks", "let's", "do", "does", "did", "get", "got", "make", "see",
    ]

    /// Adjust text for the characters right before the cursor (leading space, mid-sentence lowercase).
    static func adaptToContext(_ text: String, before: String?) -> String {
        guard let before, !text.isEmpty else { return text }
        guard let prev = before.last else { return text }
        var t = text
        let prevNonSpace = before.last(where: { !$0.isWhitespace })
        let midSentence = prevNonSpace != nil && !".!?:\n".contains(prevNonSpace!) && !(prevNonSpace!.isPunctuation && prevNonSpace! != ",")
        if midSentence, let firstWord = t.split(separator: " ").first {
            let w = firstWord.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if commonLowerStarts.contains(w), let f = t.first, f.isUppercase {
                t = f.lowercased() + t.dropFirst()
            }
        }
        if !prev.isWhitespace && !"([{\"'“‘/@#\n".contains(prev) && !(t.first.map { ",.;:!?)".contains($0) } ?? false) {
            t = " " + t
        }
        return t
    }
}
