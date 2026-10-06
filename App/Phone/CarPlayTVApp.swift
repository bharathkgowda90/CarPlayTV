import PlaybackKit
import SwiftUI

@main
struct CarPlayTVApp: App {
    init() {
        PlayerController.configureAudioSession()
        AppModel.shared.driveMonitor.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
        }
    }
}
