import AVFoundation

/// Energy-based VAD pass over a recorded wav: removes leading/trailing silence
/// and compresses internal pauses before inference, so Whisper never sees dead
/// air. Micro-pauses are kept — Whisper uses them as punctuation cues.
enum SilenceTrimmer {
    private static let windowSeconds = 0.03
    /// Internal pauses longer than this get compressed…
    private static let maxPauseSeconds = 1.0
    /// …down to this much silence.
    private static let keptPauseSeconds = 0.25
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

        // Classify each window as voiced/silent.
        var voiced: [Bool] = []
        var start = 0
        while start < total {
            let end = min(start + window, total)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            voiced.append((sum / Float(end - start)).squareRoot() > threshold)
            start += window
        }
        guard voiced.contains(true) else { return url }

        // Build kept ranges: speech (with padding) + compressed pauses.
        let keptPause = Int(format.sampleRate * keptPauseSeconds)
        let maxPause = Int(format.sampleRate * maxPauseSeconds)
        var keep: [Range<Int>] = []
        var index = 0
        while index < voiced.count {
            if voiced[index] {
                let segmentStart = index
                while index < voiced.count, voiced[index] { index += 1 }
                keep.append((segmentStart * window)..<min(index * window, total))
            } else {
                let silenceStart = index
                while index < voiced.count, !voiced[index] { index += 1 }
                let isEdge = silenceStart == 0 || index == voiced.count
                let silenceFrames = (index - silenceStart) * window
                if !isEdge {
                    let from = silenceStart * window
                    let kept = min(silenceFrames, silenceFrames > maxPause ? keptPause : silenceFrames)
                    keep.append(from..<min(from + kept, total))
                }
                // Edge silence (before first / after last speech) is dropped,
                // except a small lead-in/out merged below via padding.
            }
        }

        // Keep a small lead-in/out around the outermost speech so word onsets
        // aren't clipped.
        let edgePadding = Int(format.sampleRate * 0.15)
        if let first = keep.first {
            keep[0] = max(0, first.lowerBound - edgePadding)..<first.upperBound
        }
        if let last = keep.last {
            keep[keep.count - 1] = last.lowerBound..<min(total, last.upperBound + edgePadding)
        }

        let trimmedFrames = keep.reduce(0) { $0 + $1.count }
        // Not worth rewriting for < 0.5s saved.
        guard total - trimmedFrames > Int(format.sampleRate / 2) else { return url }

        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(trimmedFrames))
        else { return url }
        out.frameLength = AVAudioFrameCount(trimmedFrames)
        if let dst = out.floatChannelData?[0] {
            var offset = 0
            for range in keep {
                dst.advanced(by: offset).update(from: samples + range.lowerBound, count: range.count)
                offset += range.count
            }
        }

        let trimmedURL = url.deletingPathExtension().appendingPathExtension("trimmed.wav")
        guard let outFile = try? AVAudioFile(forWriting: trimmedURL, settings: file.fileFormat.settings,
                                             commonFormat: format.commonFormat, interleaved: format.isInterleaved),
              (try? outFile.write(from: out)) != nil
        else { return url }

        let savedSeconds = Double(total - trimmedFrames) / format.sampleRate
        DebugLog.log(String(format: "vad trim: %.1fs -> %.1fs (saved %.1fs, %d segments)",
                            Double(total) / format.sampleRate,
                            Double(trimmedFrames) / format.sampleRate,
                            savedSeconds, keep.count))
        return trimmedURL
    }
}
