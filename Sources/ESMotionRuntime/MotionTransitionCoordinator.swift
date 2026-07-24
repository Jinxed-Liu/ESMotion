import ESMotionCore
import Foundation
import OSLog
import SwiftUI

public typealias MotionRouteMutation = @MainActor () -> Void

enum MotionTransitionRegistrationRole: Hashable {
    case source
    case destination
}

struct MotionTransitionRegistrationKey: Hashable {
    let id: MotionTransitionID
    let role: MotionTransitionRegistrationRole
}

struct MotionTransitionRegistration {
    let token: UUID
    let id: MotionTransitionID
    let role: MotionTransitionRegistrationRole
    var frame: CGRect
    var viewportFrame: CGRect
    var spec: MotionTransitionSpec
    var snapshotPolicy: MotionTransitionSnapshotPolicy
    var proxy: MotionTransitionProxy?
    var snapshotProvider: MotionTransitionSnapshotProvider?
    var cleanBackdropProvider: MotionTransitionSnapshotProvider?
}

struct MotionTransitionRenderPayload {
    let session: MotionTransitionSession
    let spec: MotionTransitionSpec
    let reducedMotion: Bool
    let quality: MotionQualityTier
}

@MainActor
protocol MotionTransitionRenderer: AnyObject {
    var isReady: Bool { get }
    var latestGPUFrameDuration: TimeInterval { get }
    func cover(with snapshot: MotionTransitionSnapshot) -> Bool
    func prepare(_ payload: MotionTransitionRenderPayload) -> Bool
    func render(progress: Double, quality: MotionQualityTier)
    func crossfadeToHost(duration: TimeInterval)
    func clear()
}

@MainActor
public final class MotionTransitionCoordinator {
    public static let defaultMaximumSnapshotByteCount = 32 * 1_024 * 1_024
    public static let defaultDestinationTimeout: Duration = .milliseconds(250)

    public private(set) var phase = MotionTransitionPhase.idle
    public private(set) var latestMetrics = MotionTransitionMetrics.empty

    public let maximumSnapshotByteCount: Int
    public let destinationTimeout: Duration

    var activeProgress: Double {
        session?.progress
            ?? phase.progress
            ?? ((phase == .cancelled || phase == .presented) ? 1 : 0)
    }

    private let displayCoordinator: MotionDisplayCoordinator
    private let log = OSLog(
        subsystem: "dev.esmotion.runtime",
        category: "MotionTransition"
    )
    private var registrations:
        [MotionTransitionRegistrationKey: MotionTransitionRegistration] = [:]
    private var tokenKeys: [UUID: MotionTransitionRegistrationKey] = [:]
    private var cachedPresentedSession: MotionTransitionSession?
    private var session: MotionTransitionSession?
    private var driverRegistrationID: UUID?
    private var preparationTask: Task<Void, Never>?
    private var preparingID: MotionTransitionID?
    private var springState = MotionSpringState(value: 0, target: 1)
    private var pendingRouteMutation: MotionRouteMutation?
    private var frameIntervals: [TimeInterval] = []
    private var preparationStartedAt: TimeInterval = 0
    private var preparationDuration: TimeInterval = 0
    private var routeSettlementDuration: TimeInterval = 0
    private var transitionQuality = MotionQualityTier.full
    private var prefersReducedMotion = false
    private var usesReducedQuality = false
    private var isInteractive = false
    private var settlesAsCancellation = false
    private weak var renderer: (any MotionTransitionRenderer)?

    public init(
        displayCoordinator: MotionDisplayCoordinator? = nil,
        maximumSnapshotByteCount: Int =
            MotionTransitionCoordinator.defaultMaximumSnapshotByteCount,
        destinationTimeout: Duration =
            MotionTransitionCoordinator.defaultDestinationTimeout
    ) {
        self.displayCoordinator = displayCoordinator ?? MotionDisplayCoordinator()
        self.maximumSnapshotByteCount = max(maximumSnapshotByteCount, 1)
        self.destinationTimeout = destinationTimeout
        frameIntervals.reserveCapacity(120)
    }

    deinit {
        preparationTask?.cancel()
    }

    public var activeTransitionID: MotionTransitionID? {
        session?.id ?? cachedPresentedSession?.id ?? preparingID
    }

    public var canBeginInteractiveDismiss: Bool {
        !isInteractive
            && !phase.isAnimating
            && cachedPresentedSession != nil
            && renderer?.isReady == true
    }

    public var debugSnapshot: MotionTransitionDebugSnapshot {
        MotionTransitionDebugSnapshot(
            phase: phase,
            progress: activeProgress,
            activeCallbackCount: driverRegistrationID == nil ? 0 : 1,
            metrics: latestMetrics
        )
    }

    public func updateEnvironment(
        prefersReducedMotion: Bool,
        prefersPowerSaving: Bool,
        isSceneActive: Bool = true,
        thermalPressure: MotionThermalPressure = .nominal
    ) {
        self.prefersReducedMotion = prefersReducedMotion
        usesReducedQuality = prefersPowerSaving
            || thermalPressure != .nominal
        if !isSceneActive || thermalPressure == .critical {
            preparationTask?.cancel()
            stopDriver()
            renderer?.clear()
            cachedPresentedSession = nil
            session = nil
            isInteractive = false
            if phase != .idle {
                fail(isSceneActive ? .metalUnavailable : .backgrounded)
            }
        }
        transitionQuality = usesReducedQuality ? .efficient : .full
    }

    public func releaseCachedResources() {
        preparationTask?.cancel()
        preparingID = nil
        stopDriver()
        renderer?.clear()
        cachedPresentedSession = nil
        session = nil
        pendingRouteMutation = nil
        isInteractive = false
        phase = .idle
    }

    public func present(
        id: MotionTransitionID,
        routeMutation: @escaping MotionRouteMutation
    ) {
        if let activeID = activeTransitionID, activeID != id {
            fallback(
                .conflictingTransition,
                id: id,
                routeMutation: routeMutation
            )
            return
        }

        if session?.id == id, phase.isAnimating {
            pendingRouteMutation = nil
            session?.direction = .presenting
            retarget(to: 1)
            return
        }

        guard let source = registration(id: id, role: .source) else {
            fallback(.missingSource, id: id, routeMutation: routeMutation)
            return
        }
        guard let renderer, renderer.isReady else {
            fallback(.missingHost, id: id, routeMutation: routeMutation)
            return
        }
        guard source.snapshotPolicy != .system else {
            fallback(.snapshotUnavailable, id: id, routeMutation: routeMutation)
            return
        }

        preparationTask?.cancel()
        preparationStartedAt = ProcessInfo.processInfo.systemUptime
        preparingID = id
        phase = .preparing
        transitionQuality = usesReducedQuality ? .efficient : .full
        frameIntervals.removeAll(keepingCapacity: true)

        guard let sourceSnapshot = source.snapshotProvider?(
            snapshotRequest(for: source.frame, byteBudget: maximumSnapshotByteCount)
        ), let cleanBackdrop = source.cleanBackdropProvider?(
            snapshotRequest(
                for: source.viewportFrame,
                byteBudget: maximumSnapshotByteCount
                    - sourceSnapshot.estimatedByteCount
            )
        ) else {
            fallback(.snapshotUnavailable, id: id, routeMutation: routeMutation)
            return
        }
        guard sourceSnapshot.estimatedByteCount
            + cleanBackdrop.estimatedByteCount <= maximumSnapshotByteCount else {
            fallback(
                .snapshotMemoryExceeded,
                id: id,
                routeMutation: routeMutation
            )
            return
        }
        guard renderer.cover(with: cleanBackdrop) else {
            fallback(.metalUnavailable, id: id, routeMutation: routeMutation)
            return
        }

        mutateRoute(routeMutation)
        preparationTask = Task { @MainActor [weak self] in
            await self?.preparePresentation(
                id: id,
                source: source,
                sourceSnapshot: sourceSnapshot,
                cleanBackdrop: cleanBackdrop
            )
        }
    }

    public func dismiss(
        id requestedID: MotionTransitionID? = nil,
        routeMutation: @escaping MotionRouteMutation
    ) {
        let id = requestedID ?? activeTransitionID
        guard let id else {
            routeMutation()
            return
        }

        if session?.id == id, phase.isAnimating {
            session?.direction = .dismissing
            pendingRouteMutation = routeMutation
            retarget(to: 0)
            return
        }

        guard var presented = cachedPresentedSession,
              presented.id == id,
              let renderer,
              renderer.isReady else {
            fallback(.missingDestination, id: id, routeMutation: routeMutation)
            return
        }
        presented.direction = .dismissing
        presented.progress = 1
        presented.velocity = 0
        session = presented
        transitionQuality = usesReducedQuality ? .efficient : .full
        guard renderer.prepare(
            MotionTransitionRenderPayload(
                session: presented,
                spec: currentSpec,
                reducedMotion: prefersReducedMotion,
                quality: transitionQuality
            )
        ) else {
            fallback(.metalUnavailable, id: id, routeMutation: routeMutation)
            return
        }
        pendingRouteMutation = routeMutation
        springState = MotionSpringState(value: 1, target: 0)
        updatePhase(.dismissing(progress: 1))
        startDriver()
    }

    @discardableResult
    public func beginInteractiveDismiss(
        id requestedID: MotionTransitionID? = nil
    ) -> Bool {
        let id = requestedID ?? activeTransitionID
        guard let id,
              var presented = cachedPresentedSession,
              presented.id == id,
              let renderer,
              renderer.isReady else {
            return false
        }
        presented.direction = .dismissing
        presented.progress = 1
        session = presented
        guard renderer.prepare(
            MotionTransitionRenderPayload(
                session: presented,
                spec: currentSpec,
                reducedMotion: prefersReducedMotion,
                quality: transitionQuality
            )
        ) else {
            session = nil
            return false
        }
        stopDriver()
        isInteractive = true
        updatePhase(.dismissing(progress: 1))
        return true
    }

    public func updateInteractiveDismiss(
        progress gestureProgress: Double,
        velocity: Double = 0
    ) {
        guard isInteractive, var session else { return }
        session.progress = 1 - clamped(gestureProgress)
        session.velocity = -velocity
        self.session = session
        updatePhase(.dismissing(progress: session.progress))
        renderer?.render(
            progress: session.progress,
            quality: transitionQuality
        )
    }

    @discardableResult
    public func finishInteractiveDismiss(
        projectedProgress: Double,
        velocity: Double,
        routeMutation: @escaping MotionRouteMutation
    ) -> Bool {
        guard isInteractive, let session else { return false }
        var progress = MotionInteractiveProgress(progress: 1 - session.progress)
        let completes = progress.finish(
            projectedProgress: projectedProgress,
            velocity: velocity,
            progressThreshold: currentSpec.progressThreshold,
            velocityThreshold: currentSpec.velocityThreshold
        )
        isInteractive = false
        settlesAsCancellation = !completes
        pendingRouteMutation = completes ? routeMutation : nil
        let target = completes ? 0.0 : 1.0
        springState = MotionSpringState(
            value: session.progress,
            velocity: -velocity / max(session.destinationFrame.width, 1),
            target: target
        )
        updatePhase(.settling(target: target))
        startDriver()
        return completes
    }

    func attach(renderer: any MotionTransitionRenderer) {
        self.renderer = renderer
    }

    func detach(renderer: any MotionTransitionRenderer) {
        if self.renderer === renderer {
            self.renderer = nil
        }
    }

    func upsertRegistration(_ registration: MotionTransitionRegistration) {
        let key = MotionTransitionRegistrationKey(
            id: registration.id,
            role: registration.role
        )
        if let oldKey = tokenKeys[registration.token], oldKey != key {
            registrations[oldKey] = nil
        }
        tokenKeys[registration.token] = key
        registrations[key] = registration
    }

    func removeRegistration(token: UUID) {
        guard let key = tokenKeys.removeValue(forKey: token) else { return }
        if registrations[key]?.token == token {
            registrations[key] = nil
        }
        if key.role == .source, cachedPresentedSession?.id == key.id {
            cachedPresentedSession = nil
        }
    }

    private func preparePresentation(
        id: MotionTransitionID,
        source: MotionTransitionRegistration,
        sourceSnapshot: MotionTransitionSnapshot,
        cleanBackdrop: MotionTransitionSnapshot
    ) async {
        let settleStartedAt = ProcessInfo.processInfo.systemUptime
        guard let destination = await stableDestination(id: id) else {
            preparingID = nil
            renderer?.crossfadeToHost(duration: 0.18)
            fail(.routeSettlementTimedOut, id: id)
            return
        }
        routeSettlementDuration =
            ProcessInfo.processInfo.systemUptime - settleStartedAt
        let remainingBudgetForDestination = remainingBudgetForDestination(
            forSource: sourceSnapshot,
            and: cleanBackdrop
        )
        guard destination.snapshotPolicy == .proxy,
              let proxy = destination.proxy,
              let proxyImage = destinationSnapshot(
                from: proxy,
                maximumByteCount: remainingBudgetForDestination
              ) else {
            preparingID = nil
            renderer?.crossfadeToHost(duration: 0.18)
            fail(.proxyUnavailable, id: id)
            return
        }
        guard let destinationSnapshot = destinationSnapshot(
            from: proxyImage,
            proxy: proxy,
            maximumByteCount: remainingBudgetForDestination
        ) else {
            preparingID = nil
            renderer?.crossfadeToHost(duration: 0.18)
            fail(.snapshotMemoryExceeded, id: id)
            return
        }
        var prepared = MotionTransitionSession(
            id: id,
            direction: .presenting,
            sourceFrame: source.frame,
            destinationFrame: destination.frame,
            sourceSnapshot: sourceSnapshot,
            destinationSnapshot: destinationSnapshot,
            cleanBackdropSnapshot: cleanBackdrop,
            progress: 0,
            velocity: 0,
            routeMutationCount: 1,
            startedAt: preparationStartedAt
        )
        guard prepared.textureByteCount <= maximumSnapshotByteCount else {
            preparingID = nil
            renderer?.crossfadeToHost(duration: 0.18)
            fail(.snapshotMemoryExceeded, id: id)
            return
        }
        preparationDuration =
            ProcessInfo.processInfo.systemUptime - preparationStartedAt
        transitionQuality = usesReducedQuality ? .efficient : .full
        guard renderer?.prepare(
            MotionTransitionRenderPayload(
                session: prepared,
                spec: source.spec,
                reducedMotion: prefersReducedMotion,
                quality: transitionQuality
            )
        ) == true else {
            preparingID = nil
            renderer?.crossfadeToHost(duration: 0.18)
            fail(.metalUnavailable, id: id)
            return
        }
        prepared.firstFrameAt = nil
        preparingID = nil
        session = prepared
        springState = MotionSpringState(value: 0, target: 1)
        updatePhase(.presenting(progress: 0))
        startDriver()
    }

    private func stableDestination(
        id: MotionTransitionID
    ) async -> MotionTransitionRegistration? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: destinationTimeout)
        var previous: CGRect?
        var stableCount = 0
        while !Task.isCancelled, clock.now < deadline {
            if let candidate = registration(id: id, role: .destination),
               isVisible(candidate.frame, in: candidate.viewportFrame) {
                if let previous, framesMatch(previous, candidate.frame) {
                    stableCount += 1
                    if stableCount >= 2 { return candidate }
                } else {
                    stableCount = 0
                }
                previous = candidate.frame
            } else {
                previous = nil
                stableCount = 0
            }
            try? await Task.sleep(for: .milliseconds(9))
        }
        return nil
    }

    private func startDriver() {
        guard driverRegistrationID == nil else { return }
        driverRegistrationID = displayCoordinator.register(
            budget: .interaction,
            continuesWhenReducedMotion: true
        ) { [weak self] frame in
            self?.advance(frame)
        }
    }

    private func stopDriver() {
        if let driverRegistrationID {
            displayCoordinator.unregister(driverRegistrationID)
        }
        driverRegistrationID = nil
    }

    private func advance(_ frame: MotionFrame) {
        guard var session else {
            stopDriver()
            return
        }
        let delta = frame.deltaTime > 0 ? frame.deltaTime : 1 / 120
        frameIntervals.append(delta)
        if session.firstFrameAt == nil {
            session.firstFrameAt = ProcessInfo.processInfo.systemUptime
        }
        let spring = prefersReducedMotion
            ? MotionSpring(response: currentSpec.reducedMotionDuration, dampingRatio: 1)
            : currentSpec.spring
        springState.step(deltaTime: delta, spring: spring)
        session.progress = clamped(springState.value)
        session.velocity = springState.velocity
        self.session = session
        let directionPhase: MotionTransitionPhase = session.direction == .presenting
            ? .presenting(progress: session.progress)
            : .dismissing(progress: session.progress)
        updatePhase(directionPhase)
        renderer?.render(progress: session.progress, quality: transitionQuality)

        if springState.isSettled {
            finishSettling(at: springState.target)
        }
    }

    private func retarget(to target: Double) {
        guard var session else { return }
        session.direction = target == 1 ? .presenting : .dismissing
        self.session = session
        springState = MotionSpringState(
            value: session.progress,
            velocity: session.velocity,
            target: target
        )
        updatePhase(.settling(target: target))
        startDriver()
    }

    private func finishSettling(at target: Double) {
        guard var completed = session else { return }
        stopDriver()
        completed.progress = target
        renderer?.render(progress: target, quality: transitionQuality)

        if target == 1 {
            cachedPresentedSession = completed
            session = nil
            renderer?.clear()
            phase = settlesAsCancellation ? .cancelled : .presented
            settlesAsCancellation = false
            isInteractive = false
        } else {
            let mutation = pendingRouteMutation
            pendingRouteMutation = nil
            if mutation != nil {
                mutateRoute(mutation!)
                completed.routeMutationCount += 1
            }
            cachedPresentedSession = nil
            session = nil
            renderer?.clear()
            phase = .idle
        }
        publishMetrics(session: completed, fallback: nil)
    }

    private func fallback(
        _ reason: MotionTransitionFallbackReason,
        id: MotionTransitionID?,
        routeMutation: MotionRouteMutation
    ) {
        preparationTask?.cancel()
        preparingID = nil
        stopDriver()
        renderer?.clear()
        cachedPresentedSession = nil
        session = nil
        preparingID = nil
        routeMutation()
        fail(reason, id: id)
    }

    private func fail(
        _ reason: MotionTransitionFallbackReason,
        id: MotionTransitionID? = nil
    ) {
        phase = .failed(reason)
        latestMetrics = MotionTransitionMetrics(
            transitionID: id,
            quality: transitionQuality,
            fallbackReason: reason
        )
        os_log(
            "transition fallback: %{public}@",
            log: log,
            type: .error,
            reason.rawValue
        )
    }

    private func publishMetrics(
        session: MotionTransitionSession,
        fallback: MotionTransitionFallbackReason?
    ) {
        let sorted = frameIntervals.sorted()
        latestMetrics = MotionTransitionMetrics(
            transitionID: session.id,
            duration: ProcessInfo.processInfo.systemUptime - session.startedAt,
            preparationDuration: preparationDuration,
            firstFrameLatency: session.firstFrameAt.map {
                $0 - session.startedAt
            } ?? 0,
            routeSettlementDuration: routeSettlementDuration,
            gpuFrameDuration: renderer?.latestGPUFrameDuration ?? 0,
            frameCount: frameIntervals.count,
            callbackCount: driverRegistrationID == nil ? 0 : 1,
            textureByteCount: session.textureByteCount,
            p50FrameInterval: percentile(0.50, in: sorted),
            p95FrameInterval: percentile(0.95, in: sorted),
            p99FrameInterval: percentile(0.99, in: sorted),
            quality: transitionQuality,
            fallbackReason: fallback
        )
    }

    private var currentSpec: MotionTransitionSpec {
        guard let id = activeTransitionID else { return .card }
        return registration(id: id, role: .source)?.spec ?? .card
    }

    private func registration(
        id: MotionTransitionID,
        role: MotionTransitionRegistrationRole
    ) -> MotionTransitionRegistration? {
        registrations[MotionTransitionRegistrationKey(id: id, role: role)]
    }

    private func mutateRoute(_ mutation: MotionRouteMutation) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mutation()
        }
    }

    private func updatePhase(_ phase: MotionTransitionPhase) {
        self.phase = phase
    }

    private func snapshotRequest(
        for frame: CGRect,
        byteBudget: Int
    ) -> MotionTransitionSnapshotRequest {
        MotionTransitionSnapshotRequest(
            frame: frame,
            maximumByteCount: max(byteBudget, 1),
            preferredScale: transitionQuality == .full ? 2 : 1
        )
    }

    private func remainingBudgetForDestination(
        forSource sourceSnapshot: MotionTransitionSnapshot,
        and cleanBackdrop: MotionTransitionSnapshot
    ) -> Int {
        max(
            maximumSnapshotByteCount
                - sourceSnapshot.estimatedByteCount
                - cleanBackdrop.estimatedByteCount,
            1
        )
    }

    private func destinationSnapshot(
        from proxy: MotionTransitionProxy,
        maximumByteCount: Int
    ) -> CGImage? {
        let destinationRequest = MotionTransitionSnapshotRequest(
            frame: CGRect(
                origin: .zero,
                size: proxy.pointSize
            ),
            maximumByteCount: min(maximumSnapshotByteCount, max(maximumByteCount, 1)),
            preferredScale: transitionQuality == .full ? 2 : 1
        )
        return proxy.snapshotProvider(destinationRequest)
    }

    private func destinationSnapshot(
        from image: CGImage,
        proxy: MotionTransitionProxy,
        maximumByteCount: Int
    ) -> MotionTransitionSnapshot? {
        let fitScale = destinationScale(
            image: image,
            pointSize: proxy.pointSize
        )
        let direct = MotionTransitionSnapshot(image: image, scale: fitScale)
        if direct.estimatedByteCount <= maximumByteCount {
            return direct
        }
        let maxScale = minimumScaleForByteBudget(
            sourceSize: CGSize(width: image.width, height: image.height),
            maxBytes: maximumByteCount
        )
        return fitSnapshot(
            from: image,
            proxyPointSize: proxy.pointSize,
            targetScale: min(maxScale, fitScale)
        )
    }

    private func destinationScale(
        image: CGImage,
        pointSize: CGSize
    ) -> CGFloat {
        let scaleByWidth = CGFloat(image.width) / max(pointSize.width, 1)
        let scaleByHeight = CGFloat(image.height) / max(pointSize.height, 1)
        return max(max(scaleByWidth, scaleByHeight), 0.01)
    }

    private func minimumScaleForByteBudget(
        sourceSize: CGSize,
        maxBytes: Int
    ) -> CGFloat {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              maxBytes > 0 else {
            return 0.01
        }
        let maxPixels = CGFloat(maxBytes) / 4
        let sourcePixels = sourceSize.width * sourceSize.height
        let scaleForBytes = sqrt(max(maxPixels, 1) / max(sourcePixels, 1))
        return max(min(scaleForBytes, 1), 0.01)
    }

    private func fitSnapshot(
        from image: CGImage,
        proxyPointSize: CGSize,
        targetScale: CGFloat
    ) -> MotionTransitionSnapshot? {
        guard targetScale > 0,
              targetScale < 1,
              image.width > 0,
              image.height > 0 else {
            return nil
        }
        let targetWidth = max(1, Int(CGFloat(image.width) * targetScale))
        let targetHeight = max(1, Int(CGFloat(image.height) * targetScale))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(targetWidth),
                height: CGFloat(targetHeight)
            )
        )
        guard let cgImage = context.makeImage() else { return nil }
        let scaled = destinationScale(
            image: cgImage,
            pointSize: proxyPointSize
        )
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        return MotionTransitionSnapshot(image: cgImage, scale: scaled)
    }

    private func isVisible(_ frame: CGRect, in viewport: CGRect) -> Bool {
        guard !frame.isEmpty, !viewport.isEmpty else { return false }
        let intersection = frame.intersection(viewport)
        return !intersection.isEmpty
            && intersection.width * intersection.height
                >= frame.width * frame.height * 0.98
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func percentile(
        _ percentile: Double,
        in sortedValues: [TimeInterval]
    ) -> TimeInterval {
        guard !sortedValues.isEmpty else { return 0 }
        let index = Int(
            (Double(sortedValues.count - 1) * percentile).rounded()
        )
        return sortedValues[min(max(index, 0), sortedValues.count - 1)]
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
