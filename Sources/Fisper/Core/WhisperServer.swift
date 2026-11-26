import Foundation
import Darwin

/// Runs a bundled whisper.cpp server (Metal-accelerated) as a child process and keeps the model warm in memory.
/// Crash-isolated: if the engine dies it is restarted automatically.
@MainActor
final class WhisperServer: ObservableObject {
    enum State: Equatable {
        case stopped, starting, ready, failed(String), missingModel
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var loadedModelID: String?

    private var process: Process?
    private var port: Int = 0
    private var intentionalStop = false
    private var restartAttempts = 0
    private var modelID: String = ""
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.connectionProxyDictionary = [:]  // never route localhost through a proxy
        return URLSession(configuration: cfg)
    }()

    static var binaryURL: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/whisper-server"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("whisper-server"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("vendor/whisper-server"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isReady: Bool { state == .ready }

    func start(modelID: String) {
        self.modelID = modelID
        let model = WhisperModelInfo.info(for: modelID)
        guard model.isDownloaded else { state = .missingModel; return }
        guard let bin = Self.binaryURL else { state = .failed("Speech engine binary is missing from the app bundle"); return }
        stopProcess()
        intentionalStop = false
        state = .starting

        port = Self.freePort()
        let p = Process()
        p.executableURL = bin
        let threads = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount / 2))
        p.arguments = ["-m", model.localURL.path, "--host", "127.0.0.1", "--port", String(port), "-t", String(threads), "-fa"]
        let devnull = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = devnull
        let errPipe = Pipe()
        p.standardError = errPipe
        let tail = LogTail()
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            tail.append(s)
            if s.contains("error") || s.contains("failed") { Log.info("whisper-server: \(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))") }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                errPipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                if self.intentionalStop { self.state = .stopped; return }
                Log.info("whisper-server exited (\(proc.terminationStatus)). tail: \(tail.value.suffix(400))")
                self.restartAttempts += 1
                if self.restartAttempts <= 5 {
                    let delay = Double(self.restartAttempts) * 1.0
                    self.state = .starting
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self else { return }
                        self.start(modelID: self.modelID)
                    }
                } else {
                    self.state = .failed("Speech engine keeps crashing. Try a different model in Settings.")
                }
            }
        }
        do {
            try p.run()
            process = p
            Log.info("whisper-server launched pid=\(p.processIdentifier) port=\(port) model=\(model.id)")
        } catch {
            state = .failed("Could not launch speech engine: \(error.localizedDescription)")
            return
        }
        Task { await waitUntilReady() }
    }

    private func waitUntilReady() async {
        let started = Date()
        while Date().timeIntervalSince(started) < 90 {
            guard process != nil else { return }
            if await health() {
                state = .ready
                loadedModelID = modelID
                restartAttempts = 0
                Log.info("whisper-server ready in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
                await warmUp()
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        state = .failed("Speech engine did not start in time")
    }

    private func health() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = 1
        guard let (_, resp) = try? await session.data(for: req), let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// First inference compiles Metal pipelines — do it now with silence so the user's first dictation is fast.
    private func warmUp() async {
        let silence = [Float](repeating: 0, count: 16_000)
        _ = try? await transcribe(samples: silence, language: "en", prompt: "", timeout: 30)
    }

    func stop() {
        intentionalStop = true
        stopProcess()
        state = .stopped
    }

    private func stopProcess() {
        if let p = process, p.isRunning {
            intentionalStop = true
            p.terminate()
            let deadline = Date().addingTimeInterval(1.0)
            while p.isRunning && Date() < deadline { usleep(20_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
    }

    enum TranscribeError: LocalizedError {
        case notReady, http(Int), badResponse, timeout
        var errorDescription: String? {
            switch self {
            case .notReady: return "Speech engine is still starting"
            case .http(let c): return "Speech engine error (\(c))"
            case .badResponse: return "Unexpected response from speech engine"
            case .timeout: return "Transcription timed out"
            }
        }
    }

    /// Transcribe 16 kHz mono samples. Retries once (restarting the engine) on connection failure.
    func transcribe(samples: [Float], language: String, prompt: String, timeout: TimeInterval? = nil, fast: Bool = true) async throws -> String {
        do {
            return try await transcribeOnce(samples: samples, language: language, prompt: prompt, timeout: timeout, fast: fast)
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost || e.code == .timedOut {
            Log.info("transcribe: \(e.code.rawValue) — restarting engine and retrying")
            start(modelID: modelID)
            for _ in 0..<100 where state != .ready { try? await Task.sleep(nanoseconds: 100_000_000) }
            return try await transcribeOnce(samples: samples, language: language, prompt: prompt, timeout: timeout, fast: false)
        }
    }

    private func transcribeOnce(samples: [Float], language: String, prompt: String, timeout: TimeInterval?, fast: Bool) async throws -> String {
        guard process != nil, state == .ready || state == .starting else { throw TranscribeError.notReady }
        guard let url = URL(string: "http://127.0.0.1:\(port)/inference") else { throw TranscribeError.badResponse }
        let duration = Double(samples.count) / AudioRecorder.sampleRate
        let wav = AudioUtil.wavData(samples)

        // Adaptive encoder context: Whisper always encodes 30 s windows; shrinking the context for short clips is ~3x faster.
        var audioCtx = 0
        // Too tight a context makes Whisper loop ("Thanks. Thanks. Thanks.") — keep a generous margin.
        // Measured: ≥ 2× the clip's frames (50/s) never looped; 1.6× sometimes did.
        if fast && duration < 20 {
            let needed = Int((duration * 50 * 2.0).rounded(.up))
            audioCtx = (max(512, needed) + 63) / 64 * 64
            if audioCtx >= 1400 { audioCtx = 0 }
        }

        let boundary = "fisper-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        field("response_format", "json")
        field("temperature", "0.0")
        field("temperature_inc", "0.2")
        field("no_timestamps", "true")
        field("suppress_nst", "true")
        field("language", language)
        field("prompt", prompt)
        field("audio_ctx", String(audioCtx))
        field("translate", "false")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout ?? max(20, duration * 1.5 + 15)
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TranscribeError.badResponse }
        guard http.statusCode == 200 else { throw TranscribeError.http(http.statusCode) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranscribeError.badResponse }
        if let err = obj["error"] as? String { Log.info("whisper error: \(err)"); throw TranscribeError.badResponse }
        let text = (obj["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if audioCtx != 0 && TextCleaner.hasRepetitionLoop(text) {
            Log.info("whisper: repetition detected with audio_ctx=\(audioCtx) — retrying with full context")
            return try await transcribeOnce(samples: samples, language: language, prompt: prompt, timeout: timeout, fast: false)
        }
        return text
    }

    final class LogTail: @unchecked Sendable {
        private let lock = NSLock()
        private var buf = ""
        func append(_ s: String) { lock.lock(); buf = String((buf + s).suffix(2000)); lock.unlock() }
        var value: String { lock.lock(); defer { lock.unlock() }; return buf }
    }

    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 18_765 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        guard ok else { return 18_765 }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
