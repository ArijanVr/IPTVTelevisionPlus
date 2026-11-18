#if os(iOS)
import ARJOCore
import ARJOPlayer
import MediaPlayer
import Observation

/// Meldet den laufenden Sender an «Läuft gerade» (Sperrbildschirm, CarPlay) und nimmt Fernbedienungsbefehle an.
@MainActor
final class NowPlayingPublisher {
    static let shared = NowPlayingPublisher()
    private weak var live: LiveTVViewModel?
    private var isObserving = false

    func attach(live: LiveTVViewModel) {
        self.live = live
        configureCommands()
        if !isObserving { isObserving = true; observe() }
        publish()
    }

    private func observe() {
        withObservationTracking {
            _ = live?.nowPlaying
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.observe()
            }
        }
    }

    private func publish() {
        let center = MPNowPlayingInfoCenter.default()
        guard let live, let channel = live.nowPlaying else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let now = live.epg.nowNext(for: channel)?.now { info[MPMediaItemPropertyArtist] = now.title }
        center.nowPlayingInfo = info
    }

    private func configureCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.step(1) ?? .commandFailed }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.step(-1) ?? .commandFailed }
        commands.playCommand.addTarget { [weak self] _ in self?.setPlaying(true) ?? .commandFailed }
        commands.pauseCommand.addTarget { [weak self] _ in self?.setPlaying(false) ?? .commandFailed }
    }

    private func step(_ offset: Int) -> MPRemoteCommandHandlerStatus {
        guard let live, live.nowPlaying != nil else { return .noActionableNowPlayingItem }
        live.playAdjacent(offset: offset)
        return .success
    }

    private func setPlaying(_ play: Bool) -> MPRemoteCommandHandlerStatus {
        guard let live, live.nowPlaying != nil, live.engine.backend == .avPlayer else { return .noActionableNowPlayingItem }
        if play { live.engine.player.play() } else { live.engine.player.pause() }
        return .success
    }
}
#endif
