import CoreGraphics
import Foundation

public enum MotionThermalPressure: String, Codable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical

  public init(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal:
      self = .nominal
    case .fair:
      self = .fair
    case .serious:
      self = .serious
    case .critical:
      self = .critical
    @unknown default:
      self = .serious
    }
  }
}

public struct MotionRuntimeConditions: Equatable, Sendable {
  public var isSceneActive: Bool
  public var prefersReducedMotion: Bool
  public var prefersPowerSaving: Bool
  public var thermalPressure: MotionThermalPressure

  public init(
    isSceneActive: Bool = true,
    prefersReducedMotion: Bool = false,
    prefersPowerSaving: Bool = false,
    thermalPressure: MotionThermalPressure = .nominal
  ) {
    self.isSceneActive = isSceneActive
    self.prefersReducedMotion = prefersReducedMotion
    self.prefersPowerSaving = prefersPowerSaving
    self.thermalPressure = thermalPressure
  }
}

public struct MotionRuntimeDecision: Equatable, Sendable {
  public let preferredFramesPerSecond: Int
  public let snapshotScaleMultiplier: CGFloat
  public let usesReducedMotion: Bool
  public let suspendsContinuousMotion: Bool

  public init(
    preferredFramesPerSecond: Int,
    snapshotScaleMultiplier: CGFloat,
    usesReducedMotion: Bool,
    suspendsContinuousMotion: Bool
  ) {
    self.preferredFramesPerSecond = max(preferredFramesPerSecond, 1)
    self.snapshotScaleMultiplier = min(
      max(snapshotScaleMultiplier, 0.5),
      1
    )
    self.usesReducedMotion = usesReducedMotion
    self.suspendsContinuousMotion = suspendsContinuousMotion
  }
}

public enum MotionRuntimePolicy {
  public static func resolve(
    _ conditions: MotionRuntimeConditions
  ) -> MotionRuntimeDecision {
    var framesPerSecond = 120
    var snapshotScale: CGFloat = 1

    if conditions.prefersPowerSaving {
      framesPerSecond = 60
      snapshotScale *= 0.8
    }

    switch conditions.thermalPressure {
    case .nominal:
      break
    case .fair:
      framesPerSecond = min(framesPerSecond, 90)
      snapshotScale *= 0.9
    case .serious:
      framesPerSecond = min(framesPerSecond, 60)
      snapshotScale *= 0.72
    case .critical:
      framesPerSecond = min(framesPerSecond, 30)
      snapshotScale *= 0.55
    }

    if conditions.prefersReducedMotion {
      framesPerSecond = min(framesPerSecond, 60)
      snapshotScale *= 0.8
    }

    return MotionRuntimeDecision(
      preferredFramesPerSecond: framesPerSecond,
      snapshotScaleMultiplier: snapshotScale,
      usesReducedMotion: conditions.prefersReducedMotion,
      suspendsContinuousMotion:
        !conditions.isSceneActive
        || conditions.thermalPressure == .critical
    )
  }
}
