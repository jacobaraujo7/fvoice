import Foundation
import MediaPlayer

/// Receives AirPods stem presses (and other remote play/pause commands) by
/// registering as the system's Now Playing app via MPRemoteCommandCenter.
/// While enabled, FVoice owns the stem press — media apps stop receiving it.
final class MediaKeyRemote {
    var onActivation: (() -> Void)?

    private var active = false
    private var targets: [(MPRemoteCommand, Any)] = []
    private var lastFire = Date.distantPast

    func enable() {
        guard !active else { return }
        active = true

        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand] {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                self?.fire()
                return .success
            }
            targets.append((command, target))
        }

        // macOS only treats us as the Now Playing app with explicit state.
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [MPMediaItemPropertyTitle: "FVoice — ditado"]
        info.playbackState = .playing
        DebugLog.log("media remote enabled (now playing app)")
    }

    func disable() {
        guard active else { return }
        active = false
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets.removeAll()
        let info = MPNowPlayingInfoCenter.default()
        info.playbackState = .stopped
        info.nowPlayingInfo = nil
        DebugLog.log("media remote disabled")
    }

    /// One stem press can arrive as more than one command — debounce.
    private func fire() {
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 0.4 else { return }
        lastFire = now
        DebugLog.log("media remote command received")
        DispatchQueue.main.async { [weak self] in
            self?.onActivation?()
        }
    }
}
