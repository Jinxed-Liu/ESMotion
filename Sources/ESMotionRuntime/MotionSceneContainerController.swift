#if os(iOS)
  import ESMotionCore
  import SwiftUI
  import UIKit

  @MainActor
  final class MotionSceneContainerController:
    UIViewController,
    MotionRuntimeControl,
    UIGestureRecognizerDelegate
  {
    let registry = MotionElementRegistry()
    let visibility = MotionElementVisibility()

    var clearSelection: (() -> Void)?

    private let engine: MotionEngine
    private let rootHost = UIHostingController(rootView: AnyView(EmptyView()))
    private var destinationHost: UIHostingController<AnyView>?
    private let overlay = MotionPortalOverlayView()
    private let driver = MotionDisplayDriver()

    private var transitionTask: Task<Void, Never>?
    private var generation = 0
    private var currentSelectionID: AnyHashable?
    private var currentTransitionID: MotionTransitionID?
    private var cachedSession: MotionPortalSession?
    private var desiredDestination = false
    private var clearsSelectionAtSource = false
    private var cachedContainerSize: CGSize = .zero

    private lazy var edgePan: UIScreenEdgePanGestureRecognizer = {
      let gesture = UIScreenEdgePanGestureRecognizer(
        target: self,
        action: #selector(handleEdgePan(_:))
      )
      gesture.delegate = self
      return gesture
    }()

    init(engine: MotionEngine) {
      self.engine = engine
      super.init(nibName: nil, bundle: nil)
      engine.attach(runtime: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .black
      install(rootHost)
      overlay.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(overlay)
      NSLayoutConstraint.activate([
        overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        overlay.topAnchor.constraint(equalTo: view.topAnchor),
        overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      view.addGestureRecognizer(edgePan)
      updateGestureEdge()
    }

    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      updateGestureEdge()
      if cachedContainerSize != .zero,
        cachedContainerSize != view.bounds.size
      {
        invalidateCachedSession(warmIfPresented: true)
      }
    }

    override func didReceiveMemoryWarning() {
      super.didReceiveMemoryWarning()
      invalidateCachedSession(warmIfPresented: false)
    }

    func updateRoot(_ content: AnyView) {
      rootHost.rootView = content
    }

    func showInitialDestination(
      selectionID: AnyHashable,
      transitionID: MotionTransitionID,
      content: AnyView
    ) {
      currentSelectionID = selectionID
      currentTransitionID = transitionID
      desiredDestination = true
      mountDestination(content)
      rootHost.view.alpha = 0
      destinationHost?.view.alpha = 1
      engine.setInitialBoundary(.destination)
      scheduleWarmCache()
    }

    func updateDestinationContent(_ content: AnyView) {
      destinationHost?.rootView = content
    }

    func presentDestination(
      selectionID: AnyHashable,
      transitionID: MotionTransitionID,
      content: AnyView
    ) {
      desiredDestination = true
      clearsSelectionAtSource = false

      if currentSelectionID == selectionID, destinationHost != nil {
        updateDestinationContent(content)
        switch engine.phase {
        case .animating(.dismissing),
          .settling(direction: .dismissing, target: 0):
          engine.retarget(to: .destination)
          startDriver()
        default:
          break
        }
        return
      }

      if destinationHost != nil {
        replaceDestinationWithoutAnimation(
          selectionID: selectionID,
          transitionID: transitionID,
          content: content
        )
        return
      }

      currentSelectionID = selectionID
      currentTransitionID = transitionID
      mountDestination(content)
      destinationHost?.view.alpha = 1
      rootHost.view.alpha = 1
      cachedSession = nil
      cachedContainerSize = .zero

      guard engine.preparePresentation(id: transitionID) else {
        fallback(.interrupted, restingAt: .destination)
        return
      }
      schedulePreparation(direction: .presenting)
    }

    func dismissDestination() {
      desiredDestination = false
      guard destinationHost != nil else {
        completeAtSourceWithoutAnimation()
        return
      }

      switch engine.phase {
      case .preparing(.presenting):
        cancelPreparation()
        fallback(.interrupted, restingAt: .source)
      case .animating(.presenting),
        .settling(direction: .presenting, target: 1):
        engine.retarget(to: .source)
        startDriver()
      case .presented:
        beginPreparedDismissal()
      case .preparing(.dismissing),
        .animating(.dismissing),
        .settling(direction: .dismissing, target: 0),
        .interactive(.dismissing):
        break
      case .settling(direction: .dismissing, target: 1):
        engine.retarget(to: .source)
        startDriver()
      case .interactive(.presenting), .settling:
        fallback(.interrupted, restingAt: .source)
      case .idle, .failed:
        completeAtSourceWithoutAnimation()
      }
    }

    func tearDown() {
      cancelPreparation()
      driver.stop()
      overlay.clear()
      visibility.showAll()
      cachedSession = nil
      engine.detach(runtime: self)
    }

    func motionRuntimeInvalidateSnapshots() {
      invalidateCachedSession(warmIfPresented: true)
    }

    func motionRuntimeReleaseResources() {
      invalidateCachedSession(warmIfPresented: false)
      if engine.phase.isActive {
        fallback(
          .interrupted,
          restingAt: desiredDestination ? .destination : .source
        )
      }
    }

    func motionRuntimeConditionsDidChange(_ decision: MotionRuntimeDecision) {
      if decision.suspendsContinuousMotion, engine.phase.isActive {
        fallback(
          .sceneInactive,
          restingAt: desiredDestination ? .destination : .source
        )
      } else if driver.isRunning {
        startDriver()
      }
    }

    func gestureRecognizerShouldBegin(
      _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      gestureRecognizer === edgePan
        && desiredDestination
        && cachedSession != nil
        && engine.phase == .presented
    }

    private func mountDestination(_ content: AnyView) {
      let host = UIHostingController(rootView: content)
      destinationHost = host
      install(host, below: rootHost.view)
      view.bringSubviewToFront(overlay)
    }

    private func install(
      _ controller: UIViewController,
      above sibling: UIView? = nil,
      below lowerSibling: UIView? = nil
    ) {
      addChild(controller)
      controller.view.translatesAutoresizingMaskIntoConstraints = false
      if let sibling {
        view.insertSubview(controller.view, aboveSubview: sibling)
      } else if let lowerSibling {
        view.insertSubview(controller.view, belowSubview: lowerSibling)
      } else {
        view.addSubview(controller.view)
      }
      NSLayoutConstraint.activate([
        controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        controller.view.topAnchor.constraint(equalTo: view.topAnchor),
        controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
      controller.didMove(toParent: self)
    }

    private func unmountDestination() {
      guard let destinationHost else { return }
      destinationHost.willMove(toParent: nil)
      destinationHost.view.removeFromSuperview()
      destinationHost.removeFromParent()
      self.destinationHost = nil
    }

    private func replaceDestinationWithoutAnimation(
      selectionID: AnyHashable,
      transitionID: MotionTransitionID,
      content: AnyView
    ) {
      cancelPreparation()
      driver.stop()
      overlay.clear()
      visibility.showAll()
      unmountDestination()
      currentSelectionID = selectionID
      currentTransitionID = transitionID
      mountDestination(content)
      rootHost.view.alpha = 0
      rootHost.view.transform = .identity
      destinationHost?.view.alpha = 1
      cachedSession = nil
      engine.abort(.interrupted, restingAt: .destination)
      scheduleWarmCache()
    }

    private func beginPreparedDismissal() {
      guard let id = currentTransitionID else {
        fallback(.missingDestination, restingAt: .source)
        return
      }
      guard engine.prepareDismissal(id: id) else {
        fallback(.interrupted, restingAt: .source)
        return
      }
      if let cachedSession {
        beginRendering(
          cachedSession,
          direction: .dismissing
        )
      } else {
        schedulePreparation(direction: .dismissing)
      }
    }

    private func schedulePreparation(
      direction: MotionTransitionDirection
    ) {
      cancelPreparation(incrementGeneration: false)
      generation += 1
      let token = generation
      transitionTask = Task { @MainActor [weak self] in
        guard let self else { return }
        let result = await waitForPortalSession(token: token)
        guard !Task.isCancelled, generation == token else { return }
        transitionTask = nil
        switch result {
        case .success(let session):
          cachedSession = session
          cachedContainerSize = view.bounds.size
          beginRendering(session, direction: direction)
        case .failure(let failure):
          fallback(
            failure,
            restingAt:
              direction == .presenting && desiredDestination
              ? .destination
              : .source
          )
        }
      }
    }

    private func waitForPortalSession(
      token: Int
    ) async -> Result<MotionPortalSession, MotionTransitionFailure> {
      guard let id = currentTransitionID else {
        return .failure(.missingSource)
      }
      let sourceKey = MotionPortalKey(id: id, role: .source)
      let destinationKey = MotionPortalKey(id: id, role: .destination)

      for _ in 0..<32 {
        guard !Task.isCancelled, generation == token else {
          return .failure(.interrupted)
        }
        view.layoutIfNeeded()
        if let source = registry.entry(for: sourceKey),
          let destination = registry.entry(for: destinationKey)
        {
          return captureSession(
            id: id,
            source: source,
            destination: destination
          )
        }
        try? await Task.sleep(for: .milliseconds(8))
      }

      if registry.entry(for: sourceKey) == nil {
        return .failure(.missingSource)
      }
      return .failure(.missingDestination)
    }

    private func captureSession(
      id: MotionTransitionID,
      source: MotionElementRegistry.Entry,
      destination: MotionElementRegistry.Entry
    ) -> Result<MotionPortalSession, MotionTransitionFailure> {
      guard let destinationHost else {
        return .failure(.missingDestination)
      }
      let decision = engine.decision
      guard
        let sourceCapture = MotionPortalSnapshotter.capture(
          entry: source,
          hostView: rootHost.view,
          containerView: view,
          budget: engine.snapshotBudget,
          scaleMultiplier: decision.snapshotScaleMultiplier,
          usedByteCount: 0
        )
      else {
        return .failure(.snapshotUnavailable)
      }
      guard
        let destinationCapture = MotionPortalSnapshotter.capture(
          entry: destination,
          hostView: destinationHost.view,
          containerView: view,
          budget: engine.snapshotBudget,
          scaleMultiplier: decision.snapshotScaleMultiplier,
          usedByteCount: sourceCapture.snapshot.byteCount
        )
      else {
        return .failure(.snapshotBudgetExceeded)
      }
      guard valid(sourceCapture.frameInContainer),
        valid(destinationCapture.frameInContainer)
      else {
        return .failure(.invalidGeometry)
      }
      return .success(
        MotionPortalSession(
          id: id,
          source: sourceCapture,
          destination: destinationCapture
        )
      )
    }

    private func beginRendering(
      _ session: MotionPortalSession,
      direction: MotionTransitionDirection
    ) {
      let initialProgress = direction == .presenting ? 0.0 : 1.0
      overlay.prepare(
        session: session,
        reducedMotion: engine.decision.usesReducedMotion,
        initialProgress: initialProgress
      )
      hidePortalElements(for: session.id)
      UIView.performWithoutAnimation {
        rootHost.view.alpha = 1
        destinationHost?.view.alpha = 1
        rootHost.view.transform = .identity
      }
      engine.startPreparedTransition(
        snapshotByteCount: session.snapshotByteCount
      )
      renderCurrentProgress()
      startDriver()
    }

    private func startDriver() {
      let decision = engine.decision
      guard !decision.suspendsContinuousMotion else {
        fallback(
          .sceneInactive,
          restingAt: desiredDestination ? .destination : .source
        )
        return
      }
      driver.start(
        preferredFramesPerSecond: decision.preferredFramesPerSecond
      ) { [weak self] timestamp, deltaTime in
        guard let self else { return }
        let boundary = engine.advance(
          by: deltaTime,
          timestamp: timestamp
        )
        renderCurrentProgress()
        if let boundary {
          completeHandoff(at: boundary)
        }
      }
    }

    private func renderCurrentProgress() {
      guard let geometry = overlay.render(progress: engine.progress) else {
        return
      }
      rootHost.view.transform = CGAffineTransform(
        scaleX: geometry.backdropScale,
        y: geometry.backdropScale
      )
    }

    private func completeHandoff(at boundary: MotionTransitionBoundary) {
      driver.stop()
      _ = overlay.render(progress: boundary == .destination ? 1 : 0)
      rootHost.view.transform = .identity

      if boundary == .destination {
        rootHost.view.alpha = 0
        destinationHost?.view.alpha = 1
      } else {
        rootHost.view.alpha = 1
        destinationHost?.view.alpha = 0
      }
      if let id = currentTransitionID {
        showPortalElements(for: id)
      }
      let liveView =
        boundary == .destination ? destinationHost?.view : rootHost.view
      UIView.performWithoutAnimation {
        liveView?.setNeedsLayout()
        liveView?.layoutIfNeeded()
      }

      generation += 1
      let token = generation
      Task { @MainActor [weak self] in
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(18))
        guard let self, generation == token else { return }
        overlay.clear()
        engine.finishHandoff(at: boundary)
        if boundary == .source {
          unmountDestination()
          currentSelectionID = nil
          currentTransitionID = nil
          cachedSession = nil
          cachedContainerSize = .zero
          if clearsSelectionAtSource {
            clearsSelectionAtSource = false
            clearSelection?()
          }
        } else {
          desiredDestination = true
        }
      }
    }

    private func fallback(
      _ failure: MotionTransitionFailure,
      restingAt boundary: MotionTransitionBoundary
    ) {
      cancelPreparation()
      driver.stop()
      overlay.clear()
      visibility.showAll()
      rootHost.view.transform = .identity
      cachedSession = nil
      cachedContainerSize = .zero

      if boundary == .destination, destinationHost != nil {
        rootHost.view.alpha = 0
        destinationHost?.view.alpha = 1
        desiredDestination = true
      } else {
        rootHost.view.alpha = 1
        destinationHost?.view.alpha = 0
        unmountDestination()
        currentSelectionID = nil
        currentTransitionID = nil
        desiredDestination = false
      }
      engine.abort(failure, restingAt: boundary)
    }

    private func completeAtSourceWithoutAnimation() {
      cancelPreparation()
      driver.stop()
      overlay.clear()
      visibility.showAll()
      rootHost.view.alpha = 1
      rootHost.view.transform = .identity
      unmountDestination()
      currentSelectionID = nil
      currentTransitionID = nil
      cachedSession = nil
      cachedContainerSize = .zero
      desiredDestination = false
      engine.setInitialBoundary(.source)
    }

    private func scheduleWarmCache() {
      generation += 1
      let token = generation
      transitionTask?.cancel()
      transitionTask = Task { @MainActor [weak self] in
        guard let self else { return }
        let result = await waitForPortalSession(token: token)
        guard !Task.isCancelled,
          generation == token,
          engine.phase == .presented
        else {
          return
        }
        if case .success(let session) = result {
          cachedSession = session
          cachedContainerSize = view.bounds.size
        }
        transitionTask = nil
      }
    }

    private func invalidateCachedSession(warmIfPresented: Bool) {
      cachedSession = nil
      cachedContainerSize = .zero
      if warmIfPresented,
        desiredDestination,
        engine.phase == .presented
      {
        scheduleWarmCache()
      }
    }

    private func cancelPreparation(incrementGeneration: Bool = true) {
      transitionTask?.cancel()
      transitionTask = nil
      if incrementGeneration {
        generation += 1
      }
    }

    private func hidePortalElements(for id: MotionTransitionID) {
      visibility.hide([
        MotionPortalKey(id: id, role: .source),
        MotionPortalKey(id: id, role: .destination),
      ])
    }

    private func showPortalElements(for id: MotionTransitionID) {
      visibility.show([
        MotionPortalKey(id: id, role: .source),
        MotionPortalKey(id: id, role: .destination),
      ])
    }

    private func valid(_ frame: CGRect) -> Bool {
      frame.width > 1
        && frame.height > 1
        && frame.minX.isFinite
        && frame.minY.isFinite
        && frame.width.isFinite
        && frame.height.isFinite
    }

    private func updateGestureEdge() {
      edgePan.edges =
        view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        ? .right
        : .left
    }

    @objc
    private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
      guard let session = cachedSession,
        let id = currentTransitionID
      else {
        return
      }
      let isRightToLeft =
        view.effectiveUserInterfaceLayoutDirection == .rightToLeft
      let direction: CGFloat = isRightToLeft ? -1 : 1
      let width = max(view.bounds.width, 1)
      let translation = max(
        gesture.translation(in: view).x * direction,
        0
      )
      let velocity = max(
        gesture.velocity(in: view).x * direction,
        0
      )
      let progress = min(max(translation / width, 0), 1)

      switch gesture.state {
      case .began:
        guard
          engine.beginInteractiveDismissal(
            id: id,
            snapshotByteCount: session.snapshotByteCount
          )
        else {
          return
        }
        overlay.prepare(
          session: session,
          reducedMotion: engine.decision.usesReducedMotion,
          initialProgress: 1
        )
        hidePortalElements(for: id)
        UIView.performWithoutAnimation {
          rootHost.view.alpha = 1
          destinationHost?.view.alpha = 1
        }
        renderCurrentProgress()
      case .changed:
        engine.updateInteractiveDismissal(
          progress: progress,
          velocity: Double(velocity),
          extent: Double(width)
        )
        renderCurrentProgress()
      case .ended:
        let projected = min(
          max((translation + velocity * 0.15) / width, 0),
          1
        )
        clearsSelectionAtSource = engine.finishInteractiveDismissal(
          projectedProgress: Double(projected),
          velocity: Double(velocity),
          extent: Double(width)
        )
        startDriver()
      case .cancelled, .failed:
        clearsSelectionAtSource = false
        _ = engine.finishInteractiveDismissal(
          projectedProgress: 0,
          velocity: 0,
          extent: Double(width)
        )
        startDriver()
      default:
        break
      }
    }
  }
#endif
