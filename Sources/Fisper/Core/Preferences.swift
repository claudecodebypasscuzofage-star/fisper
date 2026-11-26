import Foundation
import SwiftUI

enum HotkeyChoice: String, CaseIterable, Identifiable, Codable {
    case fn, rightOption, rightCommand, controlOption
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fn: return "fn  (Globe)"
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .controlOption: return "⌃ Control + ⌥ Option"
        }
    }
    /// Short label for inline instructions.
    var keyLabel: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        case .controlOption: return "⌃ + ⌥"
        }
    }
}

enum PolishEngine: String, CaseIterable, Identifiable, Codable {
    case auto, apple, ollama, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .apple: return "Apple Intelligence (on-device)"
        case .ollama: return "Ollama (local LLM)"
        case .off: return "Off — rules only"
        }
    }
}

struct WhisperModelInfo: Identifiable, Hashable {
    let id: String          // file name
    let title: String
    let detail: String
    let sizeMB: Int
    let url: URL
    let multilingual: Bool

    static let all: [WhisperModelInfo] = [
        .init(id: "ggml-large-v3-turbo-q5_0.bin", title: "Whisper Turbo", detail: "Best accuracy, 99 languages. Recommended.", sizeMB: 574,
              url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!, multilingual: true),
        .init(id: "ggml-small.en-q5_1.bin", title: "Whisper Small (English)", detail: "Faster, very good for English.", sizeMB: 190,
              url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin")!, multilingual: false),
        .init(id: "ggml-base.en-q5_1.bin", title: "Whisper Base (English)", detail: "Fastest and lightest, less accurate.", sizeMB: 60,
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
    ("en", "English"), ("auto", "Auto-detect"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
    ("pt", "Portuguese"), ("nl", "Dutch"), ("ru", "Russian"), ("uk", "Ukrainian"), ("pl", "Polish"), ("tr", "Turkish"),
    ("ar", "Arabic"), ("hi", "Hindi"), ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean"), ("sv", "Swedish"),
]

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var hotkey: HotkeyChoice { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var modelID: String { didSet { d.set(modelID, forKey: "modelID") } }
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    @Published var polishEngine: PolishEngine { didSet { d.set(polishEngine.rawValue, forKey: "polishEngine") } }
    @Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
    @Published var removeFillers: Bool { didSet { d.set(removeFillers, forKey: "removeFillers") } }
    @Published var voiceCommands: Bool { didSet { d.set(voiceCommands, forKey: "voiceCommands") } }
    @Published var smartSpacing: Bool { didSet { d.set(smartSpacing, forKey: "smartSpacing") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    @Published var muteWhileDictating: Bool { didSet { d.set(muteWhileDictating, forKey: "muteWhileDictating") } }
    @Published var showIdleBar: Bool { didSet { d.set(showIdleBar, forKey: "showIdleBar") } }
    @Published var keepAudio: Bool { didSet { d.set(keepAudio, forKey: "keepAudio") } }
    @Published var restoreClipboard: Bool { didSet { d.set(restoreClipboard, forKey: "restoreClipboard") } }
    @Published var microphoneUID: String { didSet { d.set(microphoneUID, forKey: "microphoneUID") } }
    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }
    @Published var styles: [AppCategory: WritingStyle] {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value.rawValue) })
            d.set(raw, forKey: "styles")
        }
    }

    private init() {
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? .fn
        modelID = d.string(forKey: "modelID") ?? WhisperModelInfo.all[0].id
        language = d.string(forKey: "language") ?? "en"
        polishEngine = PolishEngine(rawValue: d.string(forKey: "polishEngine") ?? "") ?? .auto
        ollamaModel = d.string(forKey: "ollamaModel") ?? "qwen2.5:3b"
        removeFillers = d.object(forKey: "removeFillers") as? Bool ?? true
        voiceCommands = d.object(forKey: "voiceCommands") as? Bool ?? true
        smartSpacing = d.object(forKey: "smartSpacing") as? Bool ?? true
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        muteWhileDictating = d.object(forKey: "muteWhileDictating") as? Bool ?? false
        showIdleBar = d.object(forKey: "showIdleBar") as? Bool ?? true
        keepAudio = d.object(forKey: "keepAudio") as? Bool ?? true
        restoreClipboard = d.object(forKey: "restoreClipboard") as? Bool ?? true
        microphoneUID = d.string(forKey: "microphoneUID") ?? ""
        onboarded = d.bool(forKey: "onboarded")
        var s: [AppCategory: WritingStyle] = [.personal: .casual, .work: .casual, .email: .formal, .other: .formal]
        if let raw = d.dictionary(forKey: "styles") as? [String: String] {
            for (k, v) in raw { if let c = AppCategory(rawValue: k), let st = WritingStyle(rawValue: v) { s[c] = st } }
        }
        styles = s
    }

    func style(for category: AppCategory) -> WritingStyle { styles[category] ?? .formal }
}
