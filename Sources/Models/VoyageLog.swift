import Foundation
import CoreLocation

enum VoyageLogMode: String, Codable {
    case guidedNavigation
    case freeRide

    var title: String {
        switch self {
        case .guidedNavigation:
            return L10n.tr("目的地ナビ")
        case .freeRide:
            return L10n.tr("フリーライド")
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
    // `var … = nil` (not `let`) so these appear in the synthesized memberwise initializer as
    // defaulted parameters: existing call sites keep compiling, and ride finalization can populate
    // them. A `let` with a default value is excluded from the memberwise init entirely.
    var maxSustainedSpeed: Double? = nil
    var effectiveDistance: Double? = nil
    var validSampleRatio: Double? = nil
    var isRankingEligible: Bool? = nil
    var activityBreakdown: [String: Double]? = nil

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
            weatherSummary: L10n.format("%@ / %@ %.0fkm/h", L10n.localizedWeatherCondition("晴れ"), L10n.localizedWindCompass("NE"), 12.0),
            mode: .guidedNavigation
        ),
        VoyageLog(
            id: UUID(),
            startTime: Date().addingTimeInterval(-172800),
            endTime: Date().addingTimeInterval(-170400),
            routePoints: [],
            distance: 5.2,
            averageSpeed: 7.1,
            weatherSummary: L10n.format("%@ / %@ %.0fkm/h", L10n.localizedWeatherCondition("くもり"), L10n.localizedWindCompass("SW"), 8.0),
            mode: .freeRide
        )
    ]
}
