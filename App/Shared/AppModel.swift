import Foundation
import Observation
import PlaybackKit
import SafetyKit
import SourcesKit

/// App-wide state shared by the iPhone scene and the CarPlay scene.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let player = PlayerController()
    let driveMonitor = DriveStateMonitor()

    private(set) var channels: [Channel] = []
    private(set) var channelGroups: [ChannelGroup] = []
    private(set) var isLoading = false
    var loadError: String?
    var isCarConnected = false

    func loadPlaylist(from url: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await PlaylistLoader.load(from: url)
            channels = loaded
            channelGroups = ChannelGroup.grouping(loaded)
            loadError = nil
        } catch {
            loadError = "Couldn't load the playlist: \(error.localizedDescription)"
        }
    }

    func play(_ channel: Channel) {
        player.play(channel, in: channels)
    }
}
