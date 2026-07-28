import SwiftUI

@main
struct FVoiceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("FVoice", systemImage: state.isRecording ? "record.circle.fill" : "waveform") {
            MenuBarContentView()
                .environmentObject(state)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
