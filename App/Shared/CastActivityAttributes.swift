import ActivityKit
import AppIntents
import Foundation

/// Shared by the app and the widget extension: the Lock Screen Live Activity shown
/// while CarPlayTV is receiving a cast or mirroring the screen.
struct CastActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Mode: String, Codable, Hashable {
            case receiving, mirroring
        }

        var mode: Mode
        var title: String
        var isPlaying: Bool
    }
}

extension Notification.Name {
    static let carPlayTVStopCasting = Notification.Name("CarPlayTV.StopCasting")
}

/// The Live Activity's Stop button. Live Activity intents run in the app's process.
struct StopCastingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop casting"
    static let description = IntentDescription("Stops receiving casts and screen mirroring in CarPlayTV.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .carPlayTVStopCasting, object: nil)
        }
        return .result()
    }
}
