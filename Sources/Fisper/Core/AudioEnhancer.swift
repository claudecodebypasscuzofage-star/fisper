import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

/// Cleans recorded speech before it reaches Whisper:
///  1. high-pass filter (rumble, desk bumps, AC hum)
///  2. Apple's on-device ML voice isolation (the tech behind FaceTime "Voice Isolation") — removes background
///     noise, music and far-away chatter
///  3. loudness normalization with a soft limiter — makes quiet / mumbled speech as clear as normal speech
enum AudioEnhancer {
    struct Options {
        var noise: NoiseMode = .auto
        var strength: Float = 0.85        // voice-isolation wet mix; 0.85 measured best for Whisper
        var normalize = true
        var maxBoostDB: Float = 24
    }

    struct Report { var snrDB: Float; var isolated: Bool; var gainDB: Float; var ms: Int }

    /// SNR below which "Automatic" turns on voice isolation. Clean speech measures 35+ dB, a café ~10–15 dB.
    static let noisyThresholdDB: Float = 24

    static func process(_ input: [Float], sampleRate: Double = AudioRecorder.sampleRate, options: Options) -> [Float] {
        processWithReport(input, sampleRate: sampleRate, options: options).0
    }

    static func processWithReport(_ input: [Float], sampleRate: Double = AudioRecorder.sampleRate, options: Options) -> ([Float], Report) {
        let t0 = Date()
        guard input.count > 1600 else { return (input, Report(snrDB: 0, isolated: false, gainDB: 0, ms: 0)) }
        var s = input
        if options.noise != .off { s = highPass(s, cutoff: 85, sampleRate: sampleRate) }
        let snr = estimateSNR(s)
        var isolated = false
        let wantIsolation = options.noise == .always || (options.noise == .auto && snr < noisyThresholdDB)
        if wantIsolation, let iso = isolateVoice(s, sampleRate: sampleRate, wet: max(10, min(100, options.strength * 100))) {
            s = iso; isolated = true
        }
        var gainDB: Float = 0
        // never amplify a clip that is basically just noise — that's how Whisper "hears" phantom sentences
        if options.normalize && snr >= 10 { (s, gainDB) = normalize(s, maxBoostDB: options.maxBoostDB) }
        return (s, Report(snrDB: snr, isolated: isolated, gainDB: gainDB, ms: Int(Date().timeIntervalSince(t0) * 1000)))
    }

    /// Ratio of speech level (90th percentile of 20 ms windows) to the noise floor (10th percentile), in dB.
    static func estimateSNR(_ s: [Float]) -> Float {
        let win = 320
        guard s.count > win * 10 else { return 60 }
        var e: [Float] = []
        var i = 0
        while i + win <= s.count {
            var v: Float = 0
            s.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + i, 1, &v, vDSP_Length(win)) }
            e.append(v); i += win
        }
        e.sort()
        let floor = max(e[e.count / 10], 1e-6), speech = e[e.count * 9 / 10]
        return 20 * log10f(max(speech, 1e-6) / floor)
    }

    // MARK: High-pass (2nd-order Butterworth biquad)

    static func highPass(_ x: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * 0.7071)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        let b0 = Float((1 + cosw) / 2 / a0), b1 = Float(-(1 + cosw) / a0), b2 = b0
        let a1 = Float(-2 * cosw / a0), a2 = Float((1 - alpha) / a0)
        var y = [Float](repeating: 0, count: x.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in 0..<x.count {
            let xi = x[i]
            let yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            y[i] = yi
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
        }
        return y
    }

    // MARK: Apple voice isolation (AUSoundIsolation), rendered offline

    private static let isolationDesc = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x766F6973, // 'vois'
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0)

    static var isolationAvailable: Bool {
        var d = isolationDesc
        return AudioComponentFindNext(nil, &d) != nil
    }

    /// Runs AUSoundIsolation over the whole clip. Returns nil if the unit is unavailable or fails.
    static func isolateVoice(_ samples: [Float], sampleRate: Double, wet: Float) -> [Float]? {
        guard isolationAvailable else { return nil }
        // The unit is happiest at 48 kHz; upsample, process, downsample.
        let workRate = 48_000.0
        guard let up = resample(samples, from: sampleRate, to: workRate) else { return nil }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: workRate, channels: 1, interleaved: false)!

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let effect = AVAudioUnitEffect(audioComponentDescription: isolationDesc)
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)

        // 100% wet, high-quality voice model
        if let au = Optional(effect.audioUnit) {
            AudioUnitSetParameter(au, 0 /* WetDryMixPercent */, kAudioUnitScope_Global, 0, wet, 0)
            AudioUnitSetParameter(au, 1 /* SoundToIsolate */, kAudioUnitScope_Global, 0, 0 /* HighQualityVoice */, 0)
        }

        let block: AVAudioFrameCount = 4096
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: block)
            try engine.start()
        } catch {
            Log.info("voice isolation: engine setup failed: \(error.localizedDescription)")
            return nil
        }
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(up.count)) else { return nil }
        inBuf.frameLength = AVAudioFrameCount(up.count)
        up.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: up.count) }

        // the unit has some latency: render a little extra tail, then drop the leading latency
        let latencyFrames = Int(effect.auAudioUnit.latency * workRate)
        player.scheduleBuffer(inBuf, completionHandler: nil)
        player.play()

        guard let outBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: block) else { return nil }
        var out: [Float] = []
        out.reserveCapacity(up.count + latencyFrames + Int(block))
        let total = up.count + latencyFrames
        while out.count < total {
            let n = min(block, AVAudioFrameCount(total - out.count))
            do {
                let status = try engine.renderOffline(n, to: outBuf)
                guard status == .success, let ch = outBuf.floatChannelData?[0] else { break }
                out.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
            } catch {
                Log.info("voice isolation: render failed: \(error.localizedDescription)")
                return nil
            }
        }
        engine.stop()
        if latencyFrames > 0 && out.count > latencyFrames { out.removeFirst(latencyFrames) }
        if out.count > up.count { out.removeLast(out.count - up.count) }
        // guard against a unit that silenced everything (e.g. model missing)
        let inE = rms(up), outE = rms(out)
        guard outE > inE * 0.02 else { Log.info("voice isolation: output near silent, skipping"); return nil }
        return resample(out, from: workRate, to: sampleRate)
    }

    static func resample(_ s: [Float], from: Double, to: Double) -> [Float]? {
        if from == to { return s }
        let inF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false)!
        let outF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false)!
        guard let conv = AVAudioConverter(from: inF, to: outF),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inF, frameCapacity: AVAudioFrameCount(s.count)) else { return nil }
        conv.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        inBuf.frameLength = AVAudioFrameCount(s.count)
        s.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: s.count) }
        let cap = AVAudioFrameCount(Double(s.count) * to / from + 2048)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outF, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        let st = conv.convert(to: outBuf, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        guard st != .error, let ch = outBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
    }

    // MARK: Loudness normalization (speech-aware) + soft limiter

    static func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        var v: Float = 0
        vDSP_rmsqv(s, 1, &v, vDSP_Length(s.count))
        return v
    }

    /// Brings the loudest 30% of 20 ms windows (≈ the speech) to about -20 dBFS.
    static func normalize(_ s: [Float], maxBoostDB: Float) -> ([Float], Float) {
        let win = 320
        guard s.count > win * 4 else { return (s, 0) }
        var energies: [Float] = []
        var i = 0
        while i + win <= s.count {
            var v: Float = 0
            s.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + i, 1, &v, vDSP_Length(win)) }
            energies.append(v); i += win
        }
        let sorted = energies.sorted()
        let speech = Array(sorted.suffix(max(1, sorted.count * 3 / 10)))
        let speechRMS = speech.reduce(0, +) / Float(speech.count)
        guard speechRMS > 1e-5 else { return (s, 0) }
        let target: Float = 0.1 // ≈ -20 dBFS
        let gain = min(powf(10, maxBoostDB / 20), max(1.0, target / speechRMS))   // only ever boost
        if abs(gain - 1) < 0.05 { return (s, 0) }
        // soft limiter (tanh knee) so boosted peaks never clip
        let out = s.map { x in
            let y = x * gain
            return abs(y) < 0.7 ? y : (y > 0 ? 1 : -1) * (0.7 + 0.29 * tanhf((abs(y) - 0.7) / 0.29))
        }
        return (out, 20 * log10f(gain))
    }
}
