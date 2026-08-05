import SwiftUI

/// Floating voice-reactive waveform shown near the bottom of the screen while
/// recording. Non-activating, click-through.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private let levels = LevelStore()
    private var timer: Timer?
    private var startedAt: Date?

    /// Feed the current mic level (0...1).
    func update(level: Float) {
        levels.push(level)
    }

    func show() {
        guard panel == nil, let screen = NSScreen.main else { return }

        startedAt = Date()
        levels.elapsed = "0:00"
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                let seconds = Int(Date().timeIntervalSince(startedAt))
                self.levels.elapsed = String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
        }

        let width: CGFloat = 164
        let height: CGFloat = 36
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.visibleFrame.maxY - height - 12,
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
        timer?.invalidate()
        timer = nil
        startedAt = nil
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
    @Published var elapsed = "0:00"

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
            Text(levels.elapsed)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, 5)
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
