import Foundation
import PlaybackKit
import ReceiverKit
import SourcesKit
import UIKit

/// Receive: other apps cast to CarPlayTV over UPnP/DLNA, and we play on the car display.
extension AppModel: MediaRendererDelegate {
    var receiverName: String { "CarPlayTV (\(UIDevice.current.name))" }

    func startReceiver() async {
        guard receiver == nil else { return }
        let service = MediaRendererService(friendlyName: receiverName, udn: settings.deviceID, delegate: self)
        do {
            try await service.start()
            receiver = service
            receiverError = nil
        } catch {
            receiverError = error.localizedDescription
        }
    }

    func stopReceiver() {
        receiver?.stop()
        receiver = nil
        activity.end()
    }

    /// The Live Activity's Stop button: end receiving and mirroring.
    func stopCasting() {
        if player.currentChannel?.group == "Cast" { player.stop() }
        stopReceiver()
        stopMirroring()
        castingSessionEnded()
    }

    // MARK: - MediaRendererDelegate

    func renderer(load url: URL, title: String?) {
        let isStream = url.pathExtension.lowercased() == "m3u8" && title == nil
        let channel = Channel(
            id: "cast:" + url.absoluteString,
            name: title ?? url.lastPathComponent,
            group: "Cast",
            streamURLs: [url],
            kind: isStream ? .live : .movie
        )
        play(channel)
        activity.castStarted(title: channel.name)
        castingSessionStarted()
    }

    func rendererPlay() { player.resume() }
    func rendererPause() { player.pause() }

    func rendererStop() {
        player.stop()
        activity.end()
        castingSessionEnded()
    }

    func renderer(seekTo seconds: Double) { player.seek(to: seconds) }
    func rendererSetVolume(_ volume: Int) { player.setVolume(Float(volume) / 100) }

    func rendererStatus() -> RendererStatus {
        let state: RendererStatus.State
        if player.currentChannel == nil {
            state = .noMedia
        } else if player.isLoading {
            state = .transitioning
        } else if player.isPlaying {
            state = .playing
        } else if player.errorMessage != nil {
            state = .stopped
        } else {
            state = .paused
        }
        return RendererStatus(state: state, position: player.currentTime, duration: player.duration)
    }
}
