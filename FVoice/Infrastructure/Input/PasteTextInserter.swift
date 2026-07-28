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

        // Small delay so physical modifiers (the ⌥⌘ that stopped recording)
        // are released before the synthetic Cmd+V lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.postCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                if let previous {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private static func postCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        else {
            DebugLog.log("insert: failed to create CGEvents")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        DebugLog.log("insert: Cmd+V posted (trusted=\(AXIsProcessTrusted()))")
    }
}
