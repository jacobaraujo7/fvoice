import XCTest
@testable import FVoice

final class KeyChordTests: XCTestCase {
    func testDisplayModifierOrder() {
        let chord = KeyChord(keyCode: 49, command: true, option: true, control: true, shift: true)
        XCTAssertEqual(chord.display, "⌃⌥⇧⌘Space")
    }

    func testDisplaySingleModifier() {
        XCTAssertEqual(KeyChord.optionSpace.display, "⌥Space")
        XCTAssertEqual(KeyChord(keyCode: 15, command: true).display, "⌘R")
    }

    func testKeyNameKnownCodes() {
        XCTAssertEqual(KeyChord.keyName(49), "Space")
        XCTAssertEqual(KeyChord.keyName(15), "R")
    }

    func testKeyNameUnknownCodeFallback() {
        XCTAssertEqual(KeyChord.keyName(200), "key 200")
    }
}
