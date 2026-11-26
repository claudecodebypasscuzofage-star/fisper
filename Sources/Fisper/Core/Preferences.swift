import Foundation
import SwiftUI

enum PolishEngine: String, CaseIterable, Identifiable, Codable {
    case auto, apple, ollama, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .apple: return "Apple Intelligence"
        case .ollama: return "Ollama"
        case .off: return "Off (rules only)"
        }
    }
}

enum CorrectionLevel: String, CaseIterable, Identifiable, Codable {
    case light, balanced, polished
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "Light"
        case .balanced: return "Balanced"
        case .polished: return "Polished"
        }
    }
    var detail: String {
        switch self {
        case .light: return "Punctuation, capitalization and filler words only. Your exact words."
        case .balanced: return "Also fixes grammar, applies self-corrections and formats lists."
        case .polished: return "Also smooths awkward phrasing so it reads like you wrote it."
        }
    }
}

enum NoiseMode: String, CaseIterable, Identifiable, Codable {
    case off, light, auto, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .auto: return "Automatic"
        case .always: return "Always isolate voice"
        }
    }
    var detail: String {
        switch self {
        case .off: return "Raw microphone audio."
        case .light: return "Filters rumble, hum and desk bumps."
        case .auto: return "Isolates your voice when Fisper detects background noise."
        case .always: return "Always removes background noise, music and chatter."
        }
    }
}

enum PasteMethod: String, CaseIterable, Identifiable, Codable {
    case paste, type, clipboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .paste: return "Paste (fastest)"
        case .type: return "Type it out"
        case .clipboard: return "Copy to clipboard only"
        }
    }
}

enum BarPosition: String, CaseIterable, Identifiable, Codable {
    case bottom, top
    var id: String { rawValue }
    var title: String { self == .bottom ? "Bottom" : "Top" }
}

enum IdleBarMode: String, CaseIterable, Identifiable, Codable {
    case dictating, nearby, always
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictating: return "Only while dictating"
        case .nearby: return "When the pointer is near it"
        case .always: return "Always"
        }
    }
}

enum BarStyle: String, CaseIterable, Identifiable, Codable {
    case glass, midnight
    var id: String { rawValue }
    var title: String { self == .glass ? "Liquid Glass" : "Midnight" }
}

/// A color that can be stored in UserDefaults.
struct RGBAColor: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ c: Color) {
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        r = Double(n.redComponent); g = Double(n.greenComponent); b = Double(n.blueComponent); a = Double(n.alphaComponent)
    }
    static let midnight = RGBAColor(r: 0.043, g: 0.043, b: 0.047)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let forest = RGBAColor(r: 0.059, g: 0.42, b: 0.36)
}

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AccentChoice: String, CaseIterable, Identifiable, Codable {
    case forest, system, blue, purple, pink, orange, graphite, custom
    var id: String { rawValue }
    var title: String { rawValue == "system" ? "System" : rawValue.capitalized }
    @MainActor var color: Color {
        switch self {
        case .custom: return Preferences.shared.customAccent.color
        case .forest: return Color(hex: 0x0F6B5C)
        case .system: return .accentColor
        case .blue: return Color(hex: 0x0A84FF)
        case .purple: return Color(hex: 0x8E5CF6)
        case .pink: return Color(hex: 0xE5407E)
        case .orange: return Color(hex: 0xF0802E)
        case .graphite: return Color(hex: 0x6E6E73)
        }
    }
}

enum Retention: Int, CaseIterable, Identifiable, Codable {
    case forever = 0, days90 = 90, days30 = 30, days7 = 7, never = -1
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .forever: return "Forever"
        case .days90: return "90 days"
        case .days30: return "30 days"
        case .days7: return "7 days"
        case .never: return "Don't keep history"
        }
    }
}

struct WhisperModelInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let sizeMB: Int
    let url: URL
    let multilingual: Bool

    static let all: [WhisperModelInfo] = [
        .init(id: "ggml-large-v3-turbo-q5_0.bin", title: "Whisper Turbo", detail: "Best accuracy · 99 languages", sizeMB: 574,
              url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!, multilingual: true),
        .init(id: "ggml-large-v3-turbo-q8_0.bin", title: "Whisper Turbo HQ", detail: "Slightly more accurate, more memory", sizeMB: 874,
              url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin")!, multilingual: true),
        .init(id: "ggml-small.en-q5_1.bin", title: "Whisper Small", detail: "Faster · English only", sizeMB: 190,
              url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin")!, multilingual: false),
        .init(id: "ggml-base.en-q5_1.bin", title: "Whisper Base", detail: "Fastest & lightest · English only", sizeMB: 60,
              url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q5_1.bin")!, multilingual: false),
    ]
    static func info(for id: String) -> WhisperModelInfo { all.first { $0.id == id } ?? all[0] }
    var localURL: URL { Paths.models.appendingPathComponent(id) }
    var isDownloaded: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path),
              let size = attrs[.size] as? Int else { return false }
        return size > sizeMB * 1_000_000 * 9 / 10
    }
}

let supportedLanguages: [(code: String, name: String)] = [
    ("en", "English"), ("auto", "Detect automatically"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
    ("pt", "Portuguese"), ("nl", "Dutch"), ("ru", "Russian"), ("uk", "Ukrainian"), ("pl", "Polish"), ("tr", "Turkish"),
    ("ar", "Arabic"), ("he", "Hebrew"), ("hi", "Hindi"), ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean"),
    ("sv", "Swedish"), ("da", "Danish"), ("no", "Norwegian"), ("fi", "Finnish"), ("cs", "Czech"), ("ro", "Romanian"),
    ("el", "Greek"), ("vi", "Vietnamese"), ("id", "Indonesian"), ("th", "Thai"),
]

/// All user settings, persisted to UserDefaults. Each property writes itself on change.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    // Shortcut & behaviour
    @Published var hotkey: Shortcut { didSet { saveShortcut(hotkey, "shortcut") } }
    @Published var pasteLastShortcut: Shortcut? { didSet { saveShortcut(pasteLastShortcut, "pasteLastShortcut") } }
    @Published var toggleShortcut: Shortcut? { didSet { saveShortcut(toggleShortcut, "toggleShortcut") } }
    @Published var doubleTapHandsFree: Bool { didSet { save(doubleTapHandsFree, "doubleTapHandsFree") } }
    @Published var spaceLocksHandsFree: Bool { didSet { save(spaceLocksHandsFree, "spaceLocksHandsFree") } }
    @Published var minHoldSeconds: Double { didSet { save(minHoldSeconds, "minHoldSeconds") } }
    @Published var maxRecordingMinutes: Double { didSet { save(maxRecordingMinutes, "maxRecordingMinutes") } }
    @Published var excludedApps: [String] { didSet { save(excludedApps, "excludedApps") } }

    // Output
    @Published var pasteMethod: PasteMethod { didSet { save(pasteMethod.rawValue, "pasteMethod") } }
    @Published var restoreClipboard: Bool { didSet { save(restoreClipboard, "restoreClipboard") } }
    @Published var smartSpacing: Bool { didSet { save(smartSpacing, "smartSpacing") } }
    @Published var addTrailingSpace: Bool { didSet { save(addTrailingSpace, "addTrailingSpace") } }
    @Published var pressReturnAfter: Bool { didSet { save(pressReturnAfter, "pressReturnAfter") } }

    // Speech recognition
    @Published var modelID: String { didSet { save(modelID, "modelID") } }
    @Published var language: String { didSet { save(language, "language") } }
    @Published var fastMode: Bool { didSet { save(fastMode, "fastMode") } }
    @Published var streaming: Bool { didSet { save(streaming, "streaming") } }

    // Audio
    @Published var microphoneUID: String { didSet { save(microphoneUID, "microphoneUID") } }
    @Published var noiseMode: NoiseMode { didSet { save(noiseMode.rawValue, "noiseMode") } }
    @Published var isolationStrength: Double { didSet { save(isolationStrength, "isolationStrength") } }
    @Published var boostQuietSpeech: Bool { didSet { save(boostQuietSpeech, "boostQuietSpeech") } }
    @Published var muteWhileDictating: Bool { didSet { save(muteWhileDictating, "muteWhileDictating") } }

    // Writing
    @Published var polishEngine: PolishEngine { didSet { save(polishEngine.rawValue, "polishEngine") } }
    @Published var ollamaModel: String { didSet { save(ollamaModel, "ollamaModel") } }
    @Published var correctionLevel: CorrectionLevel { didSet { save(correctionLevel.rawValue, "correctionLevel") } }
    @Published var customInstructions: String { didSet { save(customInstructions, "customInstructions") } }
    @Published var removeFillers: Bool { didSet { save(removeFillers, "removeFillers") } }
    @Published var voiceCommands: Bool { didSet { save(voiceCommands, "voiceCommands") } }
    @Published var formatLists: Bool { didSet { save(formatLists, "formatLists") } }
    @Published var numbersAsDigits: Bool { didSet { save(numbersAsDigits, "numbersAsDigits") } }
    @Published var styles: [AppCategory: WritingStyle] {
        didSet { save(Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value.rawValue) }), "styles") }
    }

    // Appearance & sound
    @Published var accent: AccentChoice { didSet { save(accent.rawValue, "accent") } }
    @Published var customAccent: RGBAColor { didSet { saveCodable(customAccent, "customAccent") } }
    @Published var appearance: AppAppearance { didSet { save(appearance.rawValue, "appearance"); applyAppearance() } }
    @Published var barColor: RGBAColor { didSet { saveCodable(barColor, "barColor") } }
    @Published var waveColor: RGBAColor { didSet { saveCodable(waveColor, "waveColor") } }
    @Published var barOpacity: Double { didSet { save(barOpacity, "barOpacity") } }

    // Personalization
    @Published var learnFromEdits: Bool { didSet { save(learnFromEdits, "learnFromEdits") } }
    @Published var learnVocabulary: Bool { didSet { save(learnVocabulary, "learnVocabulary") } }
    @Published var matchMyStyle: Bool { didSet { save(matchMyStyle, "matchMyStyle") } }
    @Published var smartSkipAI: Bool { didSet { save(smartSkipAI, "smartSkipAI") } }
    @Published var idleBar: IdleBarMode { didSet { save(idleBar.rawValue, "idleBar") } }
    var showIdleBar: Bool { idleBar != .dictating }
    @Published var barPosition: BarPosition { didSet { save(barPosition.rawValue, "barPosition") } }
    /// Where the user dragged the flow bar, as fractions of the screen's visible frame (center point). nil = preset position.
    @Published var barCustomPosition: CGPoint? {
        didSet {
            if let p = barCustomPosition { save([p.x, p.y], "barCustomPosition") } else { d.removeObject(forKey: "barCustomPosition") }
        }
    }
    @Published var barStyle: BarStyle { didSet { save(barStyle.rawValue, "barStyle") } }
    @Published var barScale: Double { didSet { save(barScale, "barScale") } }
    @Published var playSounds: Bool { didSet { save(playSounds, "playSounds") } }
    @Published var soundVolume: Double { didSet { save(soundVolume, "soundVolume") } }
    @Published var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }

    // Privacy
    @Published var retention: Retention { didSet { save(retention.rawValue, "retention") } }
    @Published var keepAudio: Bool { didSet { save(keepAudio, "keepAudio") } }

    @Published var onboarded: Bool { didSet { save(onboarded, "onboarded") } }

    private func save(_ v: Any, _ k: String) { d.set(v, forKey: k) }
    private func saveCodable<T: Encodable>(_ v: T, _ k: String) { if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: k) } }
    private static func loadCodable<T: Decodable>(_ d: UserDefaults, _ k: String) -> T? {
        guard let data = d.data(forKey: k) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func applyAppearance() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
    private func saveShortcut(_ s: Shortcut?, _ k: String) {
        if let s, let data = try? JSONEncoder().encode(s) { d.set(data, forKey: k) } else { d.set(Data(), forKey: k) }
    }
    private static func loadShortcut(_ d: UserDefaults, _ k: String) -> Shortcut?? {
        guard let data = d.data(forKey: k) else { return nil }          // never set
        if data.isEmpty { return .some(nil) }                            // explicitly disabled
        return .some(try? JSONDecoder().decode(Shortcut.self, from: data))
    }
    private func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private func double(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
    private func str(_ k: String) -> String { d.string(forKey: k) ?? "" }

    private init() {
        hotkey = (Self.loadShortcut(d, "shortcut") ?? nil) ?? Shortcut.legacy(d.string(forKey: "hotkey") ?? "") ?? .fnKey
        pasteLastShortcut = Self.loadShortcut(d, "pasteLastShortcut") ?? .defaultPasteLast
        toggleShortcut = Self.loadShortcut(d, "toggleShortcut") ?? nil
        doubleTapHandsFree = d.object(forKey: "doubleTapHandsFree") as? Bool ?? true
        spaceLocksHandsFree = d.object(forKey: "spaceLocksHandsFree") as? Bool ?? true
        minHoldSeconds = d.object(forKey: "minHoldSeconds") as? Double ?? 0.28
        maxRecordingMinutes = d.object(forKey: "maxRecordingMinutes") as? Double ?? 10
        excludedApps = d.stringArray(forKey: "excludedApps") ?? []

        pasteMethod = PasteMethod(rawValue: d.string(forKey: "pasteMethod") ?? "") ?? .paste
        restoreClipboard = d.object(forKey: "restoreClipboard") as? Bool ?? true
        smartSpacing = d.object(forKey: "smartSpacing") as? Bool ?? true
        addTrailingSpace = d.object(forKey: "addTrailingSpace") as? Bool ?? false
        pressReturnAfter = d.object(forKey: "pressReturnAfter") as? Bool ?? false

        modelID = d.string(forKey: "modelID") ?? WhisperModelInfo.all[0].id
        language = d.string(forKey: "language") ?? "en"
        fastMode = d.object(forKey: "fastMode") as? Bool ?? true
        streaming = d.object(forKey: "streaming") as? Bool ?? true

        microphoneUID = d.string(forKey: "microphoneUID") ?? ""
        noiseMode = NoiseMode(rawValue: d.string(forKey: "noiseMode") ?? "") ?? .auto
        isolationStrength = d.object(forKey: "isolationStrength") as? Double ?? 0.85
        boostQuietSpeech = d.object(forKey: "boostQuietSpeech") as? Bool ?? true
        muteWhileDictating = d.object(forKey: "muteWhileDictating") as? Bool ?? false

        polishEngine = PolishEngine(rawValue: d.string(forKey: "polishEngine") ?? "") ?? .auto
        ollamaModel = d.string(forKey: "ollamaModel") ?? "qwen2.5:3b"
        correctionLevel = CorrectionLevel(rawValue: d.string(forKey: "correctionLevel") ?? "") ?? .balanced
        customInstructions = d.string(forKey: "customInstructions") ?? ""
        removeFillers = d.object(forKey: "removeFillers") as? Bool ?? true
        voiceCommands = d.object(forKey: "voiceCommands") as? Bool ?? true
        formatLists = d.object(forKey: "formatLists") as? Bool ?? true
        numbersAsDigits = d.object(forKey: "numbersAsDigits") as? Bool ?? false
        var s: [AppCategory: WritingStyle] = [.personal: .casual, .work: .casual, .email: .formal, .other: .formal]
        if let raw = d.dictionary(forKey: "styles") as? [String: String] {
            for (k, v) in raw { if let c = AppCategory(rawValue: k), let st = WritingStyle(rawValue: v) { s[c] = st } }
        }
        styles = s

        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .forest
        customAccent = Self.loadCodable(d, "customAccent") ?? .forest
        appearance = AppAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        barColor = Self.loadCodable(d, "barColor") ?? .midnight
        waveColor = Self.loadCodable(d, "waveColor") ?? .white
        barOpacity = d.object(forKey: "barOpacity") as? Double ?? 0.82
        learnFromEdits = d.object(forKey: "learnFromEdits") as? Bool ?? true
        learnVocabulary = d.object(forKey: "learnVocabulary") as? Bool ?? true
        matchMyStyle = d.object(forKey: "matchMyStyle") as? Bool ?? true
        smartSkipAI = d.object(forKey: "smartSkipAI") as? Bool ?? true
        idleBar = IdleBarMode(rawValue: d.string(forKey: "idleBar") ?? "") ?? .dictating
        barPosition = BarPosition(rawValue: d.string(forKey: "barPosition") ?? "") ?? .bottom
        if let a = d.array(forKey: "barCustomPosition") as? [Double], a.count == 2 { barCustomPosition = CGPoint(x: a[0], y: a[1]) }
        barStyle = BarStyle(rawValue: d.string(forKey: "barStyle") ?? "") ?? .glass
        barScale = d.object(forKey: "barScale") as? Double ?? 1.0
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        soundVolume = d.object(forKey: "soundVolume") as? Double ?? 0.7
        showMenuBarIcon = d.object(forKey: "showMenuBarIcon") as? Bool ?? true

        retention = Retention(rawValue: d.object(forKey: "retention") as? Int ?? 0) ?? .forever
        keepAudio = d.object(forKey: "keepAudio") as? Bool ?? true
        onboarded = d.bool(forKey: "onboarded")
    }

    func style(for category: AppCategory) -> WritingStyle { styles[category] ?? .formal }

    func resetAll() {
        for key in d.dictionaryRepresentation().keys where !key.hasPrefix("NS") && key != "onboarded" { d.removeObject(forKey: key) }
    }

    var enhancerOptions: AudioEnhancer.Options {
        .init(noise: noiseMode, strength: Float(isolationStrength), normalize: boostQuietSpeech)
    }
}
