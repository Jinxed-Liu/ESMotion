import ESMotionCore
import SwiftUI

@MainActor
public struct MotionTransitionDebugHUD: View {
    private let coordinator: MotionTransitionCoordinator

    public init(coordinator: MotionTransitionCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let snapshot = coordinator.debugSnapshot
            VStack(alignment: .leading, spacing: 3) {
                Text(phaseText(snapshot.phase))
                    .fontWeight(.semibold)
                Text(
                    "progress \(snapshot.progress, format: .number.precision(.fractionLength(3)))"
                )
                Text(
                    "p50 \(milliseconds(snapshot.metrics.p50FrameInterval))  "
                        + "p95 \(milliseconds(snapshot.metrics.p95FrameInterval))  "
                        + "p99 \(milliseconds(snapshot.metrics.p99FrameInterval))"
                )
                Text(
                    "frames \(snapshot.metrics.frameCount)  "
                        + "callbacks \(snapshot.activeCallbackCount)"
                )
                Text(
                    "textures \(byteText(snapshot.metrics.textureByteCount))  "
                        + "quality \(qualityText(snapshot.metrics.quality))"
                )
                Text(
                    "prepare \(milliseconds(snapshot.metrics.preparationDuration))  "
                        + "gpu \(milliseconds(snapshot.metrics.gpuFrameDuration))"
                )
                if let fallback = snapshot.metrics.fallbackReason {
                    Text("fallback \(fallback.rawValue)")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.black.opacity(0.78), in: .rect(cornerRadius: 9))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("esmotion-debug-hud")
            .accessibilityLabel("ESMotion transition diagnostics")
            .accessibilityValue(debugValue(snapshot))
        }
    }

    private func phaseText(_ phase: MotionTransitionPhase) -> String {
        switch phase {
        case .idle:
            "idle"
        case .preparing:
            "preparing"
        case .presenting:
            "presenting"
        case .presented:
            "presented"
        case .dismissing:
            "dismissing"
        case .settling(let target):
            String(format: "settling %.2f", target)
        case .cancelled:
            "cancelled"
        case .failed(let reason):
            "failed \(reason.rawValue)"
        }
    }

    private func milliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.2fms", interval * 1_000)
    }

    private func byteText(_ bytes: Int) -> String {
        String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }

    private func qualityText(_ quality: MotionQualityTier) -> String {
        switch quality {
        case .full:
            "full"
        case .balanced:
            "balanced"
        case .efficient:
            "efficient"
        case .minimal:
            "minimal"
        }
    }

    private func debugValue(
        _ snapshot: MotionTransitionDebugSnapshot
    ) -> String {
        var value = phaseText(snapshot.phase)
        if let fallback = snapshot.metrics.fallbackReason {
            value += ", fallback \(fallback.rawValue)"
        }
        return value
    }
}

public extension View {
    @MainActor
    func motionTransitionDebugHUD(
        coordinator: MotionTransitionCoordinator
    ) -> some View {
        overlay(alignment: .topTrailing) {
            MotionTransitionDebugHUD(coordinator: coordinator)
                .padding(12)
                .allowsHitTesting(false)
        }
    }
}
