import Foundation

struct WeatherSnapshot: Identifiable {
    enum WarningLevel: String {
        case none
        case advisory
        case warning
    }

    let id = UUID()
    let timestamp: Date
    let tideHeight: Double
    let tideState: String
    let windSpeed: Double
    let windDirection: Double
    let waveHeight: Double
    let warning: WarningLevel

    var windCompass: String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((windDirection + 22.5) / 45.0) & 7
        return directions[index]
    }

    static let sample = WeatherSnapshot(
        timestamp: Date(),
        tideHeight: 1.8,
        tideState: "Flood",
        windSpeed: 9.2,
        windDirection: 45,
        waveHeight: 0.6,
        warning: .none
    )
}
