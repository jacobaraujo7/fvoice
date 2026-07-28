import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        switch state.status {
        case .idle:
            Text("Pronto — ⌥⌘ para gravar")
        case .recording:
            Text("Gravando… ⌥⌘ para parar")
        case .saved(let path):
            Text("Salvo: \((path as NSString).lastPathComponent)")
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
        Button("Sair") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
