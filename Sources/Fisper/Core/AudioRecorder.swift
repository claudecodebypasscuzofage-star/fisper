import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioDevices {
    static func inputDevices() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0, let uid = stringProp(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProp(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    static func defaultInputName() -> String {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return "System default" }
        return stringProp(id, kAudioObjectPropertyName) ?? "System default"
    }

    static func device(forUID uid: String) -> AudioInputDevice? {
        guard !uid.isEmpty else { return nil }
        return inputDevices().first { $0.uid == uid }
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProp(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    // MARK: Output mute (optional "silence other audio while dictating")

    private static func defaultOutput() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    static func isOutputMuted() -> Bool? {
        guard let id = defaultOutput() else { return nil }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var muted: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    static func setOutputMuted(_ mute: Bool) {
        guard let id = defaultOutput() else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return }
        var v: UInt32 = mute ? 1 : 0
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}

/// Captures microphone audio as 16 kHz mono Float32 — exactly what Whisper wants.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var isRecording = false
    private var startedAt = Date()

    /// Called on the main queue ~40x/sec with a 0...1 loudness value.
    var onLevel: ((Float) -> Void)?
    /// Called on main if the device disappears / engine dies mid-recording.
    var onInterrupted: (() -> Void)?

    private var configObserver: NSObjectProtocol?

    func start(deviceUID: String) throws {
        if isRecording { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); samples.reserveCapacity(16_000 * 60); lock.unlock()

        let engine = AVAudioEngine()
        let input = engine.inputNode

        if let dev = AudioDevices.device(forUID: deviceUID), let unit = input.audioUnit {
            var devID = dev.id
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { Log.info("mic: could not select \(dev.name) (\(status)), using default") }
        }

        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw NSError(domain: "Fisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false)!
        guard let conv = AVAudioConverter(from: hwFormat, to: target) else {
            throw NSError(domain: "Fisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported microphone format"])
        }
        self.converter = conv

        input.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, target: target)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        isRecording = true
        startedAt = Date()

        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.isRecording else { return }
            Log.info("mic: audio configuration changed mid-recording")
            self.onInterrupted?()
        }
    }

    private func handle(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard error == nil, let ch = out.floatChannelData?[0] else { return }
        let n = Int(out.frameLength)
        guard n > 0 else { return }
        let chunk = UnsafeBufferPointer(start: ch, count: n)
        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = sqrtf(sum / Float(n))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        // map RMS to perceptual 0...1 (approx -55 dB ... -12 dB)
        let db = 20 * log10f(max(rms, 1e-7))
        let level = min(1, max(0, (db + 55) / 43))
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    var elapsed: TimeInterval { isRecording ? Date().timeIntervalSince(startedAt) : 0 }

    /// Number of 16 kHz samples captured so far (thread-safe) — used for streaming transcription.
    var sampleCount: Int { lock.lock(); defer { lock.unlock() }; return samples.count }

    func copySamples(_ range: Range<Int>) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let r = max(0, range.lowerBound)..<min(samples.count, range.upperBound)
        return r.isEmpty ? [] : Array(samples[r])
    }

    /// Stops and returns the captured 16 kHz samples.
    @discardableResult
    func stop() -> [Float] {
        if let obs = configObserver { NotificationCenter.default.removeObserver(obs); configObserver = nil }
        guard isRecording, let engine else { isRecording = false; return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.converter = nil
        isRecording = false
        lock.lock(); let out = samples; samples = []; lock.unlock()
        return out
    }
}

// MARK: - Audio utilities

enum AudioUtil {
    /// Peak RMS over 30 ms windows and the amount of "voiced" audio, used to reject silent clips.
    static func analyze(_ s: [Float]) -> (peakRMS: Float, voicedSeconds: Double) {
        let win = 480
        guard s.count >= win else { return (0, 0) }
        var peak: Float = 0
        var voicedWindows = 0
        // adaptive noise floor: 20th percentile of window energies
        var energies: [Float] = []
        energies.reserveCapacity(s.count / win + 1)
        var i = 0
        while i + win <= s.count {
            var sum: Float = 0
            for j in i..<(i + win) { sum += s[j] * s[j] }
            let r = sqrtf(sum / Float(win))
            energies.append(r)
            peak = max(peak, r)
            i += win
        }
        let sorted = energies.sorted()
        let floor = sorted[Int(Double(sorted.count) * 0.2)]
        let speechLevel = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let threshold = max(0.006, min(floor * 2.5, speechLevel * 0.3))
        voicedWindows = energies.filter { $0 > threshold }.count
        return (peak, Double(voicedWindows * win) / AudioRecorder.sampleRate)
    }

    /// Trim leading/trailing silence, keeping padding; pad to a minimum length.
    static func trimmed(_ s: [Float], pad: Double = 0.25) -> [Float] {
        let win = 480
        guard s.count > win * 4 else { return s }
        var energies: [Float] = []
        var i = 0
        while i + win <= s.count {
            var sum: Float = 0
            for j in i..<(i + win) { sum += s[j] * s[j] }
            energies.append(sqrtf(sum / Float(win)))
            i += win
        }
        let sorted = energies.sorted()
        let floor = sorted[Int(Double(sorted.count) * 0.2)]
        let speechLevel = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let threshold = max(0.008, min(floor * 3, speechLevel * 0.25))
        guard let first = energies.firstIndex(where: { $0 > threshold }),
              let last = energies.lastIndex(where: { $0 > threshold }) else { return s }
        let padSamples = Int(pad * AudioRecorder.sampleRate)
        let start = max(0, first * win - padSamples)
        let end = min(s.count, (last + 1) * win + padSamples)
        return Array(s[start..<end])
    }

    /// Index of the quietest 300 ms stretch inside `s` (searching the last `searchSeconds`), or nil if nothing is quiet.
    static func quietSplitPoint(_ s: [Float], searchSeconds: Double = 4) -> Int? {
        let win = 480, need = 10 // 10 x 30 ms
        let start = max(0, s.count - Int(searchSeconds * AudioRecorder.sampleRate))
        var energies: [Float] = []
        var i = start
        while i + win <= s.count {
            var sum: Float = 0
            for j in i..<(i + win) { sum += s[j] * s[j] }
            energies.append(sqrtf(sum / Float(win))); i += win
        }
        guard energies.count > need else { return nil }
        let speech = energies.sorted()[energies.count * 9 / 10]
        var best: (idx: Int, e: Float)? = nil
        for k in 0...(energies.count - need) {
            let e = energies[k..<(k + need)].reduce(0, +) / Float(need)
            if best == nil || e < best!.e { best = (k, e) }
        }
        guard let b = best, b.e < max(0.01, speech * 0.2) else { return nil }
        return start + (b.idx + need / 2) * win
    }

    /// Whisper sometimes drops the final word if audio ends abruptly — add a short silence tail.
    static func prepared(_ s: [Float]) -> [Float] {
        var out = trimmed(s)
        out.append(contentsOf: [Float](repeating: 0, count: Int(0.35 * AudioRecorder.sampleRate)))
        let minCount = Int(1.1 * AudioRecorder.sampleRate)
        if out.count < minCount { out.append(contentsOf: [Float](repeating: 0, count: minCount - out.count)) }
        return out
    }

    static func wavData(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(byteCount)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() { pcm[i] = Int16(max(-1, min(1, s)) * 32767) }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    static func samples(fromWAV url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate, channels: 1, interleaved: false)!
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }
        if file.processingFormat.sampleRate == target.sampleRate, file.processingFormat.channelCount == 1, let ch = inBuf.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: ch, count: Int(inBuf.frameLength)))
        }
        guard let conv = AVAudioConverter(from: file.processingFormat, to: target) else { return nil }
        let cap = AVAudioFrameCount(Double(inBuf.frameLength) * target.sampleRate / file.processingFormat.sampleRate + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, st in
            if fed { st.pointee = .endOfStream; return nil }
            fed = true; st.pointee = .haveData; return inBuf
        }
        guard let ch = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
    }
}
