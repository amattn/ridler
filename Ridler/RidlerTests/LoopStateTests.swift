import XCTest
@testable import Ridler

final class LoopStateTests: XCTestCase {

    // MARK: - Color Property Tests

    func testStateColors() {
        XCTAssertEqual(LoopState.ready.color, .gray)
        XCTAssertEqual(LoopState.running.color, .cyan)
        XCTAssertEqual(LoopState.paused.color, .yellow)
        XCTAssertEqual(LoopState.stopped.color, .gray)
        XCTAssertEqual(LoopState.complete.color, .green)
        XCTAssertEqual(LoopState.error.color, .red)
    }

    // MARK: - Label Property Tests

    func testStateLabels() {
        XCTAssertEqual(LoopState.ready.label, "Ready")
        XCTAssertEqual(LoopState.running.label, "Running")
        XCTAssertEqual(LoopState.paused.label, "Paused")
        XCTAssertEqual(LoopState.stopped.label, "Stopped")
        XCTAssertEqual(LoopState.complete.label, "Complete")
        XCTAssertEqual(LoopState.error.label, "Error")
    }

    // MARK: - Valid Transition Tests

    func testReadyToRunning() {
        let sm = LoopStateMachine()
        XCTAssertEqual(sm.state, .ready)
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertEqual(sm.state, .running)
    }

    func testRunningToPaused() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        XCTAssertTrue(sm.transition(to: .paused))
        XCTAssertEqual(sm.state, .paused)
    }

    func testRunningToStopped() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        XCTAssertTrue(sm.transition(to: .stopped))
        XCTAssertEqual(sm.state, .stopped)
    }

    func testRunningToComplete() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        XCTAssertTrue(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .complete)
    }

    func testRunningToError() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        XCTAssertTrue(sm.transition(to: .error))
        XCTAssertEqual(sm.state, .error)
    }

    func testPausedToRunning() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .paused)
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertEqual(sm.state, .running)
    }

    func testStoppedToRunning() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .stopped)
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertEqual(sm.state, .running)
    }

    func testErrorToRunning() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .error)
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertEqual(sm.state, .running)
    }

    // MARK: - Invalid Transition Tests

    func testReadyToReadyInvalid() {
        let sm = LoopStateMachine()
        XCTAssertFalse(sm.transition(to: .ready))
        XCTAssertEqual(sm.state, .ready)
    }

    func testReadyToPausedInvalid() {
        let sm = LoopStateMachine()
        XCTAssertFalse(sm.transition(to: .paused))
        XCTAssertEqual(sm.state, .ready)
    }

    func testReadyToStoppedInvalid() {
        let sm = LoopStateMachine()
        XCTAssertFalse(sm.transition(to: .stopped))
        XCTAssertEqual(sm.state, .ready)
    }

    func testReadyToCompleteInvalid() {
        let sm = LoopStateMachine()
        XCTAssertFalse(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .ready)
    }

    func testReadyToErrorInvalid() {
        let sm = LoopStateMachine()
        XCTAssertFalse(sm.transition(to: .error))
        XCTAssertEqual(sm.state, .ready)
    }

    func testRunningToReadyInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        XCTAssertFalse(sm.transition(to: .ready))
        XCTAssertEqual(sm.state, .running)
    }

    func testRunningToRunningInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        XCTAssertFalse(sm.transition(to: .running))
        XCTAssertEqual(sm.state, .running)
    }

    func testPausedToPausedInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .paused)
        XCTAssertFalse(sm.transition(to: .paused))
        XCTAssertEqual(sm.state, .paused)
    }

    func testPausedToStoppedInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .paused)
        XCTAssertFalse(sm.transition(to: .stopped))
        XCTAssertEqual(sm.state, .paused)
    }

    func testPausedToCompleteInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .paused)
        XCTAssertFalse(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .paused)
    }

    func testPausedToErrorInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .paused)
        XCTAssertFalse(sm.transition(to: .error))
        XCTAssertEqual(sm.state, .paused)
    }

    func testStoppedToStoppedInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .stopped)
        XCTAssertFalse(sm.transition(to: .stopped))
        XCTAssertEqual(sm.state, .stopped)
    }

    func testCompleteToAnyInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .complete)

        for target in LoopState.allCases {
            XCTAssertFalse(sm.transition(to: target), "Complete should not transition to \(target)")
        }
        XCTAssertEqual(sm.state, .complete)
    }

    func testErrorToErrorInvalid() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .error)
        XCTAssertFalse(sm.transition(to: .error))
        XCTAssertEqual(sm.state, .error)
    }

    // MARK: - Reset Test

    func testResetReturnsToReady() {
        let sm = LoopStateMachine()
        sm.transition(to: .running)
        sm.transition(to: .complete)
        sm.reset()
        XCTAssertEqual(sm.state, .ready)
    }

    // MARK: - Initial State Test

    func testInitialStateIsReady() {
        let sm = LoopStateMachine()
        XCTAssertEqual(sm.state, .ready)
    }

    // MARK: - Multi-Step Transition Tests

    func testFullLifecycleReadyToComplete() {
        let sm = LoopStateMachine()
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .complete)
    }

    func testPauseResumeComplete() {
        let sm = LoopStateMachine()
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .paused))
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .complete)
    }

    func testErrorRecovery() {
        let sm = LoopStateMachine()
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .error))
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .complete)
    }

    func testStopAndRestart() {
        let sm = LoopStateMachine()
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .stopped))
        XCTAssertTrue(sm.transition(to: .running))
        XCTAssertTrue(sm.transition(to: .complete))
        XCTAssertEqual(sm.state, .complete)
    }
}
