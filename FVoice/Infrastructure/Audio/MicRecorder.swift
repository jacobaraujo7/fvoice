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

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopRecording() throws -> URL {
        guard isRecording, let url = fileURL else { throw MicRecorderError.notRecording }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRecording = false
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
        }
    }
}
