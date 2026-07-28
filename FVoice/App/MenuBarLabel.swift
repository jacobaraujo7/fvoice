import SwiftUI

/// Status-bar icon: animated while the model is downloading/loading and while
/// transcribing, red dot while recording.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        switch state.status {
        case .downloading(let fraction):
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.circle")
                    .symbolEffect(.pulse, options: .repeating)
                Text("\(Int(fraction * 100))%")
                    .font(.caption2.monospacedDigit())
            }
        case .warming:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
        case .transcribing:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .recording:
            Image(systemName: "record.circle.fill")
                .symbolEffect(.pulse, options: .repeating)
        default:
            Image(systemName: "waveform")
        }
    }
}
