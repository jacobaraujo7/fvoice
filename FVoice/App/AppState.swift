import AVFoundation
import Combine
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

    let store = SettingsStore()

    private let hotkey = GlobalHotkeyMonitor()
    private let recorder: AudioCaptureService = MicRecorder()
    private let engine: TranscriptionEngine = WhisperKitEngine()
    private let typingInserter: TextInserter = TypingTextInserter()
    private let pasteInserter: TextInserter = PasteTextInserter()
    private let overlay = RecordingOverlay()
    private var engineReady = false
    private var settingsObserver: AnyCancellable?

    private var inserter: TextInserter {
        store.settings.insertMode == .paste ? pasteInserter : typingInserter
    }

    init() {
        hotkey.chord = store.settings.hotkey
        hotkey.mediaKeyEnabled = store.settings.mediaKeyToggle
        settingsObserver = store.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.hotkey.mediaKeyEnabled = settings.mediaKeyToggle
                if self.hotkey.chord != settings.hotkey {
                    self.hotkey.chord = settings.hotkey
                    self.hotkey.stop()
                    self.hotkey.start()
                }
            }
        hotkey.onActivation = { [weak self] in self?.toggle() }
        recorder.onInterrupted = { [weak self] in
            guard let self else { return }
            self.overlay.hide()
            self.status = .error("Microfone trocado — gravação cancelada")
            NSSound(named: "Basso")?.play()
        }
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
                if recorder.lastSpeechSeconds < TranscriptionFilter.minimumSpeechSeconds {
                    DebugLog.log("skipped transcription — only \(String(format: "%.2f", recorder.lastSpeechSeconds))s of speech")
                    status = .idle
                } else {
                    transcribe(url: url)
                }
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
                let raw = try await engine.transcribe(wavURL: url, language: store.settings.language)
                if let text = TranscriptionFilter.clean(raw, speechSeconds: recorder.lastSpeechSeconds) {
                    inserter.insert(text)
                    if store.settings.autoEnter {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            KeyPress.pressReturn()
                        }
                    }
                    status = .result(text)
                    NSSound(named: "Glass")?.play()
                } else {
                    status = .idle
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
