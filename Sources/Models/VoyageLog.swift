import Foundation
import CoreLocation

struct VoyageLog: Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let routePoints: [CLLocationCoordinate2D]
    let distance: Double
    let averageSpeed: Double
    let weatherSummary: String

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    static let sample: [VoyageLog] = [
        VoyageLog(
            id: UUID(),
            startTime: Date().addingTimeInterval(-7200),
            endTime: Date().addingTimeInterval(-1800),
            routePoints: [],
            distance: 18.4,
            averageSpeed: 12.3,
            weatherSummary: "晴れ / 北東 12km/h"
        ),
        VoyageLog(
            id: UUID(),
            startTime: Date().addingTimeInterval(-172800),
            endTime: Date().addingTimeInterval(-170400),
            routePoints: [],
            distance: 5.2,
            averageSpeed: 7.1,
            weatherSummary: "くもり / 南西 8km/h"
        )
    ]
}
