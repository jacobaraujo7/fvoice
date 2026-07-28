import AVFoundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case downloading(Double)
        case warming
        case idle
        case recording
        case transcribing
        case result(String)
        case needsInputMonitoring
        case needsMicrophone
        case error(String)
    }

    @Published var status: Status = .warming

    var isRecording: Bool { status == .recording }

    private let hotkey: HotkeyMonitor = GlobalHotkeyMonitor()
    private let recorder: AudioCaptureService = MicRecorder()
    private let engine: TranscriptionEngine = WhisperKitEngine()
    private let inserter: TextInserter = TypingTextInserter()
    private let overlay = RecordingOverlay()
    private var engineReady = false

    init() {
        hotkey.onActivation = { [weak self] in self?.toggle() }
        if !hotkey.start() {
            status = .needsInputMonitoring
        }
        requestMicrophoneIfNeeded()
        requestAccessibilityIfNeeded()
        prepareEngine()
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DebugLog.log("accessibility trusted = \(trusted)")
    }

    private func prepareEngine() {
        Task {
            do {
                try await engine.prepare { [weak self] fraction in
                    Task { @MainActor in
                        if fraction < 1.0 { self?.status = .downloading(fraction) }
                    }
                }
                engineReady = true
                if !isRecording { status = .idle }
            } catch {
                status = .error("Falha ao carregar modelo: \(error.localizedDescription)")
                DebugLog.log("engine prepare failed: \(error)")
            }
        }
    }

    private func requestMicrophoneIfNeeded() {
        DebugLog.log("mic auth status = \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)")
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    if !granted { self?.status = .needsMicrophone }
                }
            }
        default:
            status = .needsMicrophone
        }
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
            overlay.hide()
            do {
                let url = try recorder.stopRecording()
                NSSound(named: "Pop")?.play()
                transcribe(url: url)
            } catch {
                status = .error("\(error)")
            }
        } else {
            guard engineReady else { return }
            do {
                try recorder.startRecording()
                status = .recording
                overlay.show()
                NSSound(named: "Tink")?.play()
            } catch {
                status = .error("\(error)")
            }
        }
    }

    private func transcribe(url: URL) {
        status = .transcribing
        Task {
            do {
                let text = try await engine.transcribe(wavURL: url)
                if text.isEmpty {
                    status = .idle
                } else {
                    inserter.insert(text)
                    status = .result(text)
                    NSSound(named: "Glass")?.play()
                }
            } catch {
                status = .error("Transcrição falhou: \(error.localizedDescription)")
                DebugLog.log("transcribe failed: \(error)")
            }
        }
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
