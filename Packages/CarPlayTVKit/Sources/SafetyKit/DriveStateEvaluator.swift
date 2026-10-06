import Foundation

public enum DriveState: String, Sendable {
    case unknown
    case parked
    case moving
}

/// Turns a stream of speed readings into a parked / moving state, with hysteresis so
/// GPS noise doesn't flicker the video on and off.
///
/// Limitation: a phone can't tell "parked" from "stopped at a long red light". The dwell
/// time keeps that window short; iOS 27's CarPlay video API reports parked state from the car.
public struct DriveStateEvaluator: Sendable {
    /// At or above this speed (m/s, ≈ 9 km/h) the car counts as moving.
    public var movingSpeed: Double
    /// At or below this speed (m/s) the car counts as stopped.
    public var stoppedSpeed: Double
    /// How long the car must stay stopped before video is allowed again.
    public var parkedDwell: TimeInterval

    public private(set) var state: DriveState = .unknown
    private var stoppedSince: Date?

    public init(movingSpeed: Double = 2.5, stoppedSpeed: Double = 0.8, parkedDwell: TimeInterval = 30) {
        self.movingSpeed = movingSpeed
        self.stoppedSpeed = stoppedSpeed
        self.parkedDwell = parkedDwell
    }

    /// - Parameter speed: metres per second; negative means invalid (CoreLocation reports -1).
    @discardableResult
    public mutating func ingest(speed: Double, at time: Date) -> DriveState {
        guard speed >= 0 else { return state }

        if speed >= movingSpeed {
            state = .moving
            stoppedSince = nil
        } else if speed <= stoppedSpeed {
            let since = stoppedSince ?? time
            stoppedSince = since
            if time.timeIntervalSince(since) >= parkedDwell {
                state = .parked
            }
        } else {
            // Between thresholds: keep the current state, but restart the parked timer.
            stoppedSince = nil
        }
        return state
    }
}
