import PlaybackKit
import SwiftUI

/// SwiftUI wrapper that registers a `VideoHostView` with the player while on screen.
struct VideoSurface: UIViewRepresentable {
    let player: PlayerController
    var priority = 0

    func makeUIView(context: Context) -> VideoHostView {
        let host = VideoHostView(priority: priority)
        player.register(host)
        return host
    }

    func updateUIView(_ host: VideoHostView, context: Context) {}

    static func dismantleUIView(_ host: VideoHostView, coordinator: ()) {
        MainActor.assumeIsolated {
            AppModel.shared.player.unregister(host)
        }
    }
}
