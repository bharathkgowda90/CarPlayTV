#if os(iOS)
import MediaPlayer
import SourcesKit
import UIKit

/// Lock Screen / Control Center / car "Now Playing" info and remote commands.
@MainActor
final class NowPlayingCoordinator {
    private weak var controller: PlayerController?
    private var artworkTask: Task<Void, Never>?
    private var artworkChannelID: String?
    private var artwork: MPMediaItemArtwork?

    func bind(to controller: PlayerController) {
        self.controller = controller
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.previous() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.skip(by: 15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.controller?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.controller?.seek(to: position) }
            return .success
        }
    }

    func update(channel: Channel, isPlaying: Bool, time: Double, duration: Double?) {
        let center = MPRemoteCommandCenter.shared()
        let seekable = !channel.isLive && duration != nil
        center.changePlaybackPositionCommand.isEnabled = seekable
        center.skipForwardCommand.isEnabled = seekable
        center.skipBackwardCommand.isEnabled = seekable

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPNowPlayingInfoPropertyIsLiveStream: channel.isLive,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let group = channel.group { info[MPMediaItemPropertyAlbumTitle] = group }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if artworkChannelID == channel.id, let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if artworkChannelID != channel.id {
            loadArtwork(for: channel)
        }
    }

    func clear() {
        artworkTask?.cancel()
        artworkChannelID = nil
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(for channel: Channel) {
        artworkTask?.cancel()
        artworkChannelID = channel.id
        artwork = nil
        guard let url = channel.logoURL else { return }
        artworkTask = Task { [weak self] in
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = UIImage(data: data), !Task.isCancelled else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self, self.artworkChannelID == channel.id else { return }
            self.artwork = artwork
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
#endif
