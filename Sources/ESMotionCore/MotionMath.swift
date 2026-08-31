import CoreGraphics

public enum MotionMath {
  @inlinable
  public static func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  @inlinable
  public static func lerp(
    from: Double,
    to: Double,
    progress: Double
  ) -> Double {
    from + (to - from) * progress
  }

  @inlinable
  public static func lerp(
    from: CGFloat,
    to: CGFloat,
    progress: Double
  ) -> CGFloat {
    from + (to - from) * CGFloat(progress)
  }

  public static func lerp(
    from: CGRect,
    to: CGRect,
    progress: Double
  ) -> CGRect {
    CGRect(
      x: lerp(from: from.minX, to: to.minX, progress: progress),
      y: lerp(from: from.minY, to: to.minY, progress: progress),
      width: lerp(from: from.width, to: to.width, progress: progress),
      height: lerp(from: from.height, to: to.height, progress: progress)
    )
  }

  @inlinable
  public static func smoothstep(
    edge0: Double,
    edge1: Double,
    value: Double
  ) -> Double {
    guard edge0 != edge1 else { return value < edge0 ? 0 : 1 }
    let normalized = clamp((value - edge0) / (edge1 - edge0))
    return normalized * normalized * (3 - 2 * normalized)
  }
}
