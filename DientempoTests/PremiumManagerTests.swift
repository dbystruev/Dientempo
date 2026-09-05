import XCTest
@testable import Dientempo

@MainActor
final class PremiumManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PremiumManager.shared.resetForTesting()
    }

    override func tearDown() {
        PremiumManager.shared.resetForTesting()
        super.tearDown()
    }

    func testCanRunByDefault() {
        XCTAssertTrue(PremiumManager.shared.canRun)
        XCTAssertEqual(PremiumManager.shared.timeRemaining(), 0)
    }

    func testRecordRunLocksOutSameDay() {
        PremiumManager.shared.recordRun()
        XCTAssertFalse(PremiumManager.shared.canRun)

        let remaining = PremiumManager.shared.timeRemaining()
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertLessThanOrEqual(remaining, 86400)
    }

    func testResetForTestingRestoresCanRun() {
        PremiumManager.shared.recordRun()
        XCTAssertFalse(PremiumManager.shared.canRun)

        PremiumManager.shared.resetForTesting()
        XCTAssertTrue(PremiumManager.shared.canRun)
        XCTAssertEqual(PremiumManager.shared.timeRemaining(), 0)
    }

    func testUnlockPremiumOverridesDailyLimit() {
        PremiumManager.shared.recordRun()
        XCTAssertFalse(PremiumManager.shared.canRun)

        PremiumManager.shared.unlockPremium()
        XCTAssertTrue(PremiumManager.shared.canRun)
        XCTAssertEqual(PremiumManager.shared.timeRemaining(), 0)
    }

    func testCountdownStringFormat() {
        PremiumManager.shared.recordRun()
        let countdown = PremiumManager.shared.countdownString()
        XCTAssertEqual(countdown.count, 8, "Expected HH:MM:SS format, got \(countdown)")
        XCTAssertTrue(countdown.contains(":"))
    }
}
