import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch state.status {
        case .downloading(let fraction):
            Text("Baixando modelo… \(Int(fraction * 100))%")
        case .warming:
            Text("Carregando modelo…")
        case .idle:
            Text("Pronto — \(state.store.settings.keyChord.display) para gravar")
        case .recording:
            Text("Gravando… \(state.store.settings.keyChord.display) para parar")
        case .transcribing:
            Text("Transcrevendo…")
        case .error(let message):
            Text("Erro: \(message)")
        case .needsMicrophone:
            Text("Sem permissão de Microfone")
            Button("Abrir Ajustes de Microfone") {
                state.openMicrophoneSettings()
            }
        case .needsInputMonitoring:
            Text("Sem permissão de Input Monitoring")
            Button("Abrir Ajustes de Privacidade") {
                state.openInputMonitoringSettings()
            }
            Button("Tentar de novo") {
                state.retryHotkey()
            }
        }

        Button(state.isRecording ? "Parar gravação" : "Gravar") {
            state.toggle()
        }
        if state.isRecording {
            Button("Cancelar (Esc)") {
                state.cancelRecording()
            }
        }

        Divider()
        Button("Configurações…") {
            // LSUIElement apps open windows behind everything unless activated.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Sair") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
