import SwiftUI

@main
struct FVoiceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
