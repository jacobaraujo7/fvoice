import XCTest
@testable import FVoice

final class AppSettingsCodableTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testEmptyObjectYieldsDefaults() throws {
        let settings = try decode("{}")
        XCTAssertEqual(settings, AppSettings())
        XCTAssertEqual(settings.language, "pt")
        XCTAssertEqual(settings.insertMode, .typing)
        XCTAssertEqual(settings.keyChord, .optionSpace)
        XCTAssertEqual(settings.engine, .whisper)
        XCTAssertEqual(settings.whisperModel, .turbo)
        XCTAssertFalse(settings.autoEnter)
        XCTAssertFalse(settings.copyToClipboard)
        XCTAssertFalse(settings.pushToTalk)
    }

    func testLegacyHotkeyMigration() throws {
        let settings = try decode(#"{"hotkey":"controlOptionSpace"}"#)
        XCTAssertEqual(settings.keyChord, KeyChord(keyCode: 49, option: true, control: true))
    }

    func testLegacyPasteInsertModeFallsBackToTyping() throws {
        let settings = try decode(#"{"insertMode":"paste"}"#)
        XCTAssertEqual(settings.insertMode, .typing)
    }

    func testUnknownWhisperModelFallsBackToTurbo() throws {
        let settings = try decode(#"{"whisperModel":"gigantic"}"#)
        XCTAssertEqual(settings.whisperModel, .turbo)
    }

    func testEncodeDecodeRoundTrip() throws {
        var settings = AppSettings()
        settings.language = "auto"
        settings.insertMode = .hook
        settings.autoEnter = true
        settings.keyChord = KeyChord(keyCode: 15, command: true, shift: true)
        settings.engine = .apple
        settings.whisperModel = .small
        settings.copyToClipboard = true
        settings.vocabulary = "flutter, dart"
        settings.preferredMicUID = "mic-123"
        settings.pushToTalk = true
        settings.hookScript = "echo hi"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}
