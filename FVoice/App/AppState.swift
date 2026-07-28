import AVFoundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case idle
        case recording
        case needsInputMonitoring
        case needsMicrophone
        case error(String)
        case saved(String)
    }

    @Published var status: Status = .idle

    var isRecording: Bool { status == .recording }

    private let hotkey: HotkeyMonitor = GlobalHotkeyMonitor()
    private let recorder: AudioCaptureService = MicRecorder()

    init() {
        hotkey.onActivation = { [weak self] in self?.toggle() }
        if !hotkey.start() {
            status = .needsInputMonitoring
        }
        requestMicrophoneIfNeeded()
    }

    private func requestMicrophoneIfNeeded() {
        DebugLog.log("mic auth status = \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)")
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    if !granted, self?.status == .idle { self?.status = .needsMicrophone }
                }
            }
        default:
            if status == .idle { status = .needsMicrophone }
        }
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func retryHotkey() {
        if hotkey.start() {
            if status == .needsInputMonitoring { status = .idle }
        } else {
            status = .needsInputMonitoring
        }
    }

    func toggle() {
        if recorder.isRecording {
            do {
                let url = try recorder.stopRecording()
                status = .saved(url.path)
                NSSound(named: "Pop")?.play()
            } catch {
                status = .error("\(error)")
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard granted else {
                        self.status = .error("Permissão de microfone negada")
                        return
                    }
                    do {
                        try self.recorder.startRecording()
                        self.status = .recording
                        NSSound(named: "Tink")?.play()
                    } catch {
                        self.status = .error("\(error)")
                    }
                }
            }
        }
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
