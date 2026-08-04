import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Geral", systemImage: "gearshape") }
            RecordingSettingsTab()
                .tabItem { Label("Gravação", systemImage: "mic") }
        }
        .frame(width: 460)
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
                        Text("Ditado 100% local, direto no cursor")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Transcrição") {
                if #available(macOS 26.0, *) {
                    SettingsRow(icon: "cpu", color: .purple, title: "Engine") {
                        Picker("", selection: state.binding(\.engine)) {
                            ForEach(EngineChoice.allCases) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Apple: mais rápido. Whisper: melhor com termos técnicos em inglês.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SettingsRow(icon: "cpu", color: .purple, title: "Engine") {
                        Text("Whisper large-v3 turbo")
                    }
                }

                SettingsRow(icon: "globe", color: .blue, title: "Idioma") {
                    Picker("", selection: state.binding(\.language)) {
                        Text("Português").tag("pt")
                        Text("Inglês").tag("en")
                        Text("Espanhol").tag("es")
                        Text("Detectar automaticamente").tag("auto")
                    }
                    .labelsHidden()
                }
            }

            Section("Sistema") {
                SettingsRow(icon: "power", color: .green, title: "Abrir no login") {
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

    var body: some View {
        Form {
            Section("Atalho") {
                SettingsRow(icon: "keyboard", color: .orange, title: "Atalho de gravação") {
                    HotkeyRecorderButton()
                }
                Text("Clique e pressione a combinação desejada (uma tecla + ao menos um modificador). Esc cancela.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsRow(icon: "airpods", color: .gray, title: "Botão dos AirPods grava") {
                    Toggle("", isOn: state.binding(\.mediaKeyToggle))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("Enquanto ligado, o apertão na haste não controla mais a música.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Inserção de texto") {
                SettingsRow(icon: "text.cursor", color: .red, title: "Modo") {
                    Picker("", selection: state.binding(\.insertMode)) {
                        ForEach(InsertMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
                if state.store.settings.insertMode == .hook {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Script do hook")
                        TextEditor(text: state.binding(\.hookScript))
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 90)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                        Text("Use {{text}} onde a transcrição deve entrar (também disponível como $FVOICE_TEXT). Roda em zsh, no lugar de digitar/colar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                SettingsRow(icon: "doc.on.clipboard", color: .indigo, title: "Copiar para o clipboard") {
                    Toggle("", isOn: state.binding(\.copyToClipboard))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow(icon: "return", color: .teal, title: "Enter automático") {
                    Toggle("", isOn: state.binding(\.autoEnter))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("Útil para enviar o prompt direto ao Claude Code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
            Text(armed ? "Pressione as teclas…" : state.store.settings.keyChord.display)
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
            defer {} // events are always swallowed while armed
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
