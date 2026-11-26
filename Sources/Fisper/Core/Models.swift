import Foundation
import AppKit

// MARK: - Paths

enum Paths {
    static let realSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fisper", isDirectory: true)
    /// FISPER_DATA_DIR overrides where history/dictionary live (used by the screenshot renderer and tests).
    static let support: URL = {
        let dir = ProcessInfo.processInfo.environment["FISPER_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? realSupport
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let models: URL = {
        let dir = realSupport.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let audio: URL = {
        let dir = support.appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let history = support.appendingPathComponent("history.json")
    static let dictionary = support.appendingPathComponent("dictionary.json")
    static let snippets = support.appendingPathComponent("snippets.json")
    static let log = support.appendingPathComponent("fisper.log")
}

// MARK: - Demo mode (screenshots for docs never show the real user's name or devices)

enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["FISPER_DEMO"] == "1"
    static var firstName: String {
        isOn ? "Alex" : (NSFullUserName().split(separator: " ").first.map(String.init) ?? "there")
    }
}

// MARK: - Logging

enum Log {
    private static let queue = DispatchQueue(label: "fisper.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    static func info(_ msg: String) {
        let line = "[\(formatter.string(from: Date()))] \(msg)\n"
        #if DEBUG
        FileHandle.standardError.write(line.data(using: .utf8)!)
        #endif
        queue.async {
            if let h = try? FileHandle(forWritingTo: Paths.log) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            } else {
                try? line.data(using: .utf8)!.write(to: Paths.log)
            }
        }
    }
    static func trim() {
        queue.async {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.log.path),
                  let size = attrs[.size] as? Int, size > 2_000_000 else { return }
            try? FileManager.default.removeItem(at: Paths.log)
        }
    }
}

// MARK: - Transcript history

struct Transcript: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var text: String
    var raw: String
    var appName: String?
    var bundleID: String?
    var duration: Double          // seconds of speech audio
    var latencyMs: Int = 0        // release -> paste
    var audioFile: String?        // file name inside Paths.audio
    var polishedBy: String?       // "Apple Intelligence", "Ollama", "Rules"
    var words: Int { text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }
}

// MARK: - Dictionary & snippets

struct DictEntry: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var word: String              // canonical spelling, or the "heard" text when replacement is set
    var replacement: String?      // if set: "word" -> "replacement"
    var created = Date()
    var learned: Bool? = nil      // added automatically from the user's own corrections
    var isCorrection: Bool { !(replacement ?? "").isEmpty }
    /// The word Whisper should be biased toward.
    var vocabularyTerm: String { isCorrection ? replacement! : word }
}

struct Snippet: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var trigger: String
    var expansion: String
    var created = Date()
}

// MARK: - Generic JSON store

@MainActor
final class JSONStore<T: Codable>: ObservableObject {
    @Published var items: [T] { didSet { scheduleSave() } }
    private let url: URL
    private var saveWork: DispatchWorkItem?

    init(url: URL, defaultItems: [T] = []) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let decoded = try? dec.decode([T].self, from: data) {
                self.items = decoded
                return
            }
            // keep a backup of an unreadable file instead of silently overwriting it
            try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("bak-\(Int(Date().timeIntervalSince1970))"))
        }
        self.items = defaultItems
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = items
        let url = self.url
        let work = DispatchWorkItem {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
            if let data = try? enc.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func flush() {
        saveWork?.perform()
    }
}

// MARK: - App categories (for Style)

enum AppCategory: String, CaseIterable, Codable, Identifiable {
    case personal, work, email, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .personal: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }
    var shortTitle: String {
        switch self {
        case .personal: return "PERSONAL"
        case .work: return "WORK"
        case .email: return "EMAIL"
        case .other: return "OTHER"
        }
    }
    var subtitle: String {
        switch self {
        case .personal: return "Messages, WhatsApp, Telegram, Signal, Discord"
        case .work: return "Slack, Teams, Linear, Notion comments"
        case .email: return "Mail, Outlook, Spark, Superhuman"
        case .other: return "Docs, notes, AI chats, code editors and everything else"
        }
    }
    var icon: String {
        switch self {
        case .personal: return "message"
        case .work: return "bubble.left.and.text.bubble.right"
        case .email: return "envelope"
        case .other: return "doc.text"
        }
    }

    static func of(bundleID: String?) -> AppCategory {
        guard let b = bundleID?.lowercased() else { return .other }
        let personal = ["com.apple.mobilesms", "net.whatsapp.whatsapp", "com.whatsapp", "ru.keepcoder.telegram", "org.telegram.desktop",
                        "org.whispersystems.signal-desktop", "com.hnc.discord", "com.facebook.archon", "com.facebook.messenger", "com.tdesktop.telegram"]
        let work = ["com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.microsoft.teams2", "com.linear", "com.figma.desktop", "us.zoom.xos"]
        let email = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac", "com.superhuman.electron", "com.mimestream.mimestream",
                     "com.airmailapp.airmail2", "it.bloop.airmail2"]
        if personal.contains(where: { b.hasPrefix($0) }) { return .personal }
        if work.contains(where: { b.hasPrefix($0) }) { return .work }
        if email.contains(where: { b.hasPrefix($0) }) { return .email }
        return .other
    }
}

enum WritingStyle: String, CaseIterable, Codable, Identifiable {
    case formal, casual, veryCasual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .formal: return "Formal."
        case .casual: return "Casual"
        case .veryCasual: return "very casual"
        }
    }
    var caption: String {
        switch self {
        case .formal: return "Caps + Punctuation"
        case .casual: return "Caps + Less punctuation"
        case .veryCasual: return "No Caps + Less punctuation"
        }
    }
    var example: String {
        switch self {
        case .formal: return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case .casual: return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        case .veryCasual: return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
        }
    }
}
