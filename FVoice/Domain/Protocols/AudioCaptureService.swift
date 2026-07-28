import Foundation

protocol AudioCaptureService: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws
    /// Stops capture and returns the URL of the recorded 16kHz mono wav.
    func stopRecording() throws -> URL
}
