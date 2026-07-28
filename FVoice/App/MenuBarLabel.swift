import SwiftUI

/// Status-bar icon. Animation is done by swapping SF Symbol frames on a timer
/// (AppState.animPhase) — symbolEffect doesn't animate in MenuBarExtra labels.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    private static let loadingFrames = [
        "hourglass",
        "hourglass.tophalf.filled",
        "hourglass.bottomhalf.filled",
    ]
    private static let transcribingFrames = [
        "waveform.circle",
        "waveform.circle.fill",
    ]
    private static let recordingFrames = [
        "record.circle.fill",
        "record.circle",
    ]

    var body: some View {
        switch state.status {
        case .downloading(let fraction):
            HStack(spacing: 2) {
                Image(systemName: frame(Self.loadingFrames))
                Text("\(Int(fraction * 100))%")
                    .font(.caption2.monospacedDigit())
            }
        case .warming:
            Image(systemName: frame(Self.loadingFrames))
        case .transcribing:
            Image(systemName: frame(Self.transcribingFrames))
        case .recording:
            Image(systemName: frame(Self.recordingFrames))
        default:
            Image(systemName: "waveform")
        }
    }

    private func frame(_ frames: [String]) -> String {
        frames[state.animPhase % frames.count]
    }
}
