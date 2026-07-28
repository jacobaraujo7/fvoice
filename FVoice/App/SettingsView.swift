import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Picker("Hotkey (toggle)", selection: binding(\.hotkey)) {
                ForEach(HotkeyChord.allCases) { chord in
                    Text(chord.label).tag(chord)
                }
            }

            Picker("Idioma", selection: binding(\.language)) {
                Text("Português").tag("pt")
                Text("Inglês").tag("en")
                Text("Espanhol").tag("es")
                Text("Detectar automaticamente").tag("auto")
            }

            Picker("Inserção de texto", selection: binding(\.insertMode)) {
                ForEach(InsertMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Toggle("Botão dos AirPods (Play/Pause) grava", isOn: binding(\.mediaKeyToggle))
            Text("Enquanto ligado, o apertão na haste não controla mais a música.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enter automático após inserir", isOn: binding(\.autoEnter))
            Text("Útil para enviar o prompt direto ao Claude Code.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Abrir no login", isOn: binding(\.launchAtLogin))

            LabeledContent("Modelo", value: "large-v3 turbo (fixo na v1)")
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { state.store.settings[keyPath: keyPath] },
            set: { state.store.settings[keyPath: keyPath] = $0 }
        )
    }
}
