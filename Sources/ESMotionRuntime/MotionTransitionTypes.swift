import CoreGraphics
import ESMotionCore
import Foundation

public enum MotionTransitionRenderingMode: String, Codable, Sendable {
    case system
    case compositor
}

public enum MotionTransitionSnapshotPolicy: String, Codable, Sendable {
    case automatic
    case proxy
    case system
}

public enum MotionTransitionFallbackReason: String, Codable, Sendable {
    case missingHost
    case missingSource
    case missingDestination
    case proxyUnavailable
    case snapshotUnavailable
    case metalUnavailable
    case snapshotMemoryExceeded
    case routeSettlementTimedOut
    case conflictingTransition
    case backgrounded
    case unsupportedPlatform
}

public enum MotionTransitionDirection: String, Codable, Sendable {
    case presenting
    case dismissing
}

public enum MotionTransitionPhase: Equatable, Sendable {
    case idle
    case preparing
    case presenting(progress: Double)
    case presented
    case dismissing(progress: Double)
    case settling(target: Double)
    case cancelled
    case failed(MotionTransitionFallbackReason)

    public var progress: Double? {
        switch self {
        case .presenting(let progress), .dismissing(let progress):
            progress
        case .settling(let target):
            target
        case .presented:
            1
        case .idle, .preparing, .cancelled, .failed:
            nil
        }
    }

    public var isAnimating: Bool {
        switch self {
        case .preparing, .presenting, .dismissing, .settling:
            true
        case .idle, .presented, .cancelled, .failed:
            false
        }
    }
}

public struct MotionTransitionProxy: @unchecked Sendable {
    public let pointSize: CGSize
    public let isOpaque: Bool
    let snapshotProvider: @MainActor (MotionTransitionSnapshotRequest) -> CGImage?

    public init(
        pointSize: CGSize,
        isOpaque: Bool = true,
        snapshotProvider: @escaping @MainActor () -> CGImage?
    ) {
        self.pointSize = pointSize
        self.isOpaque = isOpaque
        self.snapshotProvider = { _ in snapshotProvider() }
    }

    public init(
        pointSize: CGSize,
        isOpaque: Bool = true,
        snapshotProvider: @escaping @MainActor (
            MotionTransitionSnapshotRequest
        ) -> CGImage?
    ) {
        self.pointSize = pointSize
        self.isOpaque = isOpaque
        self.snapshotProvider = snapshotProvider
    }
}

struct MotionTransitionSnapshot: @unchecked Sendable {
    let image: CGImage
    let scale: CGFloat

    init(image: CGImage, scale: CGFloat = 1) {
        self.image = image
        self.scale = max(scale, 0.01)
    }

    var estimatedByteCount: Int {
        image.bytesPerRow * image.height
    }
}

public struct MotionTransitionSnapshotRequest: Equatable, Sendable {
    public let frame: CGRect
    public let maximumByteCount: Int
    public let preferredScale: CGFloat
}

typealias MotionTransitionSnapshotProvider =
    @MainActor (MotionTransitionSnapshotRequest) -> MotionTransitionSnapshot?

struct MotionTransitionSession {
    let id: MotionTransitionID
    var direction: MotionTransitionDirection
    var sourceFrame: CGRect
    var destinationFrame: CGRect
    var sourceSnapshot: MotionTransitionSnapshot
    var destinationSnapshot: MotionTransitionSnapshot
    var cleanBackdropSnapshot: MotionTransitionSnapshot
    var progress: Double
    var velocity: Double
    var routeMutationCount: Int
    let startedAt: TimeInterval
    var firstFrameAt: TimeInterval?

    var textureByteCount: Int {
        sourceSnapshot.estimatedByteCount
            + destinationSnapshot.estimatedByteCount
            + cleanBackdropSnapshot.estimatedByteCount
    }
}

public struct MotionTransitionMetrics: Equatable, Sendable {
    public let transitionID: MotionTransitionID?
    public let duration: TimeInterval
    public let preparationDuration: TimeInterval
    public let firstFrameLatency: TimeInterval
    public let routeSettlementDuration: TimeInterval
    public let gpuFrameDuration: TimeInterval
    public let frameCount: Int
    public let callbackCount: Int
    public let textureByteCount: Int
    public let p50FrameInterval: TimeInterval
    public let p95FrameInterval: TimeInterval
    public let p99FrameInterval: TimeInterval
    public let quality: MotionQualityTier
    public let fallbackReason: MotionTransitionFallbackReason?

    public init(
        transitionID: MotionTransitionID? = nil,
        duration: TimeInterval = 0,
        preparationDuration: TimeInterval = 0,
        firstFrameLatency: TimeInterval = 0,
        routeSettlementDuration: TimeInterval = 0,
        gpuFrameDuration: TimeInterval = 0,
        frameCount: Int = 0,
        callbackCount: Int = 0,
        textureByteCount: Int = 0,
        p50FrameInterval: TimeInterval = 0,
        p95FrameInterval: TimeInterval = 0,
        p99FrameInterval: TimeInterval = 0,
        quality: MotionQualityTier = .full,
        fallbackReason: MotionTransitionFallbackReason? = nil
    ) {
        self.transitionID = transitionID
        self.duration = max(duration, 0)
        self.preparationDuration = max(preparationDuration, 0)
        self.firstFrameLatency = max(firstFrameLatency, 0)
        self.routeSettlementDuration = max(routeSettlementDuration, 0)
        self.gpuFrameDuration = max(gpuFrameDuration, 0)
        self.frameCount = max(frameCount, 0)
        self.callbackCount = max(callbackCount, 0)
        self.textureByteCount = max(textureByteCount, 0)
        self.p50FrameInterval = max(p50FrameInterval, 0)
        self.p95FrameInterval = max(p95FrameInterval, 0)
        self.p99FrameInterval = max(p99FrameInterval, 0)
        self.quality = quality
        self.fallbackReason = fallbackReason
    }

    public static let empty = MotionTransitionMetrics()
}

public struct MotionTransitionDebugSnapshot: Equatable, Sendable {
    public let phase: MotionTransitionPhase
    public let progress: Double
    public let activeCallbackCount: Int
    public let metrics: MotionTransitionMetrics

    public init(
        phase: MotionTransitionPhase,
        progress: Double,
        activeCallbackCount: Int,
        metrics: MotionTransitionMetrics
    ) {
        self.phase = phase
        self.progress = min(max(progress, 0), 1)
        self.activeCallbackCount = max(activeCallbackCount, 0)
        self.metrics = metrics
    }
}
