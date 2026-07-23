import XCTest
@testable import ESMotionCore

final class ESMotionCoreTests: XCTestCase {
    func testInteractiveProgressThresholds() {
        var progress = MotionInteractiveProgress(progress: 0.2)
        XCTAssertFalse(
            progress.finish(
                projectedProgress: 0.34,
                velocity: 899
            )
        )
        XCTAssertEqual(progress.target, 0)

        progress.update(progress: 0.2, velocity: 0)
        XCTAssertTrue(
            progress.finish(
                projectedProgress: 0.35,
                velocity: 0
            )
        )
        XCTAssertEqual(progress.target, 1)
    }

    func testVelocityCanCompleteInteractiveTransition() {
        var progress = MotionInteractiveProgress(progress: 0.1)
        XCTAssertTrue(
            progress.finish(
                projectedProgress: 0.1,
                velocity: 900
            )
        )
    }

    func testSpringRetargetsWithoutResettingValue() {
        var state = MotionSpringState(value: 0.62, velocity: 0.4, target: 1)
        state.retarget(to: 0)
        XCTAssertEqual(state.value, 0.62)
        XCTAssertEqual(state.velocity, 0.4)

        for _ in 0 ..< 360 {
            state.step(deltaTime: 1 / 120, spring: .transition)
        }
        XCTAssertEqual(state.value, 0, accuracy: 0.001)
    }

    func testRuntimePolicyStopsForReduceMotion() {
        let decision = MotionRuntimePolicy.resolve(
            budget: .interaction,
            inputs: MotionRuntimeInputs(prefersReducedMotion: true)
        )
        XCTAssertTrue(decision.isPaused)
    }

    func testThermalPressureDegradesBudget() {
        let decision = MotionRuntimePolicy.resolve(
            budget: .interaction,
            inputs: MotionRuntimeInputs(thermalPressure: .serious)
        )
        XCTAssertEqual(decision.frameRateRange.maximum, 24)
        XCTAssertEqual(decision.quality, .efficient)
    }

    func testSequenceInterpolation() {
        let track = MotionTrack(
            keyPath: "opacity",
            keyframes: [
                MotionKeyframe(time: 0, value: 0),
                MotionKeyframe(time: 1, value: 1),
            ]
        )
        let value = MotionSequenceSampler.value(in: track, at: 0.5)
        XCTAssertNotNil(value)
        XCTAssertEqual(value ?? .nan, 0.5, accuracy: 0.0001)
    }
}
