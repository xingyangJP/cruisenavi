import Foundation
import CoreLocation

enum VoyageLogMode: String, Codable {
    case guidedNavigation
    case freeRide

    var title: String {
        switch self {
        case .guidedNavigation:
            return "目的地ナビ"
        case .freeRide:
            return "フリーライド"
        }
    }
}

struct VoyageLog: Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let routePoints: [CLLocationCoordinate2D]
    let distance: Double
    let averageSpeed: Double
    let weatherSummary: String
    let mode: VoyageLogMode

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
            weatherSummary: "晴れ / 北東 12km/h",
            mode: .guidedNavigation
        ),
        VoyageLog(
            id: UUID(),
            startTime: Date().addingTimeInterval(-172800),
            endTime: Date().addingTimeInterval(-170400),
            routePoints: [],
            distance: 5.2,
            averageSpeed: 7.1,
            weatherSummary: "くもり / 南西 8km/h",
            mode: .freeRide
        )
    ]
}
