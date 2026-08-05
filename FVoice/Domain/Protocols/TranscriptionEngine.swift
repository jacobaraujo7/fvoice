import Foundation

protocol TranscriptionEngine: AnyObject {
    /// Downloads (if needed) and loads the model. Progress is 0...1.
    func prepare(onProgress: @escaping (Double) -> Void) async throws
    /// language: ISO code ("pt", "en", …) or "auto" for detection.
    /// vocabulary: comma-separated domain terms; engines may ignore it.
    func transcribe(wavURL: URL, language: String, vocabulary: String) async throws -> String
}
