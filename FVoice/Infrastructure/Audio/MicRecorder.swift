import AVFoundation

enum MicRecorderError: Error {
    case alreadyRecording
    case notRecording
    case formatUnavailable
    case converterUnavailable
}

/// Captures the default input via AVAudioEngine, resamples to 16kHz mono
/// Float32 and writes a wav file for debugging/transcription.
final class MicRecorder: AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var fileURL: URL?

    private(set) var isRecording = false
    /// Seconds of buffers whose RMS crossed the voice threshold (cheap VAD).
    private(set) var lastSpeechSeconds: Double = 0
    /// Called on the main queue if the audio device changes mid-recording.
    var onInterrupted: (() -> Void)?
    /// Called on the main queue with the current input level (0...1).
    var onLevel: ((Float) -> Void)?

    private var speechFrames: Int = 0
    private var configObserver: NSObjectProtocol?
    private static let voiceRMSThreshold: Float = 0.015

    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func startRecording() throws {
        guard !isRecording else { throw MicRecorderError.alreadyRecording }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw MicRecorderError.formatUnavailable }

        guard let converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat) else {
            throw MicRecorderError.converterUnavailable
        }
        self.converter = converter

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".fvoice/debug", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("rec-\(formatter.string(from: Date())).wav")

        var settings = Self.targetFormat.settings
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMBitDepthKey] = 16
        file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
        fileURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer)
        }

        speechFrames = 0
        lastSpeechSeconds = 0
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            DebugLog.log("audio device changed mid-recording — aborting session")
            _ = try? self.stopRecording()
            self.onInterrupted?()
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopRecording() throws -> URL {
        guard isRecording, let url = fileURL else { throw MicRecorderError.notRecording }
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRecording = false
        lastSpeechSeconds = Double(speechFrames) / Self.targetFormat.sampleRate
        file = nil
        converter = nil
        fileURL = nil
        return url
    }

    private func append(buffer: AVAudioPCMBuffer) {
        guard let converter, let file else { return }

        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        converter.convert(to: out, error: nil) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        if out.frameLength > 0 {
            try? file.write(from: out)
            if let data = out.floatChannelData?[0] {
                var sum: Float = 0
                for i in 0..<Int(out.frameLength) {
                    sum += data[i] * data[i]
                }
                let rms = (sum / Float(out.frameLength)).squareRoot()
                if rms > Self.voiceRMSThreshold {
                    speechFrames += Int(out.frameLength)
                }
                if let onLevel {
                    // Map typical speech RMS (~0.01–0.2) to 0...1.
                    let level = min(1, rms * 8)
                    DispatchQueue.main.async { onLevel(level) }
                }
            }
        }
    }
}
