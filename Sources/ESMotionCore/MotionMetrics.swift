import Foundation

public struct MotionFrameStatistics: Equatable, Sendable {
  public let frameCount: Int
  public let p50: TimeInterval
  public let p95: TimeInterval
  public let p99: TimeInterval
  public let longest: TimeInterval
  public let hitchCount: Int

  public init(
    frameCount: Int,
    p50: TimeInterval,
    p95: TimeInterval,
    p99: TimeInterval,
    longest: TimeInterval,
    hitchCount: Int
  ) {
    self.frameCount = max(frameCount, 0)
    self.p50 = max(p50, 0)
    self.p95 = max(p95, 0)
    self.p99 = max(p99, 0)
    self.longest = max(longest, 0)
    self.hitchCount = max(hitchCount, 0)
  }

  public static let empty = MotionFrameStatistics(
    frameCount: 0,
    p50: 0,
    p95: 0,
    p99: 0,
    longest: 0,
    hitchCount: 0
  )
}

public struct MotionFrameAccumulator: Sendable {
  private let capacity: Int
  private var intervals: [TimeInterval]

  public init(capacity: Int = 240) {
    self.capacity = max(capacity, 1)
    intervals = []
    intervals.reserveCapacity(max(capacity, 1))
  }

  public mutating func record(_ interval: TimeInterval) {
    guard interval > 0 else { return }
    intervals.append(interval)
    if intervals.count > capacity {
      intervals.removeFirst(intervals.count - capacity)
    }
  }

  public mutating func reset() {
    intervals.removeAll(keepingCapacity: true)
  }

  public func snapshot(
    hitchThreshold: TimeInterval = 1 / 30
  ) -> MotionFrameStatistics {
    guard !intervals.isEmpty else { return .empty }
    let sorted = intervals.sorted()
    let hitchCount = intervals.reduce(into: 0) { count, interval in
      if interval > hitchThreshold {
        count += 1
      }
    }
    return MotionFrameStatistics(
      frameCount: intervals.count,
      p50: percentile(0.50, in: sorted),
      p95: percentile(0.95, in: sorted),
      p99: percentile(0.99, in: sorted),
      longest: sorted.last ?? 0,
      hitchCount: hitchCount
    )
  }

  private func percentile(
    _ percentile: Double,
    in sorted: [TimeInterval]
  ) -> TimeInterval {
    let index = Int(
      (Double(sorted.count - 1) * min(max(percentile, 0), 1)).rounded()
    )
    return sorted[index]
  }
}
