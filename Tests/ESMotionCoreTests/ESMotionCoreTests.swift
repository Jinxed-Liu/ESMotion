import CoreGraphics
import XCTest

@testable import ESMotionCore

final class ESMotionCoreTests: XCTestCase {
  func testAnalyticSpringConvergesAcrossRefreshRates() {
    var finalValues: [Double] = []

    for refreshRate in [60.0, 90.0, 120.0] {
      var state = MotionSpringState(value: 0, target: 1)
      for _ in 0..<Int(refreshRate) {
        state.advance(
          by: 1 / refreshRate,
          spring: .portal
        )
      }
      finalValues.append(state.value)
      XCTAssertEqual(state.value, 1, accuracy: 0.001)
    }

    XCTAssertEqual(finalValues[0], finalValues[1], accuracy: 0.000_01)
    XCTAssertEqual(finalValues[1], finalValues[2], accuracy: 0.000_01)
  }

  func testSpringRetargetPreservesValueAndVelocity() {
    var state = MotionSpringState(value: 0.42, velocity: 1.2, target: 1)
    state.retarget(to: 0)
    XCTAssertEqual(state.value, 0.42)
    XCTAssertEqual(state.velocity, 1.2)
    XCTAssertEqual(state.target, 0)
  }

  func testPresentationAndDismissalUseOneStateMachine() {
    var machine = MotionTransitionMachine()
    XCTAssertTrue(machine.preparePresentation())
    machine.startPreparedPresentation(reducedMotion: false)
    advanceToBoundary(&machine)
    XCTAssertEqual(machine.phase, .presented)

    XCTAssertTrue(machine.beginDismissal(reducedMotion: false))
    advanceToBoundary(&machine)
    XCTAssertEqual(machine.phase, .idle)
  }

  func testInteractiveDismissalCompletesByVelocity() {
    var machine = MotionTransitionMachine(initiallyPresented: true)
    XCTAssertTrue(machine.beginInteractiveDismissal())
    machine.updateInteractiveDismissal(
      progress: 0.1,
      velocity: 950,
      extent: 400
    )
    XCTAssertTrue(
      machine.finishInteractiveDismissal(
        projectedProgress: 0.12,
        velocity: 950,
        extent: 400,
        reducedMotion: false
      )
    )
    XCTAssertEqual(
      machine.phase,
      .settling(direction: .dismissing, target: 0)
    )
  }

  func testInteractiveDismissalCancelsBelowThreshold() {
    var machine = MotionTransitionMachine(initiallyPresented: true)
    XCTAssertTrue(machine.beginInteractiveDismissal())
    machine.updateInteractiveDismissal(
      progress: 0.15,
      velocity: 120,
      extent: 400
    )
    XCTAssertFalse(
      machine.finishInteractiveDismissal(
        projectedProgress: 0.2,
        velocity: 120,
        extent: 400,
        reducedMotion: false
      )
    )
    advanceToBoundary(&machine)
    XCTAssertEqual(machine.phase, .presented)
  }

  func testRetargetKeepsCurrentProgress() {
    var machine = MotionTransitionMachine()
    _ = machine.preparePresentation()
    machine.startPreparedPresentation(reducedMotion: false)
    _ = machine.advance(by: 1 / 60)
    let progress = machine.position
    machine.retarget(to: .source, reducedMotion: false)
    XCTAssertEqual(machine.position, progress)
    XCTAssertEqual(
      machine.phase,
      .settling(direction: .dismissing, target: 0)
    )
  }

  func testPortalGeometryGoldenFrames() {
    let source = CGRect(x: 20, y: 100, width: 160, height: 120)
    let destination = CGRect(x: 0, y: 0, width: 400, height: 900)

    let frames = [0.0, 0.25, 0.5, 0.75, 1.0].map {
      MotionPortalGeometry.resolve(
        sourceFrame: source,
        destinationFrame: destination,
        sourceCornerRadius: 28,
        destinationCornerRadius: 0,
        progress: $0,
        reducedMotion: false
      ).frame
    }

    XCTAssertEqual(
      frames,
      [
        CGRect(x: 20, y: 100, width: 160, height: 120),
        CGRect(x: 15, y: 75, width: 220, height: 315),
        CGRect(x: 10, y: 50, width: 280, height: 510),
        CGRect(x: 5, y: 25, width: 340, height: 705),
        CGRect(x: 0, y: 0, width: 400, height: 900),
      ]
    )
  }

  func testReducedMotionKeepsDestinationGeometry() {
    let destination = CGRect(x: 0, y: 0, width: 400, height: 900)
    let geometry = MotionPortalGeometry.resolve(
      sourceFrame: CGRect(x: 20, y: 100, width: 160, height: 120),
      destinationFrame: destination,
      sourceCornerRadius: 28,
      destinationCornerRadius: 0,
      progress: 0,
      reducedMotion: true
    )
    XCTAssertEqual(geometry.frame, destination)
    XCTAssertEqual(geometry.cornerRadius, 0)
  }

  func testRuntimePolicySeparatesReducedMotionFromSuspension() {
    let reduced = MotionRuntimePolicy.resolve(
      MotionRuntimeConditions(prefersReducedMotion: true)
    )
    XCTAssertTrue(reduced.usesReducedMotion)
    XCTAssertFalse(reduced.suspendsContinuousMotion)
    XCTAssertEqual(reduced.preferredFramesPerSecond, 60)

    let inactive = MotionRuntimePolicy.resolve(
      MotionRuntimeConditions(isSceneActive: false)
    )
    XCTAssertTrue(inactive.suspendsContinuousMotion)
  }

  func testFrameStatisticsAreDeterministic() {
    var accumulator = MotionFrameAccumulator()
    for interval in [0.008, 0.009, 0.010, 0.020, 0.040] {
      accumulator.record(interval)
    }
    let snapshot = accumulator.snapshot()
    XCTAssertEqual(snapshot.frameCount, 5)
    XCTAssertEqual(snapshot.p50, 0.010)
    XCTAssertEqual(snapshot.p95, 0.040)
    XCTAssertEqual(snapshot.hitchCount, 1)
  }

  private func advanceToBoundary(
    _ machine: inout MotionTransitionMachine
  ) {
    for _ in 0..<240 {
      if machine.advance(by: 1 / 120) != nil {
        return
      }
    }
    XCTFail("state machine did not settle")
  }
}
