import CoreLocation
import Observation

/// Watches the iPhone's speed and decides whether video may be shown on the car display.
@MainActor
@Observable
public final class DriveStateMonitor {
    public private(set) var state: DriveState = .unknown

    /// Video is blocked only while moving. When location is unavailable the state stays
    /// `.unknown` and video is allowed (the app also shows a passengers-only notice).
    public var isVideoAllowed: Bool { state != .moving }

    @ObservationIgnored private var evaluator: DriveStateEvaluator
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let locationManager = CLLocationManager()

    public init(evaluator: DriveStateEvaluator = DriveStateEvaluator()) {
        self.evaluator = evaluator
    }

    public func start() {
        guard updatesTask == nil else { return }
        locationManager.requestWhenInUseAuthorization()
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let location = update.location else { continue }
                    self?.ingest(speed: location.speed, at: location.timestamp)
                }
            } catch {
                // Updates ended; keep the last known state.
            }
        }
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    private func ingest(speed: CLLocationSpeed, at time: Date) {
        let newState = evaluator.ingest(speed: speed, at: time)
        if newState != state { state = newState }
    }
}
