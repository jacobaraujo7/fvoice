import Foundation
import WhisperKit

enum WhisperKitEngineError: Error {
    case notPrepared
}

/// WhisperKit adapter. Downloads the model to ~/.fvoice/models and keeps it
/// loaded in memory. Language is always explicit (pt by default), never auto.
final class WhisperKitEngine: TranscriptionEngine {
    /// WhisperKit variant to load; set before prepare(). Changing it and
    /// calling prepare() again swaps the model.
    var modelVariant = "openai_whisper-large-v3-v20240930_turbo"

    private var whisper: WhisperKit?
    private var loadedVariant: String?
    private var preparing = false

    func prepare(onProgress: @escaping (Double) -> Void) async throws {
        guard loadedVariant != modelVariant || whisper == nil else { return }
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        whisper = nil

        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".fvoice/models", isDirectory: true)

        let variant = modelVariant
        DebugLog.log("model download/check started (\(variant))")
        let folder = try await WhisperKit.download(
            variant: variant,
            downloadBase: base,
            useBackgroundSession: false
        ) { progress in
            onProgress(progress.fractionCompleted)
        }

        DebugLog.log("model on disk at \(folder.path), loading…")
        let config = WhisperKitConfig(modelFolder: folder.path, load: true)
        whisper = try await WhisperKit(config)
        loadedVariant = variant
        DebugLog.log("model loaded (\(variant))")
    }

    func transcribe(samples: [Float], language: String, vocabulary: String) async throws -> String {
        guard let whisper else { throw WhisperKitEngineError.notPrepared }
        var options = DecodingOptions(
            task: .transcribe,
            language: language == "auto" ? nil : language
        )
        // Bias decoding toward the user's jargon via the initial prompt.
        let vocab = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty, let tokenizer = whisper.tokenizer {
            let tokens = tokenizer.encode(text: " " + vocab)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if !tokens.isEmpty {
                options.promptTokens = tokens
                options.usePrefillPrompt = true
            }
        }
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        DebugLog.log("transcription: \(text)")
        return text
    }
}
