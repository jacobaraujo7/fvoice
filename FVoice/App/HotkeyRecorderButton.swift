import SwiftUI

/// Button that captures the next key combination pressed.
struct HotkeyRecorderButton: View {
    /// Onboarding: show a neutral call-to-action instead of suggesting the
    /// default shortcut, until the user records one themselves.
    var placeholderUntilRecorded = false

    @EnvironmentObject var state: AppState
    @State private var armed = false
    @State private var recorded = false
    @State private var monitor: Any?

    private var label: String {
        if armed { return String(localized: "Press keys…") }
        if placeholderUntilRecorded, !recorded { return String(localized: "Click to record") }
        return state.store.settings.keyChord.display
    }

    var body: some View {
        Button {
            armed ? disarm() : arm()
        } label: {
            Text(label)
                .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .tint(armed ? .orange : nil)
        .onDisappear { disarm() }
    }

    private func arm() {
        armed = true
        state.suspendHotkey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc cancels
                disarm()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else {
                NSSound.beep()
                return nil
            }
            var chord = KeyChord(keyCode: event.keyCode)
            chord.command = flags.contains(.command)
            chord.option = flags.contains(.option)
            chord.control = flags.contains(.control)
            chord.shift = flags.contains(.shift)
            state.store.settings.keyChord = chord
            recorded = true
            disarm()
            return nil
        }
    }

    private func disarm() {
        armed = false
        state.suspendHotkey(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
