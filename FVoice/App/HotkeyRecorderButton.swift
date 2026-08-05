import SwiftUI

/// Button that captures the next key combination pressed.
struct HotkeyRecorderButton: View {
    @EnvironmentObject var state: AppState
    @State private var armed = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            armed ? disarm() : arm()
        } label: {
            Text(armed ? String(localized: "Press keys…") : state.store.settings.keyChord.display)
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
