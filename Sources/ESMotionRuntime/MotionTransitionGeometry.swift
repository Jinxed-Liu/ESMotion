import CoreGraphics
import Foundation

struct MotionTransitionResolvedFrame: Equatable, Sendable {
    let containerFrame: CGRect
    let cornerRadius: CGFloat
    let sourceOpacity: Float
    let destinationOpacity: Float
}

enum MotionTransitionGeometry {
    static func resolve(
        sourceFrame: CGRect,
        destinationFrame: CGRect,
        sourceElements: [Never] = [],
        destinationElements: [Never] = [],
        spec: MotionTransitionSpec,
        progress rawProgress: Double,
        reducedMotion: Bool
    ) -> MotionTransitionResolvedFrame {
        let progress = min(max(rawProgress, 0), 1)
        let geometryProgress = reducedMotion ? 1 : progress
        return MotionTransitionResolvedFrame(
            containerFrame: interpolate(
                from: sourceFrame,
                to: destinationFrame,
                progress: geometryProgress
            ),
            cornerRadius: interpolate(
                from: spec.cornerRadius,
                to: 0,
                progress: geometryProgress
            ),
            sourceOpacity: Float(1 - progress),
            destinationOpacity: Float(progress)
        )
    }

    static func interpolate(
        from source: CGRect,
        to destination: CGRect,
        progress: Double
    ) -> CGRect {
        CGRect(
            x: interpolate(from: source.minX, to: destination.minX, progress: progress),
            y: interpolate(from: source.minY, to: destination.minY, progress: progress),
            width: interpolate(
                from: source.width,
                to: destination.width,
                progress: progress
            ),
            height: interpolate(
                from: source.height,
                to: destination.height,
                progress: progress
            )
        )
    }

    static func interpolate(
        from source: CGFloat,
        to destination: CGFloat,
        progress: Double
    ) -> CGFloat {
        source + (destination - source) * CGFloat(progress)
    }
}
