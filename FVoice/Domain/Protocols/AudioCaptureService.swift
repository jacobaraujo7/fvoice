import Foundation

protocol AudioCaptureService: AnyObject {
    var isRecording: Bool { get }
    /// Seconds of detected speech in the last finished recording.
    var lastSpeechSeconds: Double { get }
    /// Called on the main queue if capture is interrupted (e.g. mic unplugged).
    var onInterrupted: (() -> Void)? { get set }
    /// Called on the main queue with the current input level (0...1) while recording.
    var onLevel: ((Float) -> Void)? { get set }
    func startRecording() throws
    /// Stops capture and returns the URL of the recorded 16kHz mono wav.
    func stopRecording() throws -> URL
}
