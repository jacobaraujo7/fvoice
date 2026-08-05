import Foundation

/// Energy-based VAD pass over recorded samples: removes leading/trailing
/// silence and compresses internal pauses before inference, so Whisper never
/// sees dead air. Micro-pauses are kept — Whisper uses them as punctuation
/// cues. Pure in-memory, no files involved.
enum SilenceTrimmer {
    private static let windowSeconds = 0.03
    /// Internal pauses longer than this get compressed…
    private static let maxPauseSeconds = 1.0
    /// …down to this much silence.
    private static let keptPauseSeconds = 0.25
    private static let threshold: Float = 0.012

    /// Returns the samples to transcribe — trimmed when worthwhile, the
    /// original otherwise.
    static func trim(_ samples: [Float], sampleRate: Double) -> [Float] {
        let total = samples.count
        let window = Int(sampleRate * windowSeconds)
        guard window > 0, total > window else { return samples }

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
        guard voiced.contains(true) else { return samples }

        // Build kept ranges: speech + compressed pauses.
        let keptPause = Int(sampleRate * keptPauseSeconds)
        let maxPause = Int(sampleRate * maxPauseSeconds)
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
                // except the padding added below.
            }
        }

        // Keep a small lead-in/out around the outermost speech so word onsets
        // aren't clipped.
        let edgePadding = Int(sampleRate * 0.15)
        if let first = keep.first {
            keep[0] = max(0, first.lowerBound - edgePadding)..<first.upperBound
        }
        if let last = keep.last {
            keep[keep.count - 1] = last.lowerBound..<min(total, last.upperBound + edgePadding)
        }

        let trimmedFrames = keep.reduce(0) { $0 + $1.count }
        // Not worth rewriting for < 0.5s saved.
        guard total - trimmedFrames > Int(sampleRate / 2) else { return samples }

        var out = [Float]()
        out.reserveCapacity(trimmedFrames)
        for range in keep {
            out.append(contentsOf: samples[range])
        }

        let savedSeconds = Double(total - trimmedFrames) / sampleRate
        DebugLog.log(String(format: "vad trim: %.1fs -> %.1fs (saved %.1fs, %d segments)",
                            Double(total) / sampleRate,
                            Double(trimmedFrames) / sampleRate,
                            savedSeconds, keep.count))
        return out
    }
}
