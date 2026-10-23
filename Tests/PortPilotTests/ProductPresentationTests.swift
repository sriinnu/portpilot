import XCTest
@testable import PortManagerLib

final class ProductPresentationTests: XCTestCase {
    func testUnknownAndPausedChromeNeverDescribesAnEmptySuccessfulResult() {
        for status in [ThreatMonitoringStatus.pending, .paused, .degraded] {
            for severity in [ThreatSeverity?.none, .some(.critical)] {
                let presentation = MonitoringPresentation(status: status, highestSeverity: severity, pollInterval: 45)
                XCTAssertFalse(presentation.headline.contains("No findings"))
                XCTAssertFalse(presentation.compactLabel.contains("active"))
                XCTAssertFalse(presentation.cadenceLabel.contains("every"))
            }
        }
    }

    func testSuccessfulChromeUsesConfiguredCadenceAndLimitedClaim() {
        let presentation = MonitoringPresentation(status: .current, highestSeverity: nil, pollInterval: 45)
        XCTAssertEqual(presentation.headline, "No findings in latest check")
        XCTAssertEqual(presentation.cadenceLabel, "Threat checks every 45s")
        XCTAssertFalse(presentation.headline.contains("systems nominal"))
    }

    func testThreatAndLegacyConnectionBannersRouteReviewAndDefaultClicks() {
        for category in [NotificationReviewDestination.threatCategory, "CONNECTION_ALERT"] {
            for action in [NotificationReviewDestination.openSecurityAction, "VIEW_CONNECTIONS_ACTION"] {
                XCTAssertEqual(NotificationReviewDestination.resolve(
                    categoryIdentifier: category, actionIdentifier: action, isDefaultAction: false
                ), .security)
            }
            XCTAssertEqual(NotificationReviewDestination.resolve(
                categoryIdentifier: category, actionIdentifier: "default", isDefaultAction: true
            ), .security)
            XCTAssertNil(NotificationReviewDestination.resolve(
                categoryIdentifier: category, actionIdentifier: "DISMISS_ACTION", isDefaultAction: false
            ))
        }
        XCTAssertNil(NotificationReviewDestination.resolve(
            categoryIdentifier: "PORT_OCCUPIED", actionIdentifier: "KILL_ACTION", isDefaultAction: false
        ))
    }

    func testFailedLoginRegistrationReturnsActualDisabledState() {
        let service = FakeLoginItemService(status: .disabled)
        service.failure = FakeFailure()
        let result = LoginItemChangeResult.apply(enabled: true, service: service)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(result.status, .disabled)
        XCTAssertFalse(result.status.toggleValue)
        XCTAssertEqual(result.errorMessage, "Synthetic registration failure")
    }

    func testLoginRegistrationCanRequireApprovalWithoutClaimingEnabled() {
        let service = FakeLoginItemService(status: .disabled)
        service.statusAfterRegister = .requiresApproval
        let result = LoginItemChangeResult.apply(enabled: true, service: service)
        XCTAssertEqual(result.status, .requiresApproval)
        XCTAssertTrue(result.status.toggleValue)
        XCTAssertTrue(result.status.detail.contains("Waiting for approval"))
        XCTAssertNil(result.errorMessage)
    }

    func testPendingLoginApprovalDoesNotRepeatedlyRegister() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let result = LoginItemChangeResult.apply(enabled: true, service: service)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(result.status, .requiresApproval)
    }

    func testFailedLoginRemovalDoesNotClaimDisabled() {
        let service = FakeLoginItemService(status: .enabled)
        service.failure = FakeFailure()
        let result = LoginItemChangeResult.apply(enabled: false, service: service)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(result.status, .enabled)
        XCTAssertNotNil(result.errorMessage)
    }

    func testSuccessfulLoginChangeReadsServiceResult() {
        let service = FakeLoginItemService(status: .disabled)
        XCTAssertEqual(LoginItemChangeResult.apply(enabled: true, service: service).status, .enabled)
        XCTAssertEqual(LoginItemChangeResult.apply(enabled: false, service: service).status, .disabled)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 1)
    }
}

private final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus
    var statusAfterRegister: LoginItemStatus = .enabled
    var failure: Error?
    var registerCalls = 0
    var unregisterCalls = 0

    init(status: LoginItemStatus) { self.status = status }

    func register() throws {
        registerCalls += 1
        if let failure { throw failure }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if let failure { throw failure }
        status = .disabled
    }
}

private struct FakeFailure: LocalizedError {
    var errorDescription: String? { "Synthetic registration failure" }
}
