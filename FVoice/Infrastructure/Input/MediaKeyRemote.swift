import AVFoundation
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
    /// Looping silent player: macOS only routes remote commands (AirPods stem
    /// press) to apps that are actually producing audio; playbackState alone
    /// is not enough.
    private var silentPlayer: AVAudioPlayer?

    func enable() {
        guard !active else { return }
        active = true

        let center = MPRemoteCommandCenter.shared()
        let commands: [(String, MPRemoteCommand)] = [
            ("togglePlayPause", center.togglePlayPauseCommand),
            ("play", center.playCommand),
            ("pause", center.pauseCommand),
            ("stop", center.stopCommand),
        ]
        for (name, command) in commands {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                DebugLog.log("media remote command: \(name)")
                self?.fire()
                return .success
            }
            targets.append((command, target))
        }

        startSilentAudio()

        // macOS only treats us as the Now Playing app with explicit state.
        // Without playbackRate/duration the system considers us paused and
        // won't route remote commands.
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "FVoice dictation",
            MPMediaItemPropertyPlaybackDuration: 3600.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        info.playbackState = .playing
        DebugLog.log("media remote enabled (now playing app, silent loop running)")
    }

    private func startSilentAudio() {
        guard silentPlayer == nil else { return }
        do {
            let player = try AVAudioPlayer(data: Self.silentWavData())
            player.numberOfLoops = -1
            player.volume = 0
            player.play()
            silentPlayer = player
        } catch {
            DebugLog.log("silent audio failed: \(error)")
        }
    }

    /// One second of 16kHz mono 16-bit silence as a WAV file in memory.
    private static func silentWavData() -> Data {
        let sampleRate: UInt32 = 16_000
        let dataSize: UInt32 = sampleRate * 2
        var data = Data()
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(16)
        append16(1); append16(1)                    // PCM, mono
        append(sampleRate); append(sampleRate * 2)  // byte rate
        append16(2); append16(16)                   // block align, bits
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    func disable() {
        guard active else { return }
        active = false
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets.removeAll()
        silentPlayer?.stop()
        silentPlayer = nil
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
