import XCTest
@testable import argus

@MainActor
final class AutoPilotStoreSmokeTests: XCTestCase {

    let store = AutoPilotStore.shared

    override func setUp() async throws {
        try await super.setUp()
        store.stopAutoPilotLoop()
        store.isAutoPilotEnabled = false
        store.scoutingCandidates = []
        store.scoutLogs = []
    }

    // MARK: - Default State

    func testDefaultState_AutoPilotDisabled() {
        XCTAssertFalse(store.isAutoPilotEnabled)
    }

    func testDefaultState_ScoutingCandidatesEmpty() {
        XCTAssertTrue(store.scoutingCandidates.isEmpty)
    }

    func testScanSummaryEmpty_HasRunFalse() {
        let empty = AutoPilotStore.ScanSummary.empty
        XCTAssertFalse(empty.hasRun)
        XCTAssertEqual(empty.scannedCount, 0)
        XCTAssertEqual(empty.signalCount, 0)
    }

    // MARK: - Timer Lifecycle

    func testStartLoop_CreatesTimer() {
        store.isAutoPilotEnabled = true
        store.startAutoPilotLoop()
        XCTAssertNotNil(store.autoPilotTimer)
    }

    func testStopLoop_NullsTimer() {
        store.isAutoPilotEnabled = true
        store.startAutoPilotLoop()
        store.stopAutoPilotLoop()
        XCTAssertNil(store.autoPilotTimer)
    }

    func testRestartTimer_ReplacesExistingTimer() {
        store.isAutoPilotEnabled = true
        store.startAutoPilotLoop()
        let firstTimer = store.autoPilotTimer
        store.restartTimer(interval: 120)
        let secondTimer = store.autoPilotTimer
        XCTAssertNotNil(secondTimer)
        XCTAssertFalse(firstTimer === secondTimer)
    }

    // MARK: - Balance Tracking

    func testHandleBalanceChange_UpdatesTrackedBalances() {
        store.handleBalanceChange(usd: 5000.0, tl: 25000.0)
        XCTAssertEqual(store.lastKnownGlobalBalance, 5000.0, accuracy: 0.01)
        XCTAssertEqual(store.lastKnownBistBalance, 25000.0, accuracy: 0.01)
    }

    // MARK: - Context Multiplier

    func testContextMultiplier_DefaultIsPositive() {
        let mult = store.currentContextMultiplier()
        XCTAssertGreaterThan(mult, 0.0)
        XCTAssertLessThanOrEqual(mult, 3.0)
    }
}
