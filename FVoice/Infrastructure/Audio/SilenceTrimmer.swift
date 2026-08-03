import AVFoundation

/// Energy-based VAD pass over a recorded wav: trims leading/trailing silence
/// (with padding) before inference, so Whisper never sees dead air.
enum SilenceTrimmer {
    private static let windowSeconds = 0.03
    private static let paddingSeconds = 0.25
    private static let threshold: Float = 0.012

    /// Returns the URL to transcribe — the trimmed file when trimming was
    /// worthwhile, the original otherwise.
    static func trim(_ url: URL) -> URL {
        guard let file = try? AVAudioFile(forReading: url) else { return url }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return url }

        let total = Int(buffer.frameLength)
        let window = Int(format.sampleRate * windowSeconds)
        guard window > 0, total > window else { return url }

        var firstVoiced = -1
        var lastVoiced = -1
        var start = 0
        while start < total {
            let end = min(start + window, total)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            let rms = (sum / Float(end - start)).squareRoot()
            if rms > threshold {
                if firstVoiced < 0 { firstVoiced = start }
                lastVoiced = end
            }
            start += window
        }
        guard firstVoiced >= 0 else { return url }

        let padding = Int(format.sampleRate * paddingSeconds)
        let from = max(0, firstVoiced - padding)
        let to = min(total, lastVoiced + padding)
        let trimmedFrames = to - from

        // Not worth rewriting for < 0.5s saved.
        guard total - trimmedFrames > Int(format.sampleRate / 2) else { return url }

        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(trimmedFrames))
        else { return url }
        out.frameLength = AVAudioFrameCount(trimmedFrames)
        if let dst = out.floatChannelData?[0] {
            dst.update(from: samples + from, count: trimmedFrames)
        }

        let trimmedURL = url.deletingPathExtension().appendingPathExtension("trimmed.wav")
        guard let outFile = try? AVAudioFile(forWriting: trimmedURL, settings: file.fileFormat.settings,
                                             commonFormat: format.commonFormat, interleaved: format.isInterleaved),
              (try? outFile.write(from: out)) != nil
        else { return url }

        let savedSeconds = Double(total - trimmedFrames) / format.sampleRate
        DebugLog.log(String(format: "vad trim: %.1fs -> %.1fs (saved %.1fs)",
                            Double(total) / format.sampleRate,
                            Double(trimmedFrames) / format.sampleRate,
                            savedSeconds))
        return trimmedURL
    }
}
