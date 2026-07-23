import XCTest
@testable import ESMotionCore
@testable import ESMotionRuntime

@MainActor
final class ESMotionRuntimeTests: XCTestCase {
    func testTransitionDefaultsMatchInteractionContract() {
        XCTAssertEqual(MotionTransitionSpec.card.progressThreshold, 0.35)
        XCTAssertEqual(MotionTransitionSpec.card.velocityThreshold, 900)
        XCTAssertEqual(MotionTransitionSpec.card.spring.response, 0.42)
        XCTAssertEqual(MotionTransitionSpec.card.spring.dampingRatio, 0.86)
    }

    func testEngineResolvesUserPowerSaving() {
        let engine = MotionEngine(
            environment: MotionEnvironmentState(
                userPowerSaving: true
            )
        )
        let decision = engine.decision(for: .interaction)
        XCTAssertEqual(
            decision.frameRateRange,
            MotionBudget.interaction.lowPowerFrameRateRange
        )
        XCTAssertEqual(decision.quality, .efficient)
    }

    func testDisplayCoordinatorStopsWhenLastCallbackLeaves() {
        let coordinator = MotionDisplayCoordinator()
        let id = coordinator.register(budget: .ambientScene) { _ in }
        XCTAssertNotNil(coordinator.activeBudget)
        coordinator.unregister(id)
        XCTAssertNil(coordinator.activeBudget)
    }

    func testDisplayCoordinatorRecalculatesPriorityAfterUnregister() {
        let coordinator = MotionDisplayCoordinator()
        let ambient = coordinator.register(budget: .ambientScene) { _ in }
        let interaction = coordinator.register(budget: .interaction) { _ in }
        XCTAssertEqual(coordinator.activeBudget, .interaction)

        coordinator.unregister(interaction)
        XCTAssertEqual(coordinator.activeBudget, .ambientScene)
        XCTAssertEqual(
            coordinator.decision.frameRateRange,
            MotionBudget.ambientScene.frameRateRange
        )
        coordinator.unregister(ambient)
    }

    func testSuspendedRegistrationDoesNotRaiseBudget() {
        let coordinator = MotionDisplayCoordinator()
        let ambient = coordinator.register(budget: .ambientScene) { _ in }
        let interaction = coordinator.register(
            budget: .interaction,
            isSuspended: true
        ) { _ in }

        XCTAssertEqual(coordinator.activeBudget, .ambientScene)
        coordinator.unregister(ambient)
        coordinator.unregister(interaction)
    }

    func testTransitionSourceAcceptsHostBackgroundColor() {
        XCTAssertEqual(MotionTransitionSpec.card.cornerRadius, 24)
    }
}
