import Foundation
import CoreMotion

/// Thin, impure wrapper over `CMMotionActivityManager`. Queries activity history for a finished
/// ride window and reconstructs `[RideActivitySegment]`. Runtime-guarded on
/// `isActivityAvailable()` so builds/tests stay device-independent.
@MainActor
final class MotionActivityRecorder {
    private let manager = CMMotionActivityManager()
    private let queue = OperationQueue()

    /// Safety net so a `queryActivityStarting` callback that never fires (e.g. an unanswered
    /// Motion & Fitness permission prompt, or an OS edge case) cannot hang ride finalization.
    private let queryTimeout: TimeInterval

    static var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    init(queryTimeout: TimeInterval = 5.0) {
        self.queryTimeout = queryTimeout
    }

    /// Returns activity segments spanning [start, end], or [] if unavailable/denied/empty/error.
    func segments(from start: Date, to end: Date) async -> [RideActivitySegment] {
        guard Self.isAvailable else { return [] }
        guard end > start else { return [] }

        let activities: [CMMotionActivity] = await withCheckedContinuation { continuation in
            // The completion runs on `queue` (background) while the timeout fires on a global
            // queue, so guard against a double-resume (which would crash a checked continuation).
            let resumer = ContinuationResumer(continuation)
            manager.queryActivityStarting(from: start, to: end, to: queue) { activities, _ in
                resumer.resume(with: activities ?? [])
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + queryTimeout) {
                resumer.resume(with: [])
            }
        }

        guard !activities.isEmpty else { return [] }

        // CMMotionActivity delivers state *changes*; each spans from its startDate to the next
        // activity's startDate (last spans to `end`). Clamp the first up to `start`.
        let sorted = activities.sorted { $0.startDate < $1.startDate }
        var segments: [RideActivitySegment] = []
        for (index, activity) in sorted.enumerated() {
            let rawStart = index == 0 ? max(activity.startDate, start) : activity.startDate
            let segmentStart = max(rawStart, start)
            let segmentEnd = index + 1 < sorted.count ? sorted[index + 1].startDate : end
            guard segmentEnd > segmentStart else { continue }
            segments.append(RideActivitySegment(
                startTime: segmentStart,
                endTime: min(segmentEnd, end),
                kind: Self.kind(from: activity),
                confidence: activity.confidence.rawValue
            ))
        }
        return segments
    }

    /// Thread-safe one-shot wrapper around a `CheckedContinuation`. Whichever of the CoreMotion
    /// callback or the timeout arrives first resumes it; the other is a no-op.
    private final class ContinuationResumer: @unchecked Sendable {
        private var continuation: CheckedContinuation<[CMMotionActivity], Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<[CMMotionActivity], Never>) {
            self.continuation = continuation
        }

        func resume(with value: [CMMotionActivity]) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    private static func kind(from activity: CMMotionActivity) -> RideActivityKind {
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }
}
