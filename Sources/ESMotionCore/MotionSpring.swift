import Foundation

/// A physical spring expressed in perceptual response and damping terms.
public struct MotionSpring: Codable, Equatable, Sendable {
  public let response: TimeInterval
  public let dampingRatio: Double

  public init(response: TimeInterval, dampingRatio: Double) {
    self.response = max(response, 0.05)
    self.dampingRatio = max(dampingRatio, 0.01)
  }

  public static let portal = MotionSpring(
    response: 0.44,
    dampingRatio: 0.88
  )

  public static let reducedMotion = MotionSpring(
    response: 0.18,
    dampingRatio: 1
  )
}

/// Frame-rate-independent spring state.
///
/// `advance` solves the damped oscillator analytically, so 60 Hz and 120 Hz
/// converge to the same trajectory instead of accumulating Euler error.
public struct MotionSpringState: Equatable, Sendable {
  public var value: Double
  public var velocity: Double
  public var target: Double

  public init(value: Double, velocity: Double = 0, target: Double) {
    self.value = value
    self.velocity = velocity
    self.target = target
  }

  public func isSettled(
    displacementEpsilon: Double = 0.0005,
    velocityEpsilon: Double = 0.001
  ) -> Bool {
    abs(target - value) <= displacementEpsilon
      && abs(velocity) <= velocityEpsilon
  }

  public mutating func retarget(to newTarget: Double) {
    target = newTarget
  }

  public mutating func advance(
    by deltaTime: TimeInterval,
    spring: MotionSpring
  ) {
    guard deltaTime > 0 else { return }

    let duration = min(deltaTime, 0.25)
    let omega = (2 * Double.pi) / spring.response
    let damping = spring.dampingRatio
    let displacement = value - target

    let solved: (displacement: Double, velocity: Double)
    if damping < 1 - 0.0001 {
      solved = solveUnderdamped(
        displacement: displacement,
        velocity: velocity,
        time: duration,
        omega: omega,
        damping: damping
      )
    } else if damping > 1 + 0.0001 {
      solved = solveOverdamped(
        displacement: displacement,
        velocity: velocity,
        time: duration,
        omega: omega,
        damping: damping
      )
    } else {
      solved = solveCriticallyDamped(
        displacement: displacement,
        velocity: velocity,
        time: duration,
        omega: omega
      )
    }

    value = target + solved.displacement
    velocity = solved.velocity

    if isSettled() {
      value = target
      velocity = 0
    }
  }

  private func solveUnderdamped(
    displacement: Double,
    velocity: Double,
    time: TimeInterval,
    omega: Double,
    damping: Double
  ) -> (Double, Double) {
    let dampedOmega = omega * sqrt(max(1 - damping * damping, 0.000_001))
    let envelope = exp(-damping * omega * time)
    let cosine = cos(dampedOmega * time)
    let sine = sin(dampedOmega * time)
    let sineCoefficient =
      (velocity + damping * omega * displacement) / dampedOmega
    let nextDisplacement =
      envelope
      * (displacement * cosine + sineCoefficient * sine)
    let nextVelocity =
      envelope
      * (velocity * cosine
        - (damping * omega * sineCoefficient
          + displacement * dampedOmega) * sine)
    return (nextDisplacement, nextVelocity)
  }

  private func solveCriticallyDamped(
    displacement: Double,
    velocity: Double,
    time: TimeInterval,
    omega: Double
  ) -> (Double, Double) {
    let coefficient = velocity + omega * displacement
    let envelope = exp(-omega * time)
    let nextDisplacement = (displacement + coefficient * time) * envelope
    let nextVelocity =
      (coefficient - omega * (displacement + coefficient * time))
      * envelope
    return (nextDisplacement, nextVelocity)
  }

  private func solveOverdamped(
    displacement: Double,
    velocity: Double,
    time: TimeInterval,
    omega: Double,
    damping: Double
  ) -> (Double, Double) {
    let root = sqrt(damping * damping - 1)
    let firstRate = -omega * (damping - root)
    let secondRate = -omega * (damping + root)
    let denominator = firstRate - secondRate
    let firstCoefficient =
      (velocity - secondRate * displacement) / denominator
    let secondCoefficient = displacement - firstCoefficient
    let firstEnvelope = exp(firstRate * time)
    let secondEnvelope = exp(secondRate * time)
    let nextDisplacement =
      firstCoefficient * firstEnvelope
      + secondCoefficient * secondEnvelope
    let nextVelocity =
      firstRate * firstCoefficient * firstEnvelope
      + secondRate * secondCoefficient * secondEnvelope
    return (nextDisplacement, nextVelocity)
  }
}
