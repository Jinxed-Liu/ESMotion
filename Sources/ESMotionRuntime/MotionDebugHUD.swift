import ESMotionCore
import SwiftUI

@MainActor
public struct MotionDebugHUD: View {
  private let engine: MotionEngine

  public init(engine: MotionEngine) {
    self.engine = engine
  }

  public var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
      let snapshot = engine.snapshot()
      VStack(alignment: .leading, spacing: 4) {
        Text("ESMotion 0.2")
          .font(.caption.bold())
        Text(snapshot.phase.debugLabel)
        Text(
          "progress \(snapshot.progress, format: .number.precision(.fractionLength(2)))"
        )
        Text(
          "p95 \(snapshot.metrics.frameStatistics.p95 * 1_000, format: .number.precision(.fractionLength(1))) ms"
        )
        Text(
          "snap \(snapshot.metrics.snapshotByteCount / 1_024 / 1_024) MB"
        )
        if let failure = snapshot.metrics.failure {
          Text("fallback \(failure.rawValue)")
            .foregroundStyle(.orange)
        }
      }
      .font(.caption2.monospaced())
      .foregroundStyle(.white)
      .padding(10)
      .background(.black.opacity(0.72), in: .rect(cornerRadius: 12))
      .accessibilityElement(children: .combine)
      .accessibilityLabel("ESMotion runtime")
      .accessibilityValue(
        accessibilityValue(for: snapshot)
      )
      .accessibilityIdentifier("motion-debug-hud")
    }
  }

  private func accessibilityValue(
    for snapshot: MotionEngineSnapshot
  ) -> String {
    let failure = snapshot.metrics.failure?.rawValue ?? "none"
    let firstFrameMilliseconds =
      snapshot.metrics.firstFrameLatency * 1_000
    return [
      "phase \(snapshot.phase.debugLabel)",
      "failure \(failure)",
      "reduced motion \(snapshot.metrics.usedReducedMotion)",
      "first frame \(String(format: "%.1f", firstFrameMilliseconds)) milliseconds",
    ].joined(separator: ", ")
  }
}

extension MotionTransitionPhase {
  fileprivate var debugLabel: String {
    switch self {
    case .idle:
      "idle"
    case .preparing(let direction):
      "prepare \(direction.rawValue)"
    case .animating(let direction):
      "animate \(direction.rawValue)"
    case .interactive(let direction):
      "interactive \(direction.rawValue)"
    case .settling(_, let target):
      "settle \(String(format: "%.1f", target))"
    case .presented:
      "presented"
    case .failed(let failure):
      "failed \(failure.rawValue)"
    }
  }
}
