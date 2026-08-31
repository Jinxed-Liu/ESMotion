import CoreGraphics
import ESMotionCore
import XCTest

@testable import ESMotionRuntime

@MainActor
final class ESMotionRuntimeTests: XCTestCase {
  func testSnapshotBudgetAccountsForAlreadyUsedBytes() {
    let budget = MotionSnapshotBudget(
      maximumByteCount: 8 * 1_024 * 1_024,
      minimumScale: 0.5,
      maximumScale: 3
    )
    let size = CGSize(width: 400, height: 800)

    let fullScale = budget.resolvedScale(
      pointSize: size,
      nativeScale: 3
    )
    let reducedScale = budget.resolvedScale(
      pointSize: size,
      nativeScale: 3,
      usedByteCount: 6 * 1_024 * 1_024
    )

    XCTAssertNotNil(fullScale)
    XCTAssertNotNil(reducedScale)
    XCTAssertLessThan(reducedScale ?? .infinity, fullScale ?? 0)
  }

  func testSnapshotBudgetRejectsResolutionBelowMinimumScale() {
    let budget = MotionSnapshotBudget(
      maximumByteCount: 256,
      minimumScale: 1,
      maximumScale: 2
    )
    XCTAssertNil(
      budget.resolvedScale(
        pointSize: CGSize(width: 400, height: 800),
        nativeScale: 2
      )
    )
  }

  func testEngineCompletesPresentationAndPublishesMetrics() {
    let engine = MotionEngine()
    let id = MotionTransitionID("card")
    XCTAssertTrue(engine.preparePresentation(id: id))
    engine.startPreparedTransition(snapshotByteCount: 2_000_000)

    let start = ProcessInfo.processInfo.systemUptime
    var boundary: MotionTransitionBoundary?
    for frame in 1...240 {
      boundary = engine.advance(
        by: 1 / 120,
        timestamp: start + Double(frame) / 120
      )
      if boundary != nil { break }
    }

    XCTAssertEqual(boundary, .destination)
    engine.finishHandoff(at: .destination)
    XCTAssertEqual(engine.phase, .presented)
    XCTAssertEqual(engine.lastMetrics.transitionID, id)
    XCTAssertEqual(engine.lastMetrics.direction, .presenting)
    XCTAssertEqual(engine.lastMetrics.snapshotByteCount, 2_000_000)
    XCTAssertGreaterThan(engine.lastMetrics.frameStatistics.frameCount, 0)
    XCTAssertNil(engine.lastMetrics.failure)
  }

  func testEngineRetargetsWithoutResettingProgress() {
    let engine = MotionEngine()
    XCTAssertTrue(engine.preparePresentation(id: "card"))
    engine.startPreparedTransition(snapshotByteCount: 100)
    _ = engine.advance(
      by: 1 / 60,
      timestamp: ProcessInfo.processInfo.systemUptime
    )
    let progress = engine.progress

    engine.retarget(to: .source)

    XCTAssertEqual(engine.progress, progress)
    XCTAssertEqual(
      engine.phase,
      .settling(direction: .dismissing, target: 0)
    )
  }

  func testAbortRecordsFailureAndRestsAtRequestedBoundary() {
    let engine = MotionEngine()
    XCTAssertTrue(engine.preparePresentation(id: "missing"))
    engine.abort(.missingDestination, restingAt: .destination)

    XCTAssertEqual(engine.phase, .presented)
    XCTAssertEqual(engine.progress, 1)
    XCTAssertEqual(engine.lastMetrics.failure, .missingDestination)
  }

  func testConditionsReachAttachedRuntime() {
    let engine = MotionEngine()
    let runtime = TestRuntime()
    engine.attach(runtime: runtime)

    engine.updateConditions(
      MotionRuntimeConditions(
        prefersPowerSaving: true,
        thermalPressure: .serious
      )
    )

    XCTAssertEqual(runtime.lastDecision?.preferredFramesPerSecond, 60)
    XCTAssertLessThan(
      runtime.lastDecision?.snapshotScaleMultiplier ?? 1,
      1
    )
  }

  func testExplicitResourceCommandsReachRuntime() {
    let engine = MotionEngine()
    let runtime = TestRuntime()
    engine.attach(runtime: runtime)

    engine.invalidatePortalSnapshots()
    engine.releaseResources()

    XCTAssertEqual(runtime.invalidateCount, 1)
    XCTAssertEqual(runtime.releaseCount, 1)
  }

  private final class TestRuntime: MotionRuntimeControl {
    var invalidateCount = 0
    var releaseCount = 0
    var lastDecision: MotionRuntimeDecision?

    func motionRuntimeInvalidateSnapshots() {
      invalidateCount += 1
    }

    func motionRuntimeReleaseResources() {
      releaseCount += 1
    }

    func motionRuntimeConditionsDidChange(
      _ decision: MotionRuntimeDecision
    ) {
      lastDecision = decision
    }
  }
}
