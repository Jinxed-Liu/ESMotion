import ESMotionCore
import Foundation
import Observation

public struct MotionTransitionMetrics: Equatable, Sendable {
  public let transitionID: MotionTransitionID?
  public let direction: MotionTransitionDirection?
  public let duration: TimeInterval
  public let preparationDuration: TimeInterval
  public let firstFrameLatency: TimeInterval
  public let snapshotByteCount: Int
  public let frameStatistics: MotionFrameStatistics
  public let usedReducedMotion: Bool
  public let failure: MotionTransitionFailure?

  public init(
    transitionID: MotionTransitionID? = nil,
    direction: MotionTransitionDirection? = nil,
    duration: TimeInterval = 0,
    preparationDuration: TimeInterval = 0,
    firstFrameLatency: TimeInterval = 0,
    snapshotByteCount: Int = 0,
    frameStatistics: MotionFrameStatistics = .empty,
    usedReducedMotion: Bool = false,
    failure: MotionTransitionFailure? = nil
  ) {
    self.transitionID = transitionID
    self.direction = direction
    self.duration = max(duration, 0)
    self.preparationDuration = max(preparationDuration, 0)
    self.firstFrameLatency = max(firstFrameLatency, 0)
    self.snapshotByteCount = max(snapshotByteCount, 0)
    self.frameStatistics = frameStatistics
    self.usedReducedMotion = usedReducedMotion
    self.failure = failure
  }

  public static let empty = MotionTransitionMetrics()
}

public struct MotionEngineSnapshot: Equatable, Sendable {
  public let transitionID: MotionTransitionID?
  public let phase: MotionTransitionPhase
  public let progress: Double
  public let decision: MotionRuntimeDecision
  public let metrics: MotionTransitionMetrics
}

@MainActor
protocol MotionRuntimeControl: AnyObject {
  func motionRuntimeInvalidateSnapshots()
  func motionRuntimeReleaseResources()
  func motionRuntimeConditionsDidChange(_ decision: MotionRuntimeDecision)
}

@MainActor
@Observable
public final class MotionEngine {
  public private(set) var phase: MotionTransitionPhase
  public private(set) var activeTransitionID: MotionTransitionID?
  public private(set) var lastMetrics = MotionTransitionMetrics.empty
  public private(set) var conditions: MotionRuntimeConditions

  public let configuration: MotionTransitionConfiguration
  public let snapshotBudget: MotionSnapshotBudget

  @ObservationIgnored
  public private(set) var progress: Double

  @ObservationIgnored
  private var machine: MotionTransitionMachine

  @ObservationIgnored
  private weak var runtime: (any MotionRuntimeControl)?

  @ObservationIgnored
  private var metricDirection: MotionTransitionDirection?

  @ObservationIgnored
  private var metricStartedAt: TimeInterval = 0

  @ObservationIgnored
  private var preparationStartedAt: TimeInterval = 0

  @ObservationIgnored
  private var preparationDuration: TimeInterval = 0

  @ObservationIgnored
  private var firstFrameLatency: TimeInterval = 0

  @ObservationIgnored
  private var snapshotByteCount = 0

  @ObservationIgnored
  private var previousFrameTimestamp: TimeInterval?

  @ObservationIgnored
  private var frames = MotionFrameAccumulator()

  public init(
    configuration: MotionTransitionConfiguration = .portal,
    snapshotBudget: MotionSnapshotBudget = .portal,
    conditions: MotionRuntimeConditions = MotionRuntimeConditions()
  ) {
    self.configuration = configuration
    self.snapshotBudget = snapshotBudget
    self.conditions = conditions
    machine = MotionTransitionMachine(configuration: configuration)
    phase = machine.phase
    progress = machine.progress
  }

  public var decision: MotionRuntimeDecision {
    MotionRuntimePolicy.resolve(conditions)
  }

  public var isTransitioning: Bool {
    phase.isActive
  }

  public func updateConditions(_ conditions: MotionRuntimeConditions) {
    guard self.conditions != conditions else { return }
    self.conditions = conditions
    runtime?.motionRuntimeConditionsDidChange(decision)
  }

  public func invalidatePortalSnapshots() {
    runtime?.motionRuntimeInvalidateSnapshots()
  }

  public func releaseResources() {
    runtime?.motionRuntimeReleaseResources()
  }

  public func snapshot() -> MotionEngineSnapshot {
    MotionEngineSnapshot(
      transitionID: activeTransitionID,
      phase: phase,
      progress: progress,
      decision: decision,
      metrics: lastMetrics
    )
  }

  func attach(runtime: any MotionRuntimeControl) {
    self.runtime = runtime
    runtime.motionRuntimeConditionsDidChange(decision)
  }

  func detach(runtime: any MotionRuntimeControl) {
    if self.runtime === runtime {
      self.runtime = nil
    }
  }

  func setInitialBoundary(_ boundary: MotionTransitionBoundary) {
    machine.reset(to: boundary)
    activeTransitionID = nil
    syncMachine()
  }

  @discardableResult
  func preparePresentation(id: MotionTransitionID) -> Bool {
    guard machine.preparePresentation() else { return false }
    beginMetrics(id: id, direction: .presenting)
    syncMachine()
    return true
  }

  @discardableResult
  func prepareDismissal(id: MotionTransitionID) -> Bool {
    guard machine.prepareDismissal() else { return false }
    beginMetrics(id: id, direction: .dismissing)
    syncMachine()
    return true
  }

  func startPreparedTransition(snapshotByteCount: Int) {
    self.snapshotByteCount = max(snapshotByteCount, 0)
    preparationDuration =
      ProcessInfo.processInfo.systemUptime - preparationStartedAt

    switch machine.phase {
    case .preparing(.presenting):
      machine.startPreparedPresentation(
        reducedMotion: decision.usesReducedMotion
      )
    case .preparing(.dismissing):
      machine.startPreparedDismissal(
        reducedMotion: decision.usesReducedMotion
      )
    default:
      return
    }
    syncMachine()
  }

  @discardableResult
  func beginInteractiveDismissal(
    id: MotionTransitionID,
    snapshotByteCount: Int
  ) -> Bool {
    guard machine.beginInteractiveDismissal() else { return false }
    beginMetrics(id: id, direction: .dismissing)
    self.snapshotByteCount = max(snapshotByteCount, 0)
    preparationDuration = 0
    syncMachine()
    return true
  }

  func updateInteractiveDismissal(
    progress: Double,
    velocity: Double,
    extent: Double
  ) {
    machine.updateInteractiveDismissal(
      progress: progress,
      velocity: velocity,
      extent: extent
    )
    recordFrame(at: ProcessInfo.processInfo.systemUptime)
    syncMachine()
  }

  @discardableResult
  func finishInteractiveDismissal(
    projectedProgress: Double,
    velocity: Double,
    extent: Double
  ) -> Bool {
    let completes = machine.finishInteractiveDismissal(
      projectedProgress: projectedProgress,
      velocity: velocity,
      extent: extent,
      reducedMotion: decision.usesReducedMotion
    )
    syncMachine()
    return completes
  }

  func retarget(to boundary: MotionTransitionBoundary) {
    machine.retarget(
      to: boundary,
      reducedMotion: decision.usesReducedMotion
    )
    metricDirection =
      boundary == .destination ? .presenting : .dismissing
    syncMachine()
  }

  func advance(
    by deltaTime: TimeInterval,
    timestamp: TimeInterval
  ) -> MotionTransitionBoundary? {
    recordFrame(at: timestamp, suppliedInterval: deltaTime)
    let boundary = machine.advance(by: deltaTime)
    syncMachine()
    return boundary
  }

  func finishHandoff(at boundary: MotionTransitionBoundary) {
    machine.reset(to: boundary)
    publishMetrics(failure: nil)
    activeTransitionID = nil
    syncMachine()
  }

  func abort(
    _ failure: MotionTransitionFailure,
    restingAt boundary: MotionTransitionBoundary
  ) {
    machine.fail(failure)
    syncMachine()
    publishMetrics(failure: failure)
    machine.reset(to: boundary)
    activeTransitionID = nil
    syncMachine()
  }

  private func beginMetrics(
    id: MotionTransitionID,
    direction: MotionTransitionDirection
  ) {
    activeTransitionID = id
    metricDirection = direction
    metricStartedAt = ProcessInfo.processInfo.systemUptime
    preparationStartedAt = metricStartedAt
    preparationDuration = 0
    firstFrameLatency = 0
    snapshotByteCount = 0
    previousFrameTimestamp = nil
    frames.reset()
  }

  private func recordFrame(
    at timestamp: TimeInterval,
    suppliedInterval: TimeInterval? = nil
  ) {
    if firstFrameLatency == 0, metricStartedAt > 0 {
      firstFrameLatency = timestamp - metricStartedAt
    }
    let interval =
      suppliedInterval
      ?? previousFrameTimestamp.map { timestamp - $0 }
    if let interval {
      frames.record(interval)
    }
    previousFrameTimestamp = timestamp
  }

  private func publishMetrics(failure: MotionTransitionFailure?) {
    let now = ProcessInfo.processInfo.systemUptime
    lastMetrics = MotionTransitionMetrics(
      transitionID: activeTransitionID,
      direction: metricDirection,
      duration: metricStartedAt > 0 ? now - metricStartedAt : 0,
      preparationDuration: preparationDuration,
      firstFrameLatency: firstFrameLatency,
      snapshotByteCount: snapshotByteCount,
      frameStatistics: frames.snapshot(),
      usedReducedMotion: decision.usesReducedMotion,
      failure: failure
    )
    metricStartedAt = 0
    preparationStartedAt = 0
    previousFrameTimestamp = nil
  }

  private func syncMachine() {
    progress = machine.progress
    if phase != machine.phase {
      phase = machine.phase
    }
  }
}
