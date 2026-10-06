import Foundation
import MirrorKit

/// Mirror: the broadcast extension streams the iPhone screen to the car display.
extension AppModel {
    static let broadcastExtensionID = "com.bharathkgowda.carplaytv.broadcast"

    func startMirrorListener() {
        mirror.onActiveChange = { [weak self] active in
            guard let self else { return }
            self.isMirroring = active
            if active {
                // The mirrored app brings its own audio; pause ours.
                self.player.pause()
                self.activity.mirroringStarted()
            } else {
                self.activity.end()
            }
        }
        do {
            try mirror.start()
        } catch {
            mirrorError = "Screen mirroring isn't available: \(error.localizedDescription)"
        }
    }

    func stopMirroring() {
        mirror.disconnect()
    }
}
