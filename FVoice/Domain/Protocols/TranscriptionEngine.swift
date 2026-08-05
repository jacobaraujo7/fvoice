import Foundation

protocol TranscriptionEngine: AnyObject {
    /// Downloads (if needed) and loads the model. Progress is 0...1.
    func prepare(onProgress: @escaping (Double) -> Void) async throws
    /// samples: 16kHz mono Float32 audio.
    /// language: ISO code ("pt", "en", …) or "auto" for detection.
    /// vocabulary: comma-separated domain terms; engines may ignore it.
    /// context: text transcribed so far (streaming chunks); engines may ignore it.
    func transcribe(samples: [Float], language: String, vocabulary: String, context: String) async throws -> String
}
