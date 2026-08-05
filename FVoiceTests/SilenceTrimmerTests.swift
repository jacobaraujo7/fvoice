import XCTest
import AVFoundation
@testable import FVoice

final class SilenceTrimmerTests: XCTestCase {
    private let sampleRate = 16_000.0
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilenceTrimmerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Segments: (seconds, isSpeech). Speech is white noise at amplitude 0.1.
    private func makeWav(name: String, segments: [(seconds: Double, speech: Bool)]) throws -> URL {
        let url = tempDir.appendingPathComponent("\(name).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let totalFrames = segments.reduce(0) { $0 + Int(sampleRate * $1.seconds) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let data = buffer.floatChannelData![0]
        var offset = 0
        var rng = SystemRandomNumberGenerator()
        for segment in segments {
            let frames = Int(sampleRate * segment.seconds)
            for i in 0..<frames {
                data[offset + i] = segment.speech ? Float.random(in: -0.1...0.1, using: &rng) : 0
            }
            offset += frames
        }
        try file.write(from: buffer)
        return url
    }

    private func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func testTrimsLeadingAndTrailingSilence() throws {
        let url = try makeWav(name: "edges", segments: [(2.0, false), (1.0, true), (2.0, false)])
        let result = SilenceTrimmer.trim(url)
        XCTAssertNotEqual(result, url)
        let trimmed = try duration(of: result)
        XCTAssertLessThan(trimmed, 5.0)
        // Roughly the 1s of speech plus edge padding.
        XCTAssertEqual(trimmed, 1.3, accuracy: 0.35)
    }

    func testCompressesLongInternalPause() throws {
        let url = try makeWav(name: "pause",
                              segments: [(1.0, true), (3.0, false), (1.0, true)])
        let result = SilenceTrimmer.trim(url)
        XCTAssertNotEqual(result, url)
        let original = try duration(of: url)
        let trimmed = try duration(of: result)
        // The 3s pause should be compressed to ~0.25s.
        XCTAssertEqual(original - trimmed, 3.0 - 0.25, accuracy: 0.4)
    }

    func testAllSilenceReturnsOriginal() throws {
        let url = try makeWav(name: "silence", segments: [(2.0, false)])
        XCTAssertEqual(SilenceTrimmer.trim(url), url)
    }

    func testSmallSavingReturnsOriginal() throws {
        // Only ~0.4s of edge silence to save, minus padding: under 0.5s.
        let url = try makeWav(name: "small", segments: [(0.2, false), (1.0, true), (0.2, false)])
        XCTAssertEqual(SilenceTrimmer.trim(url), url)
    }
}
