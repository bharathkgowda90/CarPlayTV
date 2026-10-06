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
            ContentView()
                .environment(AppModel.shared)
        }
    }
}
