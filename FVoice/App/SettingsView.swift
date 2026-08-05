import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            RecordingSettingsTab()
                .tabItem { Label("Recording", systemImage: "mic") }
            HistoryTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 580, height: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Tabs

private struct GeneralSettingsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FVoice").font(.headline)
                        Text("100% local dictation, straight to your cursor")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Transcription") {
                if #available(macOS 26.0, *) {
                    SettingsRow(icon: "cpu", color: .purple, title: "Engine") {
                        Picker("", selection: state.binding(\.engine)) {
                            ForEach(EngineChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Apple: faster. Whisper: better with technical terms.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SettingsRow(icon: "cpu", color: .purple, title: "Engine") {
                        Text("Whisper large-v3 turbo")
                    }
                }

                if state.store.settings.engine == .whisper {
                    SettingsRow(icon: "memorychip", color: .brown, title: "Whisper model") {
                        Picker("", selection: state.binding(\.whisperModel)) {
                            ForEach(WhisperModel.allCases) { model in
                                Text(model.label).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("RAM stays in use while FVoice runs. Smaller models respond faster but miss more jargon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsRow(icon: "globe", color: .blue, title: "Language") {
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
                }
                Text("Auto-detect works on Whisper only; the Apple engine falls back to the system language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Vocabulary hints")
                    TextField("", text: state.binding(\.vocabulary),
                              prompt: Text("Comma-separated jargon, e.g. worktree, refactor, staging (Whisper only)"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
            }

            Section("System") {
                SettingsRow(icon: "power", color: .green, title: "Launch at login") {
                    Toggle("", isOn: state.binding(\.launchAtLogin))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct RecordingSettingsTab: View {
    @EnvironmentObject var state: AppState

    private var microphones: [AudioDeviceList.Device] {
        AudioDeviceList.inputDevices()
    }

    var body: some View {
        Form {
            Section("Shortcut") {
                SettingsRow(icon: "keyboard", color: .orange, title: "Recording shortcut") {
                    HotkeyRecorderButton()
                }
                Text("Click, then press the desired combination (a key plus at least one modifier). Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsRow(icon: "hand.tap", color: .pink, title: "Push to talk") {
                    Toggle("", isOn: state.binding(\.pushToTalk))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("Hold the shortcut to record, release to transcribe. Off: press once to start, again to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsRow(icon: "airpods", color: .gray, title: "AirPods button records") {
                    Toggle("", isOn: state.binding(\.mediaKeyToggle))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("While on, the stem press no longer controls media playback. Always toggle mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Input") {
                SettingsRow(icon: "mic", color: .cyan, title: "Microphone") {
                    Picker("", selection: state.binding(\.preferredMicUID)) {
                        Text("System default").tag("")
                        ForEach(microphones) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                }
                Text("Pin the Mac's microphone to keep full quality while wearing AirPods.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text insertion") {
                SettingsRow(icon: "text.cursor", color: .red, title: "Mode") {
                    Picker("", selection: state.binding(\.insertMode)) {
                        ForEach(InsertMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
                if state.store.settings.insertMode == .hook {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hook script")
                        TextEditor(text: state.binding(\.hookScript))
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                        Text("Use {{text}} where the transcription goes (also available as $FVOICE_TEXT). Runs in zsh instead of typing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                SettingsRow(icon: "doc.on.clipboard", color: .indigo, title: "Copy to clipboard") {
                    Toggle("", isOn: state.binding(\.copyToClipboard))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(icon: "return", color: .teal, title: "Auto Enter") {
                    Toggle("", isOn: state.binding(\.autoEnter))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("Sends the prompt straight to Claude Code after inserting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HistoryTab: View {
    @EnvironmentObject var state: AppState
    @State private var copiedIndex: Int?

    var body: some View {
        Group {
            if state.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No transcriptions yet")
                        .foregroundStyle(.secondary)
                    Text("Your last 10 dictations of this session appear here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        ForEach(Array(state.history.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text(item)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(item, forType: .string)
                                    copiedIndex = index
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        if copiedIndex == index { copiedIndex = nil }
                                    }
                                } label: {
                                    Image(systemName: copiedIndex == index ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help("Copy")
                            }
                            .padding(.vertical, 2)
                        }
                    } footer: {
                        HStack {
                            Spacer()
                            Button("Clear history") {
                                state.history.removeAll()
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}

// MARK: - Components

/// System Settings style row: colored icon badge + title + trailing control.
private struct SettingsRow<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        LabeledContent {
            content
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
                Text(title)
            }
        }
    }
}

/// Button that captures the next key combination pressed.
private struct HotkeyRecorderButton: View {
    @EnvironmentObject var state: AppState
    @State private var armed = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            armed ? disarm() : arm()
        } label: {
            Text(armed ? "Press keys…" : state.store.settings.keyChord.display)
                .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .tint(armed ? .orange : nil)
        .onDisappear { disarm() }
    }

    private func arm() {
        armed = true
        state.suspendHotkey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc cancels
                disarm()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else {
                NSSound.beep()
                return nil
            }
            var chord = KeyChord(keyCode: event.keyCode)
            chord.command = flags.contains(.command)
            chord.option = flags.contains(.option)
            chord.control = flags.contains(.control)
            chord.shift = flags.contains(.shift)
            state.store.settings.keyChord = chord
            disarm()
            return nil
        }
    }

    private func disarm() {
        armed = false
        state.suspendHotkey(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
