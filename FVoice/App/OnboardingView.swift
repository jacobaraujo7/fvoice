import AVFoundation
import IOKit.hid
import SwiftUI

/// First-launch setup assistant: welcome, engine choice, permissions, shortcut test.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var micGranted = false
    @State private var inputMonitoringGranted = false
    @State private var accessibilityGranted = false

    private let stepCount = 4
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: engineStep
                case 2: permissionsStep
                default: shortcutStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .onAppear {
            refreshPermissions()
            if state.store.settings.hasCompletedOnboarding, !allPermissionsGranted {
                step = 2
            }
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("onboarding") == true }) {
                // Menu bar app: keep this window above others or it gets lost.
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
            }
        }
        .onReceive(timer) { _ in refreshPermissions() }
    }

    // MARK: - Header

    private var stepIndicator: some View {
        HStack(spacing: 10) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to FVoice")
                .font(.largeTitle.bold())
            Text("100% local dictation, straight to your cursor")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: Language and engine

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Language and engine")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text("Language")
                Spacer()
                Picker("", selection: state.binding(\.language)) {
                    Text("Portuguese").tag("pt")
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Italian").tag("it")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Chinese").tag("zh")
                    Text("Russian").tag("ru")
                    Text("Auto-detect").tag("auto")
                }
                .labelsHidden()
                .frame(width: 200)
            }

            HStack(spacing: 12) {
                engineCard(
                    choice: .apple,
                    title: "Apple SpeechTranscriber",
                    subtitle: "Ready in seconds, minimal RAM, faster",
                    icon: "apple.logo"
                )
                engineCard(
                    choice: .whisper,
                    title: "Whisper",
                    subtitle: "Best accuracy with technical jargon",
                    icon: "waveform"
                )
            }

            if state.store.settings.engine == .whisper {
                HStack {
                    Text("Whisper model")
                    Spacer()
                    Picker("", selection: state.binding(\.whisperModel)) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.label).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 340)
                }
            }
        }
    }

    private func engineCard(choice: EngineChoice, title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String) -> some View {
        let selected = state.store.settings.engine == choice
        return Button {
            state.store.settings.engine = choice
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 4) {
                Text("Permissions")
                    .font(.title2.bold())
                engineStatusLine
            }
            .frame(maxWidth: .infinity)

            permissionRow(
                granted: micGranted,
                title: "Microphone",
                detail: "Needed to record your voice."
            ) {
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    Button("Allow") {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            Task { @MainActor in refreshPermissions() }
                        }
                    }
                } else {
                    Button("Open Settings") { state.openMicrophoneSettings() }
                }
            }

            permissionRow(
                granted: accessibilityGranted,
                title: "Accessibility",
                detail: "Needed to type the transcription at your cursor."
            ) {
                Button("Allow") { state.requestAccessibilityAccess() }
            }
        }
    }

    @ViewBuilder
    private var engineStatusLine: some View {
        switch state.status {
        case .downloading(let fraction):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Downloading model… \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .warming:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading model…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private func permissionRow<Actions: View>(
        granted: Bool,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { actions() }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step 4: Shortcut and test

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcut and test")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text("Recording shortcut")
                Spacer()
                HotkeyRecorderButton(placeholderUntilRecorded: true)
            }
            Text("Click and press the combination you want to use (a key plus at least one modifier). Esc cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                permissionRow(
                    granted: inputMonitoringGranted,
                    title: "Input Monitoring",
                    detail: "Needed so the shortcut works in any app."
                ) {
                    Button("Allow") { state.requestInputMonitoringAccess() }
                }
                if !inputMonitoringGranted {
                    HStack(spacing: 8) {
                        Text("If FVoice is not in the list, add it with the + button pointing to the app. macOS requires relaunching FVoice after granting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Relaunch FVoice") { relaunch() }
                            .font(.caption)
                    }
                    .padding(.leading, 30)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Try it: press the shortcut and say something.")
                    .font(.headline)
                if let latest = state.history.first {
                    Text(latest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Label("It works!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout.bold())
                } else {
                    Text("Your transcription will appear here.")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            if step < stepCount - 1 {
                Button("Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 2 && !(micGranted && accessibilityGranted))
            } else {
                Button("Finish") {
                    state.store.settings.hasCompletedOnboarding = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!inputMonitoringGranted)
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var allPermissionsGranted: Bool {
        micGranted && inputMonitoringGranted && accessibilityGranted
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
