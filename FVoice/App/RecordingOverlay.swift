import SwiftUI

/// Small floating pulsing red dot shown near the bottom of the screen while
/// recording. Non-activating, click-through.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }

        let size: CGFloat = 28
        let frame = NSRect(
            x: screen.frame.midX - size / 2,
            y: screen.frame.minY + 80,
            width: size,
            height: size
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PulsingDot())
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .scaleEffect(pulsing ? 1.0 : 0.6)
            .opacity(pulsing ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .padding(4)
    }
}
