import CoreGraphics
import Foundation

public struct MotionPortalSnapshotRequest: Equatable, Sendable {
  public let pointSize: CGSize
  public let maximumByteCount: Int
  public let preferredScale: CGFloat

  public init(
    pointSize: CGSize,
    maximumByteCount: Int,
    preferredScale: CGFloat
  ) {
    self.pointSize = pointSize
    self.maximumByteCount = max(maximumByteCount, 0)
    self.preferredScale = max(preferredScale, 0)
  }
}

/// Supplies a prepared static image for video, Metal, camera, or other surfaces
/// that cannot be captured reliably from a view hierarchy.
public struct MotionPortalSnapshotProvider: @unchecked Sendable {
  public let isOpaque: Bool
  let render: @MainActor (MotionPortalSnapshotRequest) -> CGImage?

  public init(
    isOpaque: Bool = true,
    render:
      @escaping @MainActor (
        MotionPortalSnapshotRequest
      ) -> CGImage?
  ) {
    self.isOpaque = isOpaque
    self.render = render
  }
}

public struct MotionSnapshotBudget: Equatable, Sendable {
  public let maximumByteCount: Int
  public let minimumScale: CGFloat
  public let maximumScale: CGFloat

  public init(
    maximumByteCount: Int = 24 * 1_024 * 1_024,
    minimumScale: CGFloat = 0.75,
    maximumScale: CGFloat = 2
  ) {
    self.maximumByteCount = max(maximumByteCount, 1)
    self.minimumScale = max(minimumScale, 0.25)
    self.maximumScale = max(maximumScale, self.minimumScale)
  }

  public static let portal = MotionSnapshotBudget()

  public func resolvedScale(
    pointSize: CGSize,
    nativeScale: CGFloat,
    scaleMultiplier: CGFloat = 1,
    usedByteCount: Int = 0
  ) -> CGFloat? {
    guard pointSize.width > 0, pointSize.height > 0 else { return nil }
    let remainingBytes = maximumByteCount - max(usedByteCount, 0)
    guard remainingBytes > 0 else { return nil }

    let pointArea = pointSize.width * pointSize.height
    let maximumPixels = CGFloat(remainingBytes) / 4
    let budgetScale = sqrt(maximumPixels / pointArea)
    let preferred = min(
      max(nativeScale, 1) * max(scaleMultiplier, 0.5),
      maximumScale
    )
    let resolved = min(preferred, budgetScale)
    guard resolved >= minimumScale else { return nil }
    return resolved
  }

  public func estimatedByteCount(
    pointSize: CGSize,
    scale: CGFloat
  ) -> Int {
    let width = max(Int(ceil(pointSize.width * scale)), 1)
    let height = max(Int(ceil(pointSize.height * scale)), 1)
    return width * height * 4
  }
}

struct MotionPortalSnapshot: @unchecked Sendable {
  let image: CGImage
  let pointSize: CGSize
  let scale: CGFloat
  let isOpaque: Bool

  var byteCount: Int {
    image.bytesPerRow * image.height
  }
}
