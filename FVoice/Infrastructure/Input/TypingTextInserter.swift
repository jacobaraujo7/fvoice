import Cocoa

/// Inserts text by synthesizing keyboard events carrying Unicode strings —
/// no modifiers involved and the clipboard is never touched. Works in
/// terminals and apps where synthetic Cmd+V is unreliable.
final class TypingTextInserter: TextInserter {
    private static let chunkSize = 20

    func insert(_ text: String) {
        Self.waitForModifiersReleased {
            Self.type(text)
        }
    }

    private static func type(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            DebugLog.log("insert: no CGEventSource")
            return
        }

        var chunk: [UniChar] = []
        chunk.reserveCapacity(chunkSize * 2)

        func flush() {
            guard !chunk.isEmpty else { return }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            chunk.removeAll(keepingCapacity: true)
            usleep(8_000)
        }

        for character in text {
            chunk.append(contentsOf: Array(String(character).utf16))
            if chunk.count >= chunkSize { flush() }
        }
        flush()
        DebugLog.log("insert: typed \(text.count) chars via unicode keystrokes")
    }

    private static func waitForModifiersReleased(attempt: Int = 0, then action: @escaping () -> Void) {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        if flags.isEmpty || attempt > 40 {
            if !flags.isEmpty { DebugLog.log("insert: timed out waiting for modifier release") }
            action()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                waitForModifiersReleased(attempt: attempt + 1, then: action)
            }
        }
    }
}
