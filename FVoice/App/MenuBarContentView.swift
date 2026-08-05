import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    private var chord: String { state.store.settings.keyChord.display }

    var body: some View {
        switch state.status {
        case .downloading(let fraction):
            Text("Downloading model… \(Int(fraction * 100))%")
        case .warming:
            Text("Loading model…")
        case .idle:
            Text(state.store.settings.pushToTalk
                 ? "Ready — hold \(chord) to talk"
                 : "Ready — \(chord) to record")
        case .recording:
            Text(state.store.settings.pushToTalk
                 ? "Recording… release to transcribe"
                 : "Recording… \(chord) to stop")
        case .transcribing:
            Text("Transcribing…")
        case .error(let message):
            Text("Error: \(message)")
        case .needsMicrophone:
            Text("Microphone permission missing")
            Button("Open Microphone Settings") {
                state.openMicrophoneSettings()
            }
        case .needsInputMonitoring:
            Text("Input Monitoring permission missing")
            Button("Open Privacy Settings") {
                state.openInputMonitoringSettings()
            }
            Button("Try again") {
                state.retryHotkey()
            }
        }

        Button(state.isRecording ? "Stop recording" : "Record") {
            state.toggle()
        }
        if state.isRecording {
            Button("Cancel (Esc)") {
                state.cancelRecording()
            }
        }

        if !state.history.isEmpty {
            Menu("History") {
                ForEach(Array(state.history.enumerated()), id: \.offset) { _, item in
                    Button(item.count > 60 ? String(item.prefix(60)) + "…" : item) {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(item, forType: .string)
                    }
                }
            }
        }

        Divider()
        Button("Settings…") {
            // LSUIElement apps open windows behind everything unless activated.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
