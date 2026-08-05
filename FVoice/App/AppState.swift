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
        case needsInputMonitoring
        case needsMicrophone
        case error(String)
    }

    @Published var status: Status = .warming {
        didSet { updateAnimTimer() }
    }
    /// Drives the frame-swap animation of the menu bar icon (symbolEffect
    /// doesn't animate inside a MenuBarExtra label).
    @Published var animPhase = 0
    /// Last transcriptions, newest first (max 10).
    @Published var history: [String] = []
    private var animTimer: Timer?

    var isRecording: Bool { status == .recording }

    let store = SettingsStore()

    private let hotkey = GlobalHotkeyMonitor()
    private let mediaRemote = MediaKeyRemote()
    private let recorder: AudioCaptureService = MicRecorder()
    private let whisperKit = WhisperKitEngine()
    private var whisperEngine: TranscriptionEngine { whisperKit }
    private let appleEngine: TranscriptionEngine? = {
        if #available(macOS 26.0, *) { return AppleSpeechEngine() }
        return nil
    }()
    private var engine: TranscriptionEngine {
        store.settings.engine == .apple ? (appleEngine ?? whisperEngine) : whisperEngine
    }
    private var activeEngineChoice: EngineChoice = .whisper
    private var activeWhisperModel: WhisperModel = .turbo
    private let typingInserter: TextInserter = TypingTextInserter()
    private lazy var hookInserter: TextInserter = HookTextInserter { [weak self] in
        self?.store.settings.hookScript ?? ""
    }
    private let overlay = RecordingOverlay()
    private var engineReady = false
    private var settingsObserver: AnyCancellable?
    private var settingsForwarder: AnyCancellable?

    /// Safety net: stop and transcribe if a recording is left running.
    private static let maxRecordingSeconds: TimeInterval = 120
    private var autoStopTimer: Timer?

    private var inserter: TextInserter {
        store.settings.insertMode == .hook ? hookInserter : typingInserter
    }

    init() {
        // Re-publish SettingsStore changes so views observing AppState refresh.
        settingsForwarder = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        hotkey.keyChord = store.settings.keyChord
        hotkey.mediaKeyEnabled = store.settings.mediaKeyToggle
        mediaRemote.onActivation = { [weak self] in self?.toggle() }
        if store.settings.mediaKeyToggle { mediaRemote.enable() }
        settingsObserver = store.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.hotkey.mediaKeyEnabled = settings.mediaKeyToggle
                self.hotkey.pushToTalk = settings.pushToTalk
                settings.mediaKeyToggle ? self.mediaRemote.enable() : self.mediaRemote.disable()
                var reloadNeeded = false
                if settings.engine != self.activeEngineChoice {
                    self.activeEngineChoice = settings.engine
                    reloadNeeded = true
                }
                if settings.whisperModel != self.activeWhisperModel {
                    self.activeWhisperModel = settings.whisperModel
                    self.whisperKit.modelVariant = settings.whisperModel.variant
                    reloadNeeded = settings.engine == .whisper
                }
                if reloadNeeded {
                    self.engineReady = false
                    self.status = .warming
                    self.prepareEngine()
                }
                if self.hotkey.keyChord != settings.keyChord {
                    self.hotkey.keyChord = settings.keyChord
                    DebugLog.log("hotkey changed to \(settings.keyChord.display)")
                }
            }
        hotkey.pushToTalk = store.settings.pushToTalk
        hotkey.onActivation = { [weak self] in
            guard let self else { return }
            if self.store.settings.pushToTalk {
                if !self.recorder.isRecording { self.toggle() }
            } else {
                self.toggle()
            }
        }
        hotkey.onDeactivation = { [weak self] in
            guard let self, self.recorder.isRecording else { return }
            self.toggle()
        }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.escapeActive = { [weak self] in self?.isRecording ?? false }
        recorder.onLevel = { [weak self] level in
            self?.overlay.update(level: level)
        }
        recorder.onInterrupted = { [weak self] in
            guard let self else { return }
            self.overlay.hide()
            self.status = .error("Microphone changed, recording cancelled")
            NSSound(named: "Basso")?.play()
        }
        if !hotkey.start() {
            status = .needsInputMonitoring
        }
        registerInputMuteGesture()
        requestMicrophoneIfNeeded()
        requestAccessibilityIfNeeded()
        activeEngineChoice = store.settings.engine
        activeWhisperModel = store.settings.whisperModel
        whisperKit.modelVariant = store.settings.whisperModel.variant
        prepareEngine()
        updateAnimTimer()
    }

    private func updateAnimTimer() {
        let animating: Bool
        switch status {
        case .warming, .downloading, .transcribing, .recording: animating = true
        default: animating = false
        }
        if animating, animTimer == nil {
            animTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.animPhase += 1 }
            }
        } else if !animating {
            animTimer?.invalidate()
            animTimer = nil
        }
    }

    /// While the mic is live, AirPods switch to the call profile and the stem
    /// press becomes an input-mute gesture instead of play/pause. Handle it as
    /// "stop and transcribe".
    private func registerInputMuteGesture() {
        do {
            try AVAudioApplication.shared.setInputMuteStateChangeHandler { [weak self] muted in
                // Only the mute gesture (true) is the stem press. The false
                // events are our own unmute reset; acting on them loops.
                guard muted else { return true }
                DebugLog.log("input mute gesture received")
                Task { @MainActor in
                    guard let self else { return }
                    if self.recorder.isRecording { self.toggle() }
                    // Unmute so the next stem press fires the handler again.
                    try? AVAudioApplication.shared.setInputMuted(false)
                }
                return true
            }
        } catch {
            DebugLog.log("input mute handler registration failed: \(error)")
        }
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
                status = .error("Model load failed: \(error.localizedDescription)")
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

    /// Pauses the global hotkey while the Settings recorder captures keys.
    func suspendHotkey(_ suspended: Bool) {
        hotkey.suspended = suspended
    }

    func retryHotkey() {
        if hotkey.start() {
            if status == .needsInputMonitoring { status = .idle }
        } else {
            status = .needsInputMonitoring
        }
    }

    /// Discards the current recording without transcribing (Esc).
    func cancelRecording() {
        guard recorder.isRecording else { return }
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        overlay.hide()
        if let url = try? recorder.stopRecording() {
            try? FileManager.default.removeItem(at: url)
        }
        status = .idle
        NSSound(named: "Bottle")?.play()
        DebugLog.log("recording cancelled by user")
    }

    func toggle() {
        if recorder.isRecording {
            autoStopTimer?.invalidate()
            autoStopTimer = nil
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
                recorder.preferredDeviceUID = store.settings.preferredMicUID
                try recorder.startRecording()
                status = .recording
                overlay.show()
                NSSound(named: "Tink")?.play()
                autoStopTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.recorder.isRecording else { return }
                        DebugLog.log("auto-stop after \(Int(Self.maxRecordingSeconds))s")
                        self.toggle()
                    }
                }
            } catch {
                status = .error("\(error)")
            }
        }
    }

    private func transcribe(url: URL) {
        status = .transcribing
        Task {
            do {
                let trimmed = SilenceTrimmer.trim(url)
                let raw = try await engine.transcribe(
                    wavURL: trimmed,
                    language: store.settings.language,
                    vocabulary: store.settings.vocabulary
                )
                if trimmed != url { try? FileManager.default.removeItem(at: trimmed) }
                if let text = TranscriptionFilter.clean(raw, speechSeconds: recorder.lastSpeechSeconds) {
                    history.insert(text, at: 0)
                    if history.count > 10 { history.removeLast() }
                    if store.settings.copyToClipboard {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                    }
                    inserter.insert(text)
                    if store.settings.autoEnter, store.settings.insertMode != .hook {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            KeyPress.pressReturn()
                        }
                    }
                    NSSound(named: "Glass")?.play()
                }
                status = .idle
            } catch {
                status = .error("Transcription failed: \(error.localizedDescription)")
                DebugLog.log("transcribe failed: \(error)")
            }
        }
    }

    /// SwiftUI binding into a settings field.
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.store.settings[keyPath: keyPath] },
            set: { self.store.settings[keyPath: keyPath] = $0 }
        )
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
