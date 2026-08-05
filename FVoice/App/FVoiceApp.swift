import AVFoundation
import IOKit.hid
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
                .background(OnboardingLauncher().environmentObject(state))
        }

        Window("FVoice Setup", id: "onboarding") {
            OnboardingView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

/// Hidden view that lives in the menu bar label (rendered at launch) and opens
/// the setup assistant automatically when onboarding is pending or a required
/// permission is missing.
private struct OnboardingLauncher: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let missingPermission =
                    AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
                    || IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
                    || !AXIsProcessTrusted()
                guard !state.store.settings.hasCompletedOnboarding || missingPermission else { return }
                // LSUIElement apps open windows behind everything unless activated.
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "onboarding")
                }
            }
    }
}
