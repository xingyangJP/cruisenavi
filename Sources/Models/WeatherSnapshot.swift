import Foundation

struct WeatherSnapshot: Identifiable {
    enum WarningLevel: String {
        case none
        case advisory
        case warning
    }

    let id = UUID()
    let timestamp: Date
    let condition: String
    let windSpeed: Double
    let windDirection: Double
    let roadRisk: Double
    let precipitationStartMinutes: Int?
    let warning: WarningLevel

    var windCompass: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((windDirection + 22.5) / 45.0) & 7
        return directions[index]
    }

    static let sample = WeatherSnapshot(
        timestamp: Date(),
        condition: "晴れ",
        windSpeed: 9.2,
        windDirection: 45,
        roadRisk: 0.6,
        precipitationStartMinutes: nil,
        warning: .none
    )
}
