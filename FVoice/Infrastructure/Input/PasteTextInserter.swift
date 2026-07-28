import Cocoa

/// Inserts text by putting it on the clipboard, posting Cmd+V, and restoring
/// the previous clipboard contents shortly after. Requires Accessibility.
final class PasteTextInserter: TextInserter {
    private static let keyCodeV: CGKeyCode = 9

    func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Wait until the physical modifiers (the ⌥ that stopped recording)
        // are actually released — otherwise the focused app sees ⌥⌘V.
        Self.waitForModifiersReleased {
            Self.postCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                if let previous {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private static func waitForModifiersReleased(attempt: Int = 0, then action: @escaping () -> Void) {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        if flags.isEmpty || attempt > 40 {  // ~4s safety timeout
            if !flags.isEmpty { DebugLog.log("insert: timed out waiting for modifier release") }
            action()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                waitForModifiersReleased(attempt: attempt + 1, then: action)
            }
        }
    }

    private static let keyCodeCommand: CGKeyCode = 55

    private static func postCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeCommand, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeCommand, keyDown: false)
        else {
            DebugLog.log("insert: failed to create CGEvents")
            return
        }

        // Full sequence like a real keyboard: Cmd down, V down/up, Cmd up,
        // with the command flag carried on every event in between.
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []

        for event in [cmdDown, vDown, vUp, cmdUp] {
            event.post(tap: .cghidEventTap)
        }
        DebugLog.log("insert: Cmd+V sequence posted (trusted=\(AXIsProcessTrusted()))")
    }
}
