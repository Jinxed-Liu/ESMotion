#if os(iOS)
  import CoreGraphics
  import UIKit

  @MainActor
  struct MotionCapturedPortal {
    let snapshot: MotionPortalSnapshot
    let frameInContainer: CGRect
    let cornerRadius: CGFloat
  }

  @MainActor
  enum MotionPortalSnapshotter {
    static func capture(
      entry: MotionElementRegistry.Entry,
      hostView: UIView,
      containerView: UIView,
      budget: MotionSnapshotBudget,
      scaleMultiplier: CGFloat,
      usedByteCount: Int
    ) -> MotionCapturedPortal? {
      guard let marker = entry.view,
        marker.window != nil,
        marker.bounds.width > 0,
        marker.bounds.height > 0
      else {
        return nil
      }

      let cropFrame = marker.convert(marker.bounds, to: hostView)
        .intersection(hostView.bounds)
      let containerFrame = marker.convert(marker.bounds, to: containerView)
      guard cropFrame.width > 0,
        cropFrame.height > 0,
        containerFrame.width > 0,
        containerFrame.height > 0
      else {
        return nil
      }

      let nativeScale = marker.window?.screen.scale ?? 2
      guard
        let preferredScale = budget.resolvedScale(
          pointSize: cropFrame.size,
          nativeScale: nativeScale,
          scaleMultiplier: scaleMultiplier,
          usedByteCount: usedByteCount
        )
      else {
        return nil
      }
      let remainingBytes = budget.maximumByteCount - usedByteCount

      let snapshot: MotionPortalSnapshot?
      if let provider = entry.snapshotProvider {
        snapshot = captureProvider(
          provider,
          pointSize: cropFrame.size,
          preferredScale: preferredScale,
          maximumByteCount: remainingBytes
        )
      } else {
        snapshot = captureView(
          hostView,
          cropFrame: cropFrame,
          scale: preferredScale,
          isOpaque: entry.isOpaque
        )
      }

      guard let snapshot, snapshot.byteCount <= remainingBytes else {
        return nil
      }
      return MotionCapturedPortal(
        snapshot: snapshot,
        frameInContainer: containerFrame,
        cornerRadius: entry.cornerRadius
      )
    }

    private static func captureProvider(
      _ provider: MotionPortalSnapshotProvider,
      pointSize: CGSize,
      preferredScale: CGFloat,
      maximumByteCount: Int
    ) -> MotionPortalSnapshot? {
      let request = MotionPortalSnapshotRequest(
        pointSize: pointSize,
        maximumByteCount: maximumByteCount,
        preferredScale: preferredScale
      )
      guard let image = provider.render(request) else { return nil }
      let sourceScale = min(
        CGFloat(image.width) / max(pointSize.width, 1),
        CGFloat(image.height) / max(pointSize.height, 1)
      )
      let direct = MotionPortalSnapshot(
        image: image,
        pointSize: pointSize,
        scale: max(sourceScale, 0.01),
        isOpaque: provider.isOpaque
      )
      guard direct.byteCount > maximumByteCount else { return direct }

      let fitRatio = sqrt(
        CGFloat(maximumByteCount) / CGFloat(max(direct.byteCount, 1))
      )
      let targetWidth = max(Int(CGFloat(image.width) * fitRatio), 1)
      let targetHeight = max(Int(CGFloat(image.height) * fitRatio), 1)
      guard
        let downsampled = resize(
          image,
          width: targetWidth,
          height: targetHeight,
          isOpaque: provider.isOpaque
        )
      else {
        return nil
      }
      let resolvedScale = min(
        CGFloat(targetWidth) / max(pointSize.width, 1),
        CGFloat(targetHeight) / max(pointSize.height, 1)
      )
      return MotionPortalSnapshot(
        image: downsampled,
        pointSize: pointSize,
        scale: resolvedScale,
        isOpaque: provider.isOpaque
      )
    }

    private static func captureView(
      _ hostView: UIView,
      cropFrame: CGRect,
      scale: CGFloat,
      isOpaque: Bool
    ) -> MotionPortalSnapshot? {
      let previousAlpha = hostView.alpha
      let previousTransform = hostView.transform
      let previousHidden = hostView.isHidden

      UIView.performWithoutAnimation {
        hostView.alpha = 1
        hostView.transform = .identity
        hostView.isHidden = false
        hostView.layoutIfNeeded()
      }
      defer {
        UIView.performWithoutAnimation {
          hostView.alpha = previousAlpha
          hostView.transform = previousTransform
          hostView.isHidden = previousHidden
        }
      }

      let format = UIGraphicsImageRendererFormat()
      format.scale = scale
      format.opaque = isOpaque
      format.preferredRange = .standard
      let image = UIGraphicsImageRenderer(
        size: cropFrame.size,
        format: format
      ).image { context in
        context.cgContext.translateBy(
          x: -cropFrame.minX,
          y: -cropFrame.minY
        )
        let rendered = hostView.drawHierarchy(
          in: hostView.bounds,
          afterScreenUpdates: true
        )
        if !rendered {
          hostView.layer.render(in: context.cgContext)
        }
      }
      guard let cgImage = image.cgImage else { return nil }
      return MotionPortalSnapshot(
        image: cgImage,
        pointSize: cropFrame.size,
        scale: image.scale,
        isOpaque: isOpaque
      )
    }

    private static func resize(
      _ image: CGImage,
      width: Int,
      height: Int,
      isOpaque: Bool
    ) -> CGImage? {
      let alpha: CGImageAlphaInfo =
        isOpaque ? .noneSkipLast : .premultipliedLast
      guard
        let context = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | alpha.rawValue
        )
      else {
        return nil
      }
      context.interpolationQuality = .high
      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: width, height: height)
      )
      return context.makeImage()
    }
  }
#endif
