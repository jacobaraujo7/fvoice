import Foundation

/// Filters out Whisper hallucinations: transcriptions produced from
/// silence/noise and known PT filler phrases when they are the whole result.
enum TranscriptionFilter {
    static let minimumSpeechSeconds = 0.3

    private static let hallucinationPatterns: [String] = [
        #"^legendas pela comunidade amara\.?org.?$"#,
        #"^legendas pela comunidade.?$"#,
        #"^obrigado por assistir.?!?$"#,
        #"^obrigada por assistir.?!?$"#,
        #"^tchau,? tchau.?!?$"#,
        #"^até a próxima.?!?$"#,
        #"^inscreva-se no canal.?!?$"#,
        #"^curta e compartilhe.?!?$"#,
        #"^\.+$"#,
    ]

    /// Returns nil when the transcription should be discarded.
    static func clean(_ text: String, speechSeconds: Double) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard speechSeconds >= minimumSpeechSeconds else {
            DebugLog.log("filter: discarded — speech \(String(format: "%.2f", speechSeconds))s < \(minimumSpeechSeconds)s")
            return nil
        }

        let normalized = trimmed.lowercased()
        for pattern in hallucinationPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                DebugLog.log("filter: discarded hallucination \"\(trimmed)\"")
                return nil
            }
        }
        return trimmed
    }
}
