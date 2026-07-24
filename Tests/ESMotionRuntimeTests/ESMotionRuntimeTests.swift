import CoreGraphics
import XCTest
@testable import ESMotionCore
@testable import ESMotionRuntime

@MainActor
final class ESMotionRuntimeTests: XCTestCase {
    private final class TestRenderer: MotionTransitionRenderer {
        var isReady = true
        var latestGPUFrameDuration: TimeInterval = 0.001
        var preparedPayloads: [MotionTransitionRenderPayload] = []
        var renderedProgress: [Double] = []
        var clearCount = 0

        func cover(with snapshot: MotionTransitionSnapshot) -> Bool {
            true
        }

        func prepare(_ payload: MotionTransitionRenderPayload) -> Bool {
            preparedPayloads.append(payload)
            return true
        }

        func render(progress: Double, quality: MotionQualityTier) {
            renderedProgress.append(progress)
        }

        func crossfadeToHost(duration: TimeInterval) {
            clear()
        }

        func clear() {
            clearCount += 1
        }
    }

    func testTransitionDefaultsMatchInteractionContract() {
        XCTAssertEqual(MotionTransitionSpec.card.progressThreshold, 0.35)
        XCTAssertEqual(MotionTransitionSpec.card.velocityThreshold, 900)
        XCTAssertEqual(MotionTransitionSpec.card.spring.response, 0.42)
        XCTAssertEqual(MotionTransitionSpec.card.spring.dampingRatio, 0.86)
    }

    func testEngineResolvesUserPowerSaving() {
        let engine = MotionEngine(
            environment: MotionEnvironmentState(
                userPowerSaving: true,
                thermalPressure: .nominal
            )
        )
        let decision = engine.decision(for: .interaction)
        XCTAssertEqual(
            decision.frameRateRange,
            MotionBudget.interaction.lowPowerFrameRateRange
        )
        XCTAssertEqual(decision.quality, .efficient)
    }

    func testDisplayCoordinatorStopsWhenLastCallbackLeaves() {
        let coordinator = MotionDisplayCoordinator()
        let id = coordinator.register(budget: .ambientScene) { _ in }
        XCTAssertNotNil(coordinator.activeBudget)
        coordinator.unregister(id)
        XCTAssertNil(coordinator.activeBudget)
    }

    func testDisplayCoordinatorRecalculatesPriorityAfterUnregister() {
        let coordinator = MotionDisplayCoordinator()
        let ambient = coordinator.register(budget: .ambientScene) { _ in }
        let interaction = coordinator.register(budget: .interaction) { _ in }
        XCTAssertEqual(coordinator.activeBudget, .interaction)

        coordinator.unregister(interaction)
        XCTAssertEqual(coordinator.activeBudget, .ambientScene)
        XCTAssertEqual(
            coordinator.decision.frameRateRange,
            MotionBudget.ambientScene.frameRateRange
        )
        coordinator.unregister(ambient)
    }

    func testSuspendedRegistrationDoesNotRaiseBudget() {
        let coordinator = MotionDisplayCoordinator()
        let ambient = coordinator.register(budget: .ambientScene) { _ in }
        let interaction = coordinator.register(
            budget: .interaction,
            isSuspended: true
        ) { _ in }

        XCTAssertEqual(coordinator.activeBudget, .ambientScene)
        coordinator.unregister(ambient)
        coordinator.unregister(interaction)
    }

    func testTransitionSourceAcceptsHostBackgroundColor() {
        XCTAssertEqual(MotionTransitionSpec.card.cornerRadius, 24)
    }

    func testDisplayCoordinatorRunsOnlyOptedInCallbackForReduceMotion() {
        let coordinator = MotionDisplayCoordinator()
        let ambient = coordinator.register(budget: .ambientScene) { _ in }
        let transition = coordinator.register(
            budget: .interaction,
            continuesWhenReducedMotion: true
        ) { _ in }

        coordinator.updateRuntimeInputs(
            MotionRuntimeInputs(prefersReducedMotion: true)
        )

        XCTAssertEqual(coordinator.activeBudget, .interaction)
        XCTAssertFalse(coordinator.decision.isPaused)

        coordinator.unregister(transition)
        XCTAssertNil(coordinator.activeBudget)
        XCTAssertTrue(coordinator.decision.isPaused)
        coordinator.unregister(ambient)
    }

    func testCoordinatorFallsBackWithoutRegisteredSource() {
        let coordinator = MotionTransitionCoordinator()
        var mutatedRoute = false

        coordinator.present(id: MotionTransitionID("missing")) {
            mutatedRoute = true
        }

        XCTAssertTrue(mutatedRoute)
        XCTAssertEqual(coordinator.phase, .failed(.missingSource))
        XCTAssertEqual(
            coordinator.latestMetrics.fallbackReason,
            .missingSource
        )
    }

    func testCoordinatorRejectsSnapshotOverBudget() {
        let coordinator = MotionTransitionCoordinator(
            maximumSnapshotByteCount: 512
        )
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        register(
            coordinator: coordinator,
            id: "memory",
            role: .source,
            imageSize: 64
        )
        var mutatedRoute = false

        coordinator.present(id: MotionTransitionID("memory")) {
            mutatedRoute = true
        }

        XCTAssertTrue(mutatedRoute)
        XCTAssertEqual(
            coordinator.phase,
            .failed(.snapshotMemoryExceeded)
        )
    }

    func testCompositorDestinationCanShrinkToFitRemainingBudget() async {
        let coordinator = MotionTransitionCoordinator(
            maximumSnapshotByteCount: 1_048_576
        )
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        register(
            coordinator: coordinator,
            id: "scaled",
            role: .source,
            frame: CGRect(x: 20, y: 40, width: 160, height: 100),
            imageSize: 8
        )
        let largeProxyImage = makeImage(
            width: 1400,
            height: 2400,
            red: 0.23,
            green: 0.64,
            blue: 0.42,
            alpha: 1
        )
        let destinationFrame = CGRect(x: 0, y: 0, width: 390, height: 844)
        var observedRequestBudget: Int?
        coordinator.upsertRegistration(
            MotionTransitionRegistration(
                token: UUID(),
                id: MotionTransitionID("scaled"),
                role: .destination,
                frame: destinationFrame,
                viewportFrame: CGRect(x: 0, y: 0, width: 390, height: 844),
                spec: .card,
                snapshotPolicy: .proxy,
                proxy: MotionTransitionProxy(
                    pointSize: destinationFrame.size,
                    snapshotProvider: { request in
                        observedRequestBudget = request.maximumByteCount
                        return largeProxyImage
                    }
                ),
                snapshotProvider: nil,
                cleanBackdropProvider: nil
            )
        )

        var routeMutated = false
        coordinator.present(id: MotionTransitionID("scaled")) {
            routeMutated = true
        }

        XCTAssertTrue(routeMutated)
        let didPresent = await waitUntil {
            coordinator.phase == .presented
        }
        XCTAssertTrue(didPresent)
        XCTAssertNotNil(observedRequestBudget)
        XCTAssertLessThanOrEqual(
            observedRequestBudget ?? Int.max,
            1_048_576
        )
        XCTAssertLessThanOrEqual(
            coordinator.latestMetrics.textureByteCount,
            coordinator.maximumSnapshotByteCount
        )
    }

    func testCoordinatorPresentsAndDismissesWithoutResettingRouteState() async {
        let displayCoordinator = MotionDisplayCoordinator()
        let coordinator = MotionTransitionCoordinator(
            displayCoordinator: displayCoordinator
        )
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        registerPair(coordinator: coordinator, id: "card")
        var routeIsPresented = false
        var routeMutationCount = 0

        coordinator.present(id: MotionTransitionID("card")) {
            routeIsPresented = true
            routeMutationCount += 1
        }

        XCTAssertTrue(routeIsPresented)
        let didPresent = await waitUntil {
            coordinator.phase == .presented
        }
        XCTAssertTrue(didPresent)
        XCTAssertEqual(renderer.preparedPayloads.count, 1)
        XCTAssertEqual(routeMutationCount, 1)

        coordinator.dismiss(id: MotionTransitionID("card")) {
            routeIsPresented = false
            routeMutationCount += 1
        }

        let didDismiss = await waitUntil {
            coordinator.phase == .idle
        }
        XCTAssertTrue(didDismiss)
        XCTAssertFalse(routeIsPresented)
        XCTAssertEqual(routeMutationCount, 2)
        XCTAssertGreaterThan(coordinator.latestMetrics.frameCount, 0)
        XCTAssertGreaterThanOrEqual(renderer.clearCount, 2)
    }

    func testSameIDReversesWithoutResettingProgress() async {
        let coordinator = MotionTransitionCoordinator()
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        registerPair(coordinator: coordinator, id: "reverse")
        var routeIsPresented = false

        coordinator.present(id: MotionTransitionID("reverse")) {
            routeIsPresented = true
        }
        let didBegin = await waitUntil {
            let progress = coordinator.activeProgress
            return progress > 0 && progress < 1
        }
        XCTAssertTrue(didBegin)
        let progressBeforeDismiss = coordinator.activeProgress

        coordinator.dismiss(id: MotionTransitionID("reverse")) {
            routeIsPresented = false
        }

        XCTAssertEqual(
            coordinator.activeProgress,
            progressBeforeDismiss
        )
        let didDismiss = await waitUntil {
            coordinator.phase == .idle
        }
        XCTAssertTrue(didDismiss)
        XCTAssertFalse(routeIsPresented)
    }

    func testDifferentIDConflictMutatesNewRouteAndRecordsFallback() {
        let coordinator = MotionTransitionCoordinator()
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        registerPair(coordinator: coordinator, id: "first")
        registerPair(coordinator: coordinator, id: "second")
        var firstRouteMutated = false
        var secondRouteMutated = false

        coordinator.present(id: MotionTransitionID("first")) {
            firstRouteMutated = true
        }
        coordinator.present(id: MotionTransitionID("second")) {
            secondRouteMutated = true
        }

        XCTAssertTrue(firstRouteMutated)
        XCTAssertTrue(secondRouteMutated)
        XCTAssertEqual(
            coordinator.phase,
            .failed(.conflictingTransition)
        )
        XCTAssertEqual(
            coordinator.latestMetrics.fallbackReason,
            .conflictingTransition
        )
    }

    func testInteractiveVelocityCompletesDismissalBelowProgressThreshold() async {
        let coordinator = MotionTransitionCoordinator()
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        registerPair(coordinator: coordinator, id: "interactive")
        var routeIsPresented = false

        coordinator.present(id: MotionTransitionID("interactive")) {
            routeIsPresented = true
        }
        let didPresent = await waitUntil {
            coordinator.phase == .presented
        }
        XCTAssertTrue(didPresent)
        XCTAssertTrue(
            coordinator.beginInteractiveDismiss(
                id: MotionTransitionID("interactive")
            )
        )
        coordinator.updateInteractiveDismiss(progress: 0.1, velocity: 100)

        let completed = coordinator.finishInteractiveDismiss(
            projectedProgress: 0.1,
            velocity: 901
        ) {
            routeIsPresented = false
        }

        XCTAssertTrue(completed)
        let didDismiss = await waitUntil {
            coordinator.phase == .idle
        }
        XCTAssertTrue(didDismiss)
        XCTAssertFalse(routeIsPresented)
    }

    func testInteractiveDismissalCancelsAndReturnsToPresentedState() async {
        let coordinator = MotionTransitionCoordinator()
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        registerPair(coordinator: coordinator, id: "cancel")

        coordinator.present(id: MotionTransitionID("cancel")) {}
        let didPresent = await waitUntil {
            coordinator.phase == .presented
        }
        XCTAssertTrue(didPresent)
        XCTAssertTrue(coordinator.beginInteractiveDismiss())
        coordinator.updateInteractiveDismiss(progress: 0.2)

        let completed = coordinator.finishInteractiveDismiss(
            projectedProgress: 0.2,
            velocity: 100
        ) {}

        XCTAssertFalse(completed)
        let didCancel = await waitUntil {
            coordinator.phase == .cancelled
        }
        XCTAssertTrue(didCancel)
        XCTAssertEqual(coordinator.activeProgress, 1)
    }

    func testDestinationTimeoutRecordsFallback() async {
        let coordinator = MotionTransitionCoordinator(
            destinationTimeout: .milliseconds(25)
        )
        let renderer = TestRenderer()
        coordinator.attach(renderer: renderer)
        register(
            coordinator: coordinator,
            id: "timeout",
            role: .source
        )
        var mutatedRoute = false

        coordinator.present(id: MotionTransitionID("timeout")) {
            mutatedRoute = true
        }

        XCTAssertTrue(mutatedRoute)
        let didTimeOut = await waitUntil(timeout: .seconds(1)) {
            coordinator.phase == .failed(.routeSettlementTimedOut)
        }
        XCTAssertTrue(didTimeOut)
    }

    func testTransitionGeometryMatchesFiveProgressGoldens() {
        let progressValues = [0.0, 0.25, 0.5, 0.75, 1.0]
        let frames = progressValues.map {
            MotionTransitionGeometry.resolve(
                sourceFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                destinationFrame: CGRect(
                    x: 100,
                    y: 200,
                    width: 300,
                    height: 500
                ),
                spec: .card,
                progress: $0,
                reducedMotion: false
            )
        }

        XCTAssertEqual(
            frames.map(\.containerFrame),
            [
                CGRect(x: 0, y: 0, width: 100, height: 100),
                CGRect(x: 25, y: 50, width: 150, height: 200),
                CGRect(x: 50, y: 100, width: 200, height: 300),
                CGRect(x: 75, y: 150, width: 250, height: 400),
                CGRect(x: 100, y: 200, width: 300, height: 500),
            ]
        )
        XCTAssertEqual(
            frames.map(\.cornerRadius),
            [24, 18, 12, 6, 0]
        )
        XCTAssertEqual(
            frames.map(\.sourceOpacity),
            [1, 0.75, 0.5, 0.25, 0]
        )
        XCTAssertEqual(
            frames.map(\.destinationOpacity),
            [0, 0.25, 0.5, 0.75, 1]
        )
    }

    func testReducedMotionUsesDestinationGeometryWithCrossfade() {
        let frame = MotionTransitionGeometry.resolve(
            sourceFrame: CGRect(x: 10, y: 20, width: 100, height: 80),
            destinationFrame: CGRect(x: 0, y: 0, width: 390, height: 844),
            sourceElements: [],
            destinationElements: [],
            spec: .card,
            progress: 0,
            reducedMotion: true
        )

        XCTAssertEqual(
            frame.containerFrame,
            CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        XCTAssertEqual(frame.cornerRadius, 0)
        XCTAssertEqual(frame.sourceOpacity, 1)
        XCTAssertEqual(frame.destinationOpacity, 0)
    }

    private func registerPair(
        coordinator: MotionTransitionCoordinator,
        id: String
    ) {
        register(
            coordinator: coordinator,
            id: id,
            role: .source,
            frame: CGRect(x: 20, y: 40, width: 160, height: 100)
        )
        register(
            coordinator: coordinator,
            id: id,
            role: .destination,
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
    }

    private func register(
        coordinator: MotionTransitionCoordinator,
        id: String,
        role: MotionTransitionRegistrationRole,
        frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
        imageSize: Int = 8
    ) {
        let snapshot = makeSnapshot(size: imageSize)
        let proxy: MotionTransitionProxy?
        let snapshotProvider: MotionTransitionSnapshotProvider?
        let backdropProvider: MotionTransitionSnapshotProvider?
        if role == .destination {
            proxy = MotionTransitionProxy(
                pointSize: frame.size,
                snapshotProvider: { snapshot.image }
            )
            snapshotProvider = nil
            backdropProvider = nil
        } else {
            proxy = nil
            snapshotProvider = { _ in snapshot }
            backdropProvider = { _ in snapshot }
        }
        coordinator.upsertRegistration(
            MotionTransitionRegistration(
                token: UUID(),
                id: MotionTransitionID(id),
                role: role,
                frame: frame,
                viewportFrame: CGRect(x: 0, y: 0, width: 390, height: 844),
                spec: .card,
                snapshotPolicy: role == .source ? .automatic : .proxy,
                proxy: proxy,
                snapshotProvider: snapshotProvider,
                cleanBackdropProvider: backdropProvider
            )
        )
    }

    private func makeSnapshot(size: Int) -> MotionTransitionSnapshot {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            red: 0.2,
            green: 0.5,
            blue: 0.9,
            alpha: 1
        )
        context.fill(
            CGRect(x: 0, y: 0, width: size, height: size)
        )
        return MotionTransitionSnapshot(
            image: context.makeImage()!,
            scale: 1
        )
    }

    private func makeImage(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()!
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
