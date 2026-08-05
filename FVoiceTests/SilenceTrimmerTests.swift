import XCTest
@testable import FVoice

final class SilenceTrimmerTests: XCTestCase {
    private let sampleRate = 16_000.0

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(sampleRate * seconds))
    }

    /// White noise loud enough to cross the 0.012 RMS threshold.
    private func speech(seconds: Double) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { _ in Float.random(in: -0.1...0.1) }
    }

    private func seconds(_ samples: [Float]) -> Double {
        Double(samples.count) / sampleRate
    }

    func testTrimsEdgeSilence() {
        let input = silence(seconds: 2) + speech(seconds: 1) + silence(seconds: 2)
        let output = SilenceTrimmer.trim(input, sampleRate: sampleRate)
        XCTAssertLessThan(output.count, input.count)
        // 1s of speech plus 0.15s padding on both edges, with window slack.
        XCTAssertEqual(seconds(output), 1.3, accuracy: 0.2)
    }

    func testCompressesInternalPause() {
        let input = speech(seconds: 1) + silence(seconds: 3) + speech(seconds: 1)
        let output = SilenceTrimmer.trim(input, sampleRate: sampleRate)
        // The 3s pause collapses to ~0.25s.
        XCTAssertEqual(seconds(input) - seconds(output), 2.75, accuracy: 0.3)
    }

    func testAllSilenceReturnsOriginal() {
        let input = silence(seconds: 3)
        let output = SilenceTrimmer.trim(input, sampleRate: sampleRate)
        XCTAssertEqual(output.count, input.count)
    }

    func testSmallSavingReturnsOriginal() {
        let input = silence(seconds: 0.2) + speech(seconds: 1) + silence(seconds: 0.2)
        let output = SilenceTrimmer.trim(input, sampleRate: sampleRate)
        XCTAssertEqual(output.count, input.count)
    }
}
