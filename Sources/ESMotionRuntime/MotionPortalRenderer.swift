#if os(iOS)
  import ESMotionCore
  import QuartzCore
  import UIKit

  struct MotionPortalSession {
    let id: MotionTransitionID
    let source: MotionCapturedPortal
    let destination: MotionCapturedPortal

    var snapshotByteCount: Int {
      source.snapshot.byteCount + destination.snapshot.byteCount
    }
  }

  @MainActor
  final class MotionPortalOverlayView: UIView {
    private let shadowLayer = CALayer()
    private let clipLayer = CALayer()
    private let sourceLayer = CALayer()
    private let destinationLayer = CALayer()

    private var session: MotionPortalSession?
    private var reducedMotion = false

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = .clear
      isUserInteractionEnabled = false
      isAccessibilityElement = false

      layer.addSublayer(shadowLayer)
      shadowLayer.addSublayer(clipLayer)
      clipLayer.addSublayer(sourceLayer)
      clipLayer.addSublayer(destinationLayer)

      shadowLayer.shadowColor = UIColor.black.cgColor
      shadowLayer.shadowRadius = 28
      shadowLayer.shadowOffset = CGSize(width: 0, height: 16)
      clipLayer.masksToBounds = true
      sourceLayer.contentsGravity = .resizeAspectFill
      destinationLayer.contentsGravity = .resizeAspectFill
      isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func prepare(
      session: MotionPortalSession,
      reducedMotion: Bool,
      initialProgress: Double
    ) {
      self.session = session
      self.reducedMotion = reducedMotion
      sourceLayer.contents = session.source.snapshot.image
      sourceLayer.contentsScale = session.source.snapshot.scale
      destinationLayer.contents = session.destination.snapshot.image
      destinationLayer.contentsScale = session.destination.snapshot.scale
      clipLayer.backgroundColor =
        reducedMotion
        ? UIColor.clear.cgColor
        : UIColor.black.cgColor
      isHidden = false
      _ = render(progress: initialProgress)
    }

    @discardableResult
    func render(progress: Double) -> MotionPortalGeometry? {
      guard let session else { return nil }
      let geometry = MotionPortalGeometry.resolve(
        sourceFrame: session.source.frameInContainer,
        destinationFrame: session.destination.frameInContainer,
        sourceCornerRadius: session.source.cornerRadius,
        destinationCornerRadius: session.destination.cornerRadius,
        progress: progress,
        reducedMotion: reducedMotion
      )

      CATransaction.begin()
      CATransaction.setDisableActions(true)
      shadowLayer.frame = geometry.frame
      shadowLayer.cornerRadius = geometry.cornerRadius
      shadowLayer.shadowOpacity = geometry.shadowOpacity
      shadowLayer.shadowPath =
        UIBezierPath(
          roundedRect: shadowLayer.bounds,
          cornerRadius: geometry.cornerRadius
        ).cgPath

      clipLayer.frame = shadowLayer.bounds
      clipLayer.cornerRadius = geometry.cornerRadius
      sourceLayer.frame = clipLayer.bounds
      destinationLayer.frame = clipLayer.bounds
      sourceLayer.opacity = Float(geometry.sourceOpacity)
      destinationLayer.opacity = Float(geometry.destinationOpacity)
      CATransaction.commit()
      return geometry
    }

    func clear() {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      sourceLayer.contents = nil
      destinationLayer.contents = nil
      sourceLayer.opacity = 0
      destinationLayer.opacity = 0
      shadowLayer.shadowOpacity = 0
      CATransaction.commit()
      session = nil
      isHidden = true
    }
  }
#endif
