import AVFoundation

struct Cue {
    let t: Double
    let kind: String
}

struct AudioMix {
    static let rate = 48_000.0

    let duration: Double
    var left: [Float]
    var right: [Float]
    private var seed: UInt32 = 0x9E37_79B9

    init(duration: Double) {
        self.duration = duration
        let frames = Int(duration * Self.rate)
        left = Array(repeating: 0, count: frames)
        right = Array(repeating: 0, count: frames)
    }

    private mutating func noise() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    private mutating func place(_ samples: [Float], at t: Double, gain: Float) {
        let start = Int(t * Self.rate)
        for (i, s) in samples.enumerated() where start + i >= 0 && start + i < left.count {
            left[start + i] += s * gain
            right[start + i] += s * gain
        }
    }

    private func sine(_ f: Double, _ t: Double) -> Float { Float(sin(2 * .pi * f * t)) }

    // Sounds

    private mutating func bell(_ freqs: [Double], decay: Double, length: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(length * Self.rate))
        for i in out.indices {
            let t = Double(i) / Self.rate
            let attack = Float(min(1, t / 0.006))
            var s: Float = 0
            for (k, f) in freqs.enumerated() {
                s += (sine(f, t) + 0.18 * sine(f * 2.76, t) * Float(exp(-t * 9))) / Float(k + 1)
            }
            out[i] = s * attack * Float(exp(-t * decay))
        }
        return out
    }

    private mutating func whoosh(length: Double, rising: Bool) -> [Float] {
        var out = [Float](repeating: 0, count: Int(length * Self.rate))
        var lp: Float = 0
        for i in out.indices {
            let p = Double(i) / Double(out.count)
            let sweep = rising ? p : 1 - p
            let cutoff = Float(0.004 + 0.05 * sweep * sweep)
            lp += (noise() - lp) * cutoff
            let env = Float(pow(sin(.pi * p), 2))
            out[i] = lp * 6 * env
        }
        return out
    }

    private mutating func thud() -> [Float] {
        var out = [Float](repeating: 0, count: Int(0.25 * Self.rate))
        for i in out.indices {
            let t = Double(i) / Self.rate
            out[i] = sine(85, t) * Float(exp(-t * 22)) + noise() * Float(exp(-t * 90)) * 0.15
        }
        return out
    }

    mutating func addEffects(_ cues: [Cue], gain: Float) {
        for cue in cues {
            switch cue.kind {
            case "toast":
                place(bell([880], decay: 9, length: 0.6), at: cue.t, gain: 0.012 * gain)
            case "chime":
                place(bell([784], decay: 4, length: 1.4), at: cue.t, gain: 0.02 * gain)
                place(bell([1175], decay: 4, length: 1.4), at: cue.t + 0.12, gain: 0.016 * gain)
            case "logo":
                place(bell([523.25, 783.99, 1318.5], decay: 2, length: 2.5), at: cue.t, gain: 0.012 * gain)
            case "open":
                place(whoosh(length: 1.4, rising: true), at: cue.t - 0.2, gain: 0.03 * gain)
            case "close":
                place(whoosh(length: 1.1, rising: false), at: cue.t, gain: 0.03 * gain)
            case "drop":
                place(thud(), at: cue.t, gain: 0.045 * gain)
            default:
                break
            }
        }
    }

    mutating func addMusic(from url: URL, gain: Float, fadeIn: Double = 0.02, fadeOut: Double = 2) throws {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let frames = AVAudioFrameCount(left.count)
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames)!
        var done = false
        var error: NSError?
        converter.convert(to: output, error: &error) { packets, status in
            let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: packets)!
            do { try file.read(into: input, frameCount: packets) } catch { done = true }
            if done || input.frameLength == 0 {
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            return input
        }
        if let error { throw error }

        let channels = output.floatChannelData!
        let stereo = output.format.channelCount > 1
        for i in 0..<Int(output.frameLength) where i < left.count {
            let t = Double(i) / Self.rate
            let env = Float(min(1, t / fadeIn, max(0, (duration - t) / fadeOut)))
            left[i] += channels[0][i] * gain * env
            right[i] += channels[stereo ? 1 : 0][i] * gain * env
        }
    }

    mutating func normalize(peak target: Float = 0.89) {
        let peak = max(left.map(abs).max() ?? 0, right.map(abs).max() ?? 0)
        guard peak > target else { return }
        let k = target / peak
        for i in left.indices {
            left[i] *= k
            right[i] *= k
        }
    }

    func write(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.rate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 8192
        var offset = 0
        while offset < left.count {
            let n = min(chunk, left.count - offset)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n))!
            buffer.frameLength = AVAudioFrameCount(n)
            for i in 0..<n {
                buffer.floatChannelData![0][i] = left[offset + i]
                buffer.floatChannelData![1][i] = right[offset + i]
            }
            try file.write(from: buffer)
            offset += n
        }
    }
}

func mux(video: URL, audio: URL, into output: URL) async throws {
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: video)
    let audioAsset = AVURLAsset(url: audio)
    let duration = try await videoAsset.load(.duration)
    let audioDuration = try await audioAsset.load(.duration)
    guard
        let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
        let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw CocoaError(.fileReadCorruptFile) }
    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, audioDuration)), of: sourceAudio, at: .zero)

    try? FileManager.default.removeItem(at: output)
    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try await session.export(to: output, as: .mp4)
}
