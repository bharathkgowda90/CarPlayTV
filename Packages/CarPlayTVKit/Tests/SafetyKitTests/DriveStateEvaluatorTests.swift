import XCTest
@testable import SafetyKit

final class DriveStateEvaluatorTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testStartsUnknownAndIgnoresInvalidSpeed() {
        var evaluator = DriveStateEvaluator()
        XCTAssertEqual(evaluator.state, .unknown)
        XCTAssertEqual(evaluator.ingest(speed: -1, at: start), .unknown)
    }

    func testMovingAboveThreshold() {
        var evaluator = DriveStateEvaluator()
        XCTAssertEqual(evaluator.ingest(speed: 10, at: start), .moving)
    }

    func testParkedOnlyAfterDwell() {
        var evaluator = DriveStateEvaluator(parkedDwell: 30)
        evaluator.ingest(speed: 15, at: start)
        XCTAssertEqual(evaluator.ingest(speed: 0, at: start.addingTimeInterval(1)), .moving)
        XCTAssertEqual(evaluator.ingest(speed: 0, at: start.addingTimeInterval(20)), .moving)
        XCTAssertEqual(evaluator.ingest(speed: 0, at: start.addingTimeInterval(31)), .parked)
    }

    func testCreepingSpeedKeepsStateAndResetsTimer() {
        var evaluator = DriveStateEvaluator(parkedDwell: 30)
        evaluator.ingest(speed: 15, at: start)
        evaluator.ingest(speed: 0, at: start.addingTimeInterval(1))
        // 1.5 m/s is between thresholds: still moving, and the parked timer restarts.
        XCTAssertEqual(evaluator.ingest(speed: 1.5, at: start.addingTimeInterval(25)), .moving)
        XCTAssertEqual(evaluator.ingest(speed: 0, at: start.addingTimeInterval(40)), .moving)
        XCTAssertEqual(evaluator.ingest(speed: 0, at: start.addingTimeInterval(71)), .parked)
    }

    func testParkedSwitchesBackToMoving() {
        var evaluator = DriveStateEvaluator(parkedDwell: 0)
        XCTAssertEqual(evaluator.ingest(speed: 0, at: start), .parked)
        XCTAssertEqual(evaluator.ingest(speed: 3, at: start.addingTimeInterval(1)), .moving)
    }
}
