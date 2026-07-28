import Foundation

protocol TranscriptionEngine: AnyObject {
    /// Downloads (if needed) and loads the model. Progress is 0...1.
    func prepare(onProgress: @escaping (Double) -> Void) async throws
    func transcribe(wavURL: URL) async throws -> String
}
