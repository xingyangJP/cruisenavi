import Foundation
import CoreLocation
import HealthKit

protocol RideLogSyncService {
    func syncRideLog(_ log: VoyageLog) async -> RideLogSyncResult
}

enum RideLogSyncResult {
    case synced
    case skipped(String)
    case failed(String)
}

final class HealthWorkoutSyncService: RideLogSyncService {
    private let healthStore = HKHealthStore()
    private var didRequestAuthorization = false

    func syncRideLog(_ log: VoyageLog) async -> RideLogSyncResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .skipped("Health未対応")
        }

        do {
            try await requestAuthorizationIfNeeded()
            let workout = try await saveWorkout(for: log)
            if log.routePoints.count > 1 {
                try await saveRoute(for: log, workout: workout)
            }
            return .synced
        } catch {
            #if DEBUG
            print("HealthKit sync failed:", error)
            #endif
            return .failed(error.localizedDescription)
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        guard !didRequestAuthorization else { return }

        let workoutType = HKObjectType.workoutType()
        let routeType = HKSeriesType.workoutRoute()
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceCycling)!

        let share: Set<HKSampleType> = [workoutType, routeType, distanceType]
        let read: Set<HKObjectType> = [workoutType, routeType, distanceType]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: share, read: read) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit authorization denied"]))
                }
            }
        }

        didRequestAuthorization = true
    }

    private func saveWorkout(for log: VoyageLog) async throws -> HKWorkout {
        let distance = HKQuantity(unit: .meter(), doubleValue: max(log.distance * 1000.0, 0))
        let metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            HKMetadataKeyExternalUUID: log.id.uuidString
        ]

        let workout = HKWorkout(
            activityType: .cycling,
            start: log.startTime,
            end: log.endTime,
            duration: max(log.duration, 0),
            totalEnergyBurned: nil,
            totalDistance: distance,
            metadata: metadata
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(workout) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Workout save failed"]))
                }
            }
        }

        return workout
    }

    private func saveRoute(for log: VoyageLog, workout: HKWorkout) async throws {
        let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        let locations = interpolatedLocations(from: log)
        guard !locations.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.insertRouteData(locations) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Route insert failed"]))
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.finishRoute(with: workout, metadata: nil) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private func interpolatedLocations(from log: VoyageLog) -> [CLLocation] {
        let points = log.routePoints
        guard !points.isEmpty else { return [] }

        let totalDuration = max(log.endTime.timeIntervalSince(log.startTime), 1)
        let step = totalDuration / Double(max(points.count - 1, 1))

        return points.enumerated().map { index, coordinate in
            let timestamp = log.startTime.addingTimeInterval(step * Double(index))
            return CLLocation(
                coordinate: coordinate,
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 10,
                course: -1,
                speed: -1,
                timestamp: timestamp
            )
        }
    }
}

struct NoopRideLogSyncService: RideLogSyncService {
    func syncRideLog(_ log: VoyageLog) async -> RideLogSyncResult {
        .skipped("同期無効")
    }
}
