import Foundation

protocol AudioCaptureService: AnyObject {
    var isRecording: Bool { get }
    /// Seconds of detected speech in the last finished recording.
    var lastSpeechSeconds: Double { get }
    /// Called on the main queue if capture is interrupted (e.g. mic unplugged).
    var onInterrupted: (() -> Void)? { get set }
    /// Called on the main queue with the current input level (0...1) while recording.
    var onLevel: ((Float) -> Void)? { get set }
    /// Input device UID to capture from; nil/empty uses the system default.
    var preferredDeviceUID: String? { get set }
    func startRecording() throws
    /// Stops capture and returns the recorded 16kHz mono Float32 samples.
    func stopRecording() throws -> [Float]
    /// Samples captured so far in the current recording.
    var recordedSampleCount: Int { get }
    /// Copies a range of the samples captured so far (for streaming chunks).
    func recordedSamples(from start: Int, to end: Int) -> [Float]
}
