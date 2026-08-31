#if os(iOS)
  import QuartzCore

  @MainActor
  final class MotionDisplayDriver {
    private final class Target: NSObject {
      var callback: ((CADisplayLink) -> Void)?

      @objc
      func tick(_ displayLink: CADisplayLink) {
        callback?(displayLink)
      }
    }

    private let target = Target()
    private var displayLink: CADisplayLink?
    private var previousTimestamp: TimeInterval?

    var isRunning: Bool {
      displayLink != nil
    }

    func start(
      preferredFramesPerSecond: Int,
      onFrame:
        @escaping (
          _ timestamp: TimeInterval,
          _ deltaTime: TimeInterval
        ) -> Void
    ) {
      stop()
      let link = CADisplayLink(
        target: target,
        selector: #selector(Target.tick(_:))
      )
      let preferred = max(preferredFramesPerSecond, 1)
      if #available(iOS 15.0, *) {
        link.preferredFrameRateRange = CAFrameRateRange(
          minimum: Float(min(preferred, 60)),
          maximum: Float(preferred),
          preferred: Float(preferred)
        )
      } else {
        link.preferredFramesPerSecond = preferred
      }
      target.callback = { [weak self] link in
        guard let self else { return }
        let frameTimestamp = link.targetTimestamp
        let fallbackDelta = max(
          frameTimestamp - link.timestamp,
          1 / 120
        )
        let delta =
          previousTimestamp.map {
            max(frameTimestamp - $0, 0.000_001)
          } ?? fallbackDelta
        previousTimestamp = frameTimestamp
        onFrame(frameTimestamp, min(delta, 0.25))
      }
      displayLink = link
      link.add(to: .main, forMode: .common)
    }

    func stop() {
      displayLink?.invalidate()
      displayLink = nil
      previousTimestamp = nil
      target.callback = nil
    }

  }
#endif
