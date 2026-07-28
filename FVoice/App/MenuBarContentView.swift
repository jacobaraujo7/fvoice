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
            Text("Pronto — ⌥Space para gravar")
        case .recording:
            Text("Gravando… ⌥Space para parar")
        case .transcribing:
            Text("Transcrevendo…")
        case .result(let text):
            Text(text.count > 60 ? String(text.prefix(60)) + "…" : text)
            Text("(copiado para o clipboard)")
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
