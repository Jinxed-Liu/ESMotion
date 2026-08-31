import Foundation

public struct MotionTransitionID:
  Hashable,
  Codable,
  Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    rawValue = value
  }
}

public enum MotionTransitionDirection: String, Codable, Equatable, Sendable {
  case presenting
  case dismissing
}

public enum MotionTransitionFailure:
  String,
  Codable,
  Equatable,
  Error,
  Sendable
{
  case missingSource
  case missingDestination
  case invalidGeometry
  case snapshotUnavailable
  case snapshotBudgetExceeded
  case interrupted
  case sceneInactive
}

public enum MotionTransitionPhase: Equatable, Sendable {
  case idle
  case preparing(MotionTransitionDirection)
  case animating(MotionTransitionDirection)
  case interactive(MotionTransitionDirection)
  case settling(direction: MotionTransitionDirection, target: Double)
  case presented
  case failed(MotionTransitionFailure)

  public var isActive: Bool {
    switch self {
    case .preparing, .animating, .interactive, .settling:
      true
    case .idle, .presented, .failed:
      false
    }
  }
}

public struct MotionTransitionConfiguration: Codable, Equatable, Sendable {
  public let spring: MotionSpring
  public let reducedMotionSpring: MotionSpring
  public let completionProgress: Double
  public let completionVelocity: Double

  public init(
    spring: MotionSpring = .portal,
    reducedMotionSpring: MotionSpring = .reducedMotion,
    completionProgress: Double = 0.35,
    completionVelocity: Double = 900
  ) {
    self.spring = spring
    self.reducedMotionSpring = reducedMotionSpring
    self.completionProgress = MotionMath.clamp(completionProgress)
    self.completionVelocity = max(completionVelocity, 0)
  }

  public static let portal = MotionTransitionConfiguration()
}

public enum MotionTransitionBoundary: Equatable, Sendable {
  case source
  case destination
}

public struct MotionTransitionMachine: Equatable, Sendable {
  public private(set) var phase: MotionTransitionPhase
  public private(set) var position: Double
  public private(set) var velocity: Double
  public let configuration: MotionTransitionConfiguration

  private var springState: MotionSpringState
  private var activeSpring: MotionSpring

  public init(
    configuration: MotionTransitionConfiguration = .portal,
    initiallyPresented: Bool = false
  ) {
    self.configuration = configuration
    phase = initiallyPresented ? .presented : .idle
    position = initiallyPresented ? 1 : 0
    velocity = 0
    springState = MotionSpringState(
      value: position,
      target: position
    )
    activeSpring = configuration.spring
  }

  public var progress: Double {
    MotionMath.clamp(position)
  }

  @discardableResult
  public mutating func preparePresentation() -> Bool {
    switch phase {
    case .idle, .failed:
      break
    case .preparing, .animating, .interactive, .settling, .presented:
      return false
    }
    phase = .preparing(.presenting)
    position = 0
    velocity = 0
    springState = MotionSpringState(value: 0, target: 1)
    return true
  }

  public mutating func startPreparedPresentation(
    reducedMotion: Bool
  ) {
    guard phase == .preparing(.presenting) else { return }
    activeSpring =
      reducedMotion
      ? configuration.reducedMotionSpring
      : configuration.spring
    springState = MotionSpringState(
      value: position,
      velocity: velocity,
      target: 1
    )
    phase = .animating(.presenting)
  }

  @discardableResult
  public mutating func prepareDismissal() -> Bool {
    guard phase == .presented else { return false }
    phase = .preparing(.dismissing)
    position = 1
    velocity = 0
    springState = MotionSpringState(value: 1, target: 0)
    return true
  }

  public mutating func startPreparedDismissal(
    reducedMotion: Bool
  ) {
    guard phase == .preparing(.dismissing) else { return }
    activeSpring =
      reducedMotion
      ? configuration.reducedMotionSpring
      : configuration.spring
    springState = MotionSpringState(
      value: position,
      velocity: velocity,
      target: 0
    )
    phase = .animating(.dismissing)
  }

  @discardableResult
  public mutating func beginDismissal(reducedMotion: Bool) -> Bool {
    guard
      phase == .presented
        || phase == .animating(.presenting)
        || phase == .settling(direction: .presenting, target: 1)
    else {
      return false
    }
    activeSpring =
      reducedMotion
      ? configuration.reducedMotionSpring
      : configuration.spring
    springState = MotionSpringState(
      value: position,
      velocity: velocity,
      target: 0
    )
    phase = .animating(.dismissing)
    return true
  }

  @discardableResult
  public mutating func beginInteractiveDismissal() -> Bool {
    guard phase == .presented else { return false }
    position = 1
    velocity = 0
    springState = MotionSpringState(value: 1, target: 0)
    phase = .interactive(.dismissing)
    return true
  }

  public mutating func updateInteractiveDismissal(
    progress dismissalProgress: Double,
    velocity pointsPerSecond: Double,
    extent: Double
  ) {
    guard phase == .interactive(.dismissing) else { return }
    position = 1 - MotionMath.clamp(dismissalProgress)
    velocity = -pointsPerSecond / max(extent, 1)
    springState = MotionSpringState(
      value: position,
      velocity: velocity,
      target: 0
    )
  }

  @discardableResult
  public mutating func finishInteractiveDismissal(
    projectedProgress: Double,
    velocity pointsPerSecond: Double,
    extent: Double,
    reducedMotion: Bool
  ) -> Bool {
    guard phase == .interactive(.dismissing) else { return false }
    let completes =
      projectedProgress >= configuration.completionProgress
      || pointsPerSecond >= configuration.completionVelocity
    let target = completes ? 0.0 : 1.0
    activeSpring =
      reducedMotion
      ? configuration.reducedMotionSpring
      : configuration.spring
    springState = MotionSpringState(
      value: position,
      velocity: -pointsPerSecond / max(extent, 1),
      target: target
    )
    phase = .settling(direction: .dismissing, target: target)
    return completes
  }

  public mutating func retarget(
    to boundary: MotionTransitionBoundary,
    reducedMotion: Bool
  ) {
    let target = boundary == .destination ? 1.0 : 0.0
    let direction: MotionTransitionDirection =
      boundary == .destination ? .presenting : .dismissing
    activeSpring =
      reducedMotion
      ? configuration.reducedMotionSpring
      : configuration.spring
    springState = MotionSpringState(
      value: position,
      velocity: velocity,
      target: target
    )
    phase = .settling(direction: direction, target: target)
  }

  @discardableResult
  public mutating func advance(
    by deltaTime: TimeInterval
  ) -> MotionTransitionBoundary? {
    switch phase {
    case .animating, .settling:
      break
    case .idle, .preparing, .interactive, .presented, .failed:
      return nil
    }

    springState.advance(by: deltaTime, spring: activeSpring)
    position = springState.value
    velocity = springState.velocity

    guard springState.isSettled() else { return nil }
    if springState.target >= 0.5 {
      position = 1
      velocity = 0
      phase = .presented
      return .destination
    } else {
      position = 0
      velocity = 0
      phase = .idle
      return .source
    }
  }

  public mutating func fail(_ failure: MotionTransitionFailure) {
    velocity = 0
    springState = MotionSpringState(
      value: position,
      target: position
    )
    phase = .failed(failure)
  }

  public mutating func reset(to boundary: MotionTransitionBoundary) {
    let target = boundary == .destination ? 1.0 : 0.0
    position = target
    velocity = 0
    springState = MotionSpringState(value: target, target: target)
    phase = boundary == .destination ? .presented : .idle
  }
}
