import Sparkle
import SwiftUI

struct MenuBarContentView: View {
    let updater: SPUUpdater
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var chord: String { state.store.settings.keyChord.display }

    var body: some View {
        switch state.status {
        case .downloading(let fraction):
            Text("Downloading model… \(Int(fraction * 100))%")
        case .warming:
            Text("Loading model…")
        case .idle:
            if state.store.settings.pushToTalk {
                Text("Ready: hold \(chord) to talk")
            } else {
                Text("Ready: \(chord) to record")
            }
        case .recording:
            if state.store.settings.pushToTalk {
                Text("Recording… release to transcribe")
            } else {
                Text("Recording… \(chord) to stop")
            }
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

        if state.isRecording {
            Button("Stop recording") {
                state.toggle()
            }
            Button("Cancel (Esc)") {
                state.cancelRecording()
            }
        } else {
            Button("Record") {
                state.toggle()
            }
        }

        Divider()
        Button("Setup Assistant…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "onboarding")
        }
        Button("Settings…") {
            // LSUIElement apps open windows behind everything unless activated.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Button("Check for Updates…") {
            NSApp.activate(ignoringOtherApps: true)
            updater.checkForUpdates()
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
