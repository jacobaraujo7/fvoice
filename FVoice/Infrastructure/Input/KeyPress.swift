import Cocoa

enum KeyPress {
    private static let keyCodeReturn: CGKeyCode = 36

    /// Posts a plain Return keystroke (used by the optional auto-Enter).
    static func pressReturn() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeReturn, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeReturn, keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
