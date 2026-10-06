import Foundation
import Observation

/// User preferences, stored in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var hideDeadChannels: Bool { didSet { defaults.set(hideDeadChannels, forKey: Keys.hideDead) } }
    var healthCheckEnabled: Bool { didSet { defaults.set(healthCheckEnabled, forKey: Keys.healthCheck) } }
    var preferSoftwareDecoder: Bool { didSet { defaults.set(preferSoftwareDecoder, forKey: Keys.software) } }
    var hasAcceptedSafetyNotice: Bool { didSet { defaults.set(hasAcceptedSafetyNotice, forKey: Keys.safety) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.hideDead: true, Keys.healthCheck: true])
        hideDeadChannels = defaults.bool(forKey: Keys.hideDead)
        healthCheckEnabled = defaults.bool(forKey: Keys.healthCheck)
        preferSoftwareDecoder = defaults.bool(forKey: Keys.software)
        hasAcceptedSafetyNotice = defaults.bool(forKey: Keys.safety)
    }

    /// Stable per-install identifier sent to Jellyfin/Emby as the device ID.
    var deviceID: String {
        if let existing = defaults.string(forKey: Keys.deviceID) { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: Keys.deviceID)
        return created
    }

    private enum Keys {
        static let hideDead = "hideDeadChannels"
        static let healthCheck = "healthCheckEnabled"
        static let software = "preferSoftwareDecoder"
        static let safety = "hasAcceptedSafetyNotice"
        static let deviceID = "deviceID"
    }
}
