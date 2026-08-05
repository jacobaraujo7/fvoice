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

    // Hybrid streaming: dictations under chunkSeconds are transcribed in one
    // pass (best quality); beyond that, completed chunks are transcribed while
    // the user is still speaking, cut at pause boundaries.
    private static let chunkSeconds: Double = 30
    private static let forceChunkSeconds: Double = 45
    private var processedOffset = 0
    private var partialTexts: [String] = []
    private var chunkChain: Task<Void, Never>?
    private var streamMonitor: Task<Void, Never>?

    private var inserter: TextInserter {
        store.settings.insertMode == .hook ? hookInserter : typingInserter
    }

    init() {
        // Re-publish SettingsStore changes so views observing AppState refresh.
        settingsForwarder = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        hotkey.keyChord = store.settings.keyChord
        settingsObserver = store.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.hotkey.pushToTalk = settings.pushToTalk
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
            self.status = .error(String(localized: "Microphone changed, recording cancelled"))
            NSSound(named: "Basso")?.play()
        }
        if !hotkey.start() {
            status = .needsInputMonitoring
        }
        checkMicrophone()
        checkAccessibility()
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

    /// Prompts live only in the onboarding buttons; at launch we just observe.
    private func checkAccessibility() {
        DebugLog.log("accessibility trusted = \(AXIsProcessTrusted())")
    }

    /// Onboarding: triggers the system Accessibility prompt.
    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Onboarding: registers the app in the Input Monitoring pane (and shows
    /// the system prompt when possible), then opens the pane. Attempting the
    /// event tap is what reliably makes the app show up in the list.
    func requestInputMonitoringAccess() {
        hotkey.requestAccess()
        openInputMonitoringSettings()
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
                status = .error(String(localized: "Model load failed: \(error.localizedDescription)"))
                DebugLog.log("engine prepare failed: \(error)")
            }
        }
    }

    private func checkMicrophone() {
        let auth = AVCaptureDevice.authorizationStatus(for: .audio)
        DebugLog.log("mic auth status = \(auth.rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)")
        // .notDetermined is left alone: the onboarding Allow button prompts.
        if auth == .denied || auth == .restricted {
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
        streamMonitor?.cancel()
        streamMonitor = nil
        chunkChain = nil
        partialTexts = []
        _ = try? recorder.stopRecording()
        status = .idle
        NSSound(named: "Bottle")?.play()
        DebugLog.log("recording cancelled by user")
    }

    func toggle() {
        if recorder.isRecording {
            autoStopTimer?.invalidate()
            autoStopTimer = nil
            overlay.hide()
            streamMonitor?.cancel()
            streamMonitor = nil
            do {
                let samples = try recorder.stopRecording()
                NSSound(named: "Pop")?.play()
                if recorder.lastSpeechSeconds < TranscriptionFilter.minimumSpeechSeconds {
                    DebugLog.log("skipped transcription — only \(String(format: "%.2f", recorder.lastSpeechSeconds))s of speech")
                    status = .idle
                } else {
                    let remainder = Array(samples[min(processedOffset, samples.count)...])
                    transcribe(remainder: remainder)
                }
            } catch {
                status = .error("\(error)")
            }
        } else {
            guard engineReady else { return }
            do {
                // The system-level input mute may be stuck on from earlier
                // sessions; a muted input records pure silence.
                try? AVAudioApplication.shared.setInputMuted(false)
                recorder.preferredDeviceUID = store.settings.preferredMicUID
                try recorder.startRecording()
                processedOffset = 0
                partialTexts = []
                chunkChain = nil
                startStreamMonitor()
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

    /// Streaming: every second, dispatch a completed chunk once enough
    /// unprocessed audio has accumulated, cutting at a pause boundary.
    private func startStreamMonitor() {
        streamMonitor?.cancel()
        streamMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.recorder.isRecording else { break }
                self.maybeDispatchChunk()
            }
        }
    }

    private func maybeDispatchChunk() {
        guard recorder.isRecording, engineReady else { return }
        let rate = MicRecorder.sampleRate
        let total = recorder.recordedSampleCount
        let unprocessedSeconds = Double(total - processedOffset) / rate
        guard unprocessedSeconds >= Self.chunkSeconds else { return }

        let region = recorder.recordedSamples(from: processedOffset, to: total)
        var cut = SilenceTrimmer.lastSilenceCut(in: region, sampleRate: rate)
        if cut == nil || cut! < Int(rate * 5) {
            // No usable pause yet; wait, unless speech has run on too long.
            guard unprocessedSeconds >= Self.forceChunkSeconds else { return }
            cut = region.count
        }
        let chunk = Array(region[..<cut!])
        processedOffset += cut!
        DebugLog.log(String(format: "stream: chunk %.1fs dispatched (offset now %.1fs)",
                            Double(chunk.count) / rate, Double(processedOffset) / rate))
        enqueue(chunk: chunk)
    }

    /// Chunks are transcribed strictly in order, each seeing the text so far.
    private func enqueue(chunk: [Float]) {
        let previous = chunkChain
        chunkChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let trimmed = SilenceTrimmer.trim(chunk, sampleRate: MicRecorder.sampleRate)
            do {
                let text = try await self.engine.transcribe(
                    samples: trimmed,
                    language: self.store.settings.language,
                    vocabulary: self.store.settings.vocabulary,
                    context: self.partialTexts.joined(separator: " ")
                )
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { self.partialTexts.append(clean) }
            } catch {
                DebugLog.log("stream chunk failed: \(error)")
            }
        }
    }

    private func transcribe(remainder: [Float]) {
        status = .transcribing
        Task {
            // Wait for in-flight chunks, then transcribe the tail with their
            // text as context and assemble the full result.
            await chunkChain?.value
            do {
                var tail = ""
                if !remainder.isEmpty {
                    let trimmed = SilenceTrimmer.trim(remainder, sampleRate: MicRecorder.sampleRate)
                    tail = try await engine.transcribe(
                        samples: trimmed,
                        language: store.settings.language,
                        vocabulary: store.settings.vocabulary,
                        context: partialTexts.joined(separator: " ")
                    )
                }
                let raw = (partialTexts + [tail])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                partialTexts = []
                chunkChain = nil
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
                status = .error(String(localized: "Transcription failed: \(error.localizedDescription)"))
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
