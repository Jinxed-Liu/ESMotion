import ESMotionCore
import Foundation
import QuartzCore

@MainActor
public final class MotionDisplayCoordinator {
    public typealias Callback = @MainActor (MotionFrame) -> Void

    private struct Registration {
        var budget: MotionBudget
        var isSuspended: Bool
        var callback: Callback
    }

    public private(set) var activeBudget: MotionBudget?
    public private(set) var decision = MotionRuntimeDecision(
        isPaused: true,
        frameRateRange: .ambient,
        renderScale: 1,
        quality: .full
    )

    private let metricsStore: MotionMetricsStore
    private var registrations: [UUID: Registration] = [:]
    private var runtimeInputs = MotionRuntimeInputs()
    private var previousTimestamp: TimeInterval?
    private var timeWrap: TimeInterval = 1_800

    #if os(iOS)
    private var displayLink: CADisplayLink?
    #else
    private var timer: Timer?
    #endif

    public init(metricsStore: MotionMetricsStore = MotionMetricsStore()) {
        self.metricsStore = metricsStore
    }

    isolated deinit {
        #if os(iOS)
        displayLink?.invalidate()
        #else
        timer?.invalidate()
        #endif
    }

    @discardableResult
    public func register(
        budget: MotionBudget,
        isSuspended: Bool = false,
        callback: @escaping Callback
    ) -> UUID {
        let id = UUID()
        registrations[id] = Registration(
            budget: budget,
            isSuspended: isSuspended,
            callback: callback
        )
        resolveActivePolicy()
        ensureDriver()
        return id
    }

    public func unregister(_ id: UUID) {
        registrations[id] = nil
        resolveActivePolicy()
        if registrations.isEmpty {
            activeBudget = nil
            stopDriver()
        }
    }

    public func updateRegistration(
        _ id: UUID,
        budget: MotionBudget? = nil,
        isSuspended: Bool? = nil
    ) {
        guard var registration = registrations[id] else { return }
        if let budget {
            registration.budget = budget
        }
        if let isSuspended {
            registration.isSuspended = isSuspended
        }
        registrations[id] = registration
        resolveActivePolicy()
    }

    public func updateRuntimeInputs(_ inputs: MotionRuntimeInputs) {
        runtimeInputs = inputs
        resolveActivePolicy()
    }

    public func apply(
        _ decision: MotionRuntimeDecision,
        timeWrap: TimeInterval
    ) {
        self.decision = decision
        self.timeWrap = max(timeWrap, 1)
        updateDriverPolicy()
    }

    public func removeAllCallbacks() {
        registrations.removeAll(keepingCapacity: true)
        activeBudget = nil
        stopDriver()
    }

    private func resolveActivePolicy() {
        let activeRegistrations = registrations.values.filter {
            !$0.isSuspended
        }
        activeBudget = activeRegistrations
            .map(\.budget)
            .reduce(nil) { current, incoming in
                highestPriorityBudget(
                    current: current,
                    incoming: incoming
                )
            }

        guard let activeBudget else {
            decision = MotionRuntimeDecision(
                isPaused: true,
                frameRateRange: .ambient,
                renderScale: 1,
                quality: .minimal
            )
            updateDriverPolicy()
            return
        }

        timeWrap = activeBudget.timeWrap
        decision = MotionRuntimePolicy.resolve(
            budget: activeBudget,
            inputs: runtimeInputs
        )
        updateDriverPolicy()
    }

    private func highestPriorityBudget(
        current: MotionBudget?,
        incoming: MotionBudget
    ) -> MotionBudget {
        guard let current else { return incoming }
        return priority(of: incoming.workload) < priority(of: current.workload)
            ? incoming
            : current
    }

    private func priority(of workload: MotionWorkload) -> Int {
        switch workload {
        case .interaction:
            0
        case .foregroundScene:
            1
        case .ambientScene:
            2
        }
    }

    private func ensureDriver() {
        #if os(iOS)
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #else
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: 1 / 60,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerDidFire()
            }
        }
        #endif
        updateDriverPolicy()
    }

    private func stopDriver() {
        #if os(iOS)
        displayLink?.invalidate()
        displayLink = nil
        #else
        timer?.invalidate()
        timer = nil
        #endif
        previousTimestamp = nil
    }

    private func updateDriverPolicy() {
        #if os(iOS)
        guard let displayLink else { return }
        let range = decision.frameRateRange
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(range.minimum),
            maximum: Float(range.maximum),
            preferred: Float(range.preferred)
        )
        displayLink.isPaused = decision.isPaused
            || registrations.values.allSatisfy(\.isSuspended)
        #else
        if decision.isPaused {
            timer?.fireDate = .distantFuture
        } else {
            timer?.fireDate = .now
        }
        #endif
    }

    #if os(iOS)
    @objc
    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
        emitFrame(
            timestamp: displayLink.timestamp,
            targetTimestamp: displayLink.targetTimestamp
        )
    }
    #else
    private func timerDidFire() {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let interval = 1 / Double(decision.frameRateRange.preferred)
        emitFrame(
            timestamp: timestamp,
            targetTimestamp: timestamp + interval
        )
    }
    #endif

    private func emitFrame(
        timestamp: TimeInterval,
        targetTimestamp: TimeInterval
    ) {
        let activeRegistrations = registrations.values.filter {
            !$0.isSuspended
        }
        guard !decision.isPaused, !activeRegistrations.isEmpty else {
            return
        }
        let delta = previousTimestamp.map { timestamp - $0 } ?? 0
        previousTimestamp = timestamp

        let frame = MotionFrame(
            timestamp: timestamp,
            targetTimestamp: targetTimestamp,
            deltaTime: delta,
            wrappedTime: timestamp.truncatingRemainder(dividingBy: timeWrap),
            renderScale: decision.renderScale,
            quality: decision.quality
        )
        for registration in activeRegistrations {
            registration.callback(frame)
        }

        let sample = MotionMetricSample(
            timestamp: timestamp,
            frameInterval: delta,
            callbackCount: activeRegistrations.count,
            quality: decision.quality
        )
        Task {
            await metricsStore.append(sample)
        }
    }
}
