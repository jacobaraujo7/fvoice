import SwiftUI

/// Floating voice-reactive waveform shown near the bottom of the screen while
/// recording. Non-activating, click-through.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private let levels = LevelStore()

    /// Feed the current mic level (0...1).
    func update(level: Float) {
        levels.push(level)
    }

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }

        let width: CGFloat = 120
        let height: CGFloat = 36
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.minY + 80,
            width: width,
            height: height
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
        panel.contentView = NSHostingView(rootView: VoiceWaveView(levels: levels))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        levels.reset()
    }
}

/// Rolling buffer of recent mic levels — one bar per slot.
@MainActor
final class LevelStore: ObservableObject {
    static let barCount = 13

    @Published private(set) var bars = [Float](repeating: 0, count: LevelStore.barCount)

    func push(_ level: Float) {
        bars.removeFirst()
        bars.append(level)
    }

    func reset() {
        bars = [Float](repeating: 0, count: Self.barCount)
    }
}

private struct VoiceWaveView: View {
    @ObservedObject var levels: LevelStore

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(levels.bars.indices, id: \.self) { index in
                Capsule()
                    .fill(.red)
                    .frame(width: 4, height: barHeight(levels.bars[index]))
            }
        }
        .animation(.easeOut(duration: 0.12), value: levels.bars)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func barHeight(_ level: Float) -> CGFloat {
        4 + CGFloat(min(1, level)) * 20
    }
}
