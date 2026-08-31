import CoreGraphics
import Foundation

public struct MotionPortalGeometry: Equatable, Sendable {
  public let frame: CGRect
  public let cornerRadius: CGFloat
  public let sourceOpacity: Double
  public let destinationOpacity: Double
  public let backdropScale: CGFloat
  public let shadowOpacity: Float

  public init(
    frame: CGRect,
    cornerRadius: CGFloat,
    sourceOpacity: Double,
    destinationOpacity: Double,
    backdropScale: CGFloat,
    shadowOpacity: Float
  ) {
    self.frame = frame
    self.cornerRadius = max(cornerRadius, 0)
    self.sourceOpacity = MotionMath.clamp(sourceOpacity)
    self.destinationOpacity = MotionMath.clamp(destinationOpacity)
    self.backdropScale = min(max(backdropScale, 0.9), 1)
    self.shadowOpacity = min(max(shadowOpacity, 0), 1)
  }

  public static func resolve(
    sourceFrame: CGRect,
    destinationFrame: CGRect,
    sourceCornerRadius: CGFloat,
    destinationCornerRadius: CGFloat,
    progress: Double,
    reducedMotion: Bool
  ) -> MotionPortalGeometry {
    let clamped = MotionMath.clamp(progress)
    let geometryProgress = reducedMotion ? 1 : clamped
    let destinationOpacity = MotionMath.smoothstep(
      edge0: reducedMotion ? 0 : 0.12,
      edge1: reducedMotion ? 0.72 : 0.82,
      value: clamped
    )
    let shadowBell = sin(Double.pi * clamped)

    return MotionPortalGeometry(
      frame: MotionMath.lerp(
        from: sourceFrame,
        to: destinationFrame,
        progress: geometryProgress
      ),
      cornerRadius: MotionMath.lerp(
        from: sourceCornerRadius,
        to: destinationCornerRadius,
        progress: geometryProgress
      ),
      sourceOpacity: reducedMotion ? 0 : 1,
      destinationOpacity: destinationOpacity,
      backdropScale: CGFloat(1 - 0.025 * clamped),
      shadowOpacity: Float(max(shadowBell, 0) * 0.22)
    )
  }
}
