import SwiftUI

struct MenuBarContentView: View {
    var body: some View {
        Text("FVoice — pronto")
        Divider()
        Button("Sair") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
