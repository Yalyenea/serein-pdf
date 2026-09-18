import XCTest
@testable import Serein

@MainActor
final class AppUpdateCoordinatorTests: XCTestCase {
    func testPendingInstallStartsOnlyWhenTerminationIsAcceptedAndRunsOnce() throws {
        let coordinator = AppUpdateCoordinator(tokenProvider: { nil }, autoCheckEnabledProvider: { false })
        var launchCount = 0
        coordinator.testingSetPendingInstall { launchCount += 1 }
        XCTAssertEqual(launchCount, 0)

        try coordinator.installPendingUpdate()
        XCTAssertEqual(launchCount, 1)
        try coordinator.installPendingUpdate()
        XCTAssertEqual(launchCount, 1)
    }

    func testPendingInstallFailurePropagatesToTerminationDecision() {
        let coordinator = AppUpdateCoordinator(tokenProvider: { nil }, autoCheckEnabledProvider: { false })
        coordinator.testingSetPendingInstall { throw AppUpdateService.ServiceError.invalidResponse }
        XCTAssertThrowsError(try coordinator.installPendingUpdate()) {
            XCTAssertEqual($0 as? AppUpdateService.ServiceError, .invalidResponse)
        }
    }
}
