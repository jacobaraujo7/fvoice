import XCTest
@testable import FVoice

final class TranscriptionFilterTests: XCTestCase {
    func testDiscardsKnownHallucinationsAsWholeText() {
        XCTAssertNil(TranscriptionFilter.clean("Legendas pela comunidade Amara.org", speechSeconds: 5))
        XCTAssertNil(TranscriptionFilter.clean("Obrigado por assistir.", speechSeconds: 5))
        XCTAssertNil(TranscriptionFilter.clean("Tchau, tchau!", speechSeconds: 5))
    }

    func testKeepsNormalTextContainingHallucinationSubstrings() {
        let text = "Hoje falei obrigado por assistir a apresentação e depois tchau tchau para todos"
        XCTAssertEqual(TranscriptionFilter.clean(text, speechSeconds: 5), text)
    }

    func testDiscardsShortSpeech() {
        XCTAssertNil(TranscriptionFilter.clean("texto normal", speechSeconds: 0.2))
    }

    func testKeepsAtMinimumSpeechSeconds() {
        XCTAssertEqual(TranscriptionFilter.clean("texto normal", speechSeconds: 0.3), "texto normal")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(TranscriptionFilter.clean("  olá mundo \n", speechSeconds: 2), "olá mundo")
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(TranscriptionFilter.clean("", speechSeconds: 2))
        XCTAssertNil(TranscriptionFilter.clean("   \n ", speechSeconds: 2))
    }
}
