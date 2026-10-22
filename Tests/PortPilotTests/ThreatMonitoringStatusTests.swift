import XCTest
@testable import PortManagerLib

final class ThreatMonitoringStatusTests: XCTestCase {
    func testOnlyActiveSuccessfulAssessedStateIsCurrent() {
        for isMonitoring in [false, true] {
            for hasAssessment in [false, true] {
                for failures in [0, 1, 3] {
                    let status = ThreatMonitoringStatus(
                        isMonitoring: isMonitoring,
                        hasAssessment: hasAssessment,
                        consecutiveFailures: failures
                    )
                    XCTAssertEqual(
                        status == .current,
                        isMonitoring && hasAssessment && failures == 0,
                        "monitoring=\(isMonitoring), assessment=\(hasAssessment), failures=\(failures)"
                    )
                }
            }
        }
    }

    func testPausedOldAssessmentIsNotCurrent() {
        XCTAssertEqual(ThreatMonitoringStatus(
            isMonitoring: false, hasAssessment: true, consecutiveFailures: 0
        ), .paused)
    }

    func testFailedFirstSnapshotIsDegradedNotPendingOrClean() {
        XCTAssertEqual(ThreatMonitoringStatus(
            isMonitoring: true, hasAssessment: false, consecutiveFailures: 1
        ), .degraded)
    }

    func testRecoveryRequiresSuccessfulAssessment() {
        XCTAssertEqual(ThreatMonitoringStatus(
            isMonitoring: true, hasAssessment: false, consecutiveFailures: 0
        ), .pending)
        XCTAssertEqual(ThreatMonitoringStatus(
            isMonitoring: true, hasAssessment: true, consecutiveFailures: 2
        ), .degraded)
        XCTAssertEqual(ThreatMonitoringStatus(
            isMonitoring: true, hasAssessment: true, consecutiveFailures: 0
        ), .current)
    }
}
