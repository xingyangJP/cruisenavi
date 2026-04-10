import Foundation

enum AppLanguage: String {
    case japanese = "ja"
    case english = "en"

    static var current: AppLanguage {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "ja"
        return preferred.lowercased().hasPrefix("ja") ? .japanese : .english
    }

    var localeIdentifier: String {
        switch self {
        case .japanese:
            return "ja-JP"
        case .english:
            return "en-US"
        }
    }

    var speechVoiceIdentifier: String {
        localeIdentifier
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale(identifier: AppLanguage.current.localeIdentifier), arguments: args)
    }

    static func localizedWeatherCondition(_ condition: String) -> String {
        tr(canonicalWeatherKey(for: condition))
    }

    static func localizedWindCompass(_ compass: String) -> String {
        tr(canonicalWindCompassKey(for: compass))
    }

    static func localizedList(_ values: [String]) -> String {
        values.map { tr($0) }.joined(separator: ", ")
    }

    static func canonicalWeatherKey(for condition: String) -> String {
        let lowercased = condition.lowercased()
        if condition.contains("晴れ時々くもり") || lowercased.contains("partly cloudy") {
            return "晴れ時々くもり"
        }
        if condition.contains("晴れ") || lowercased.contains("clear") || lowercased.contains("sunny") {
            return "晴れ"
        }
        if condition.contains("くもり") || lowercased.contains("cloud") {
            return "くもり"
        }
        if condition.contains("雨") || lowercased.contains("rain") || lowercased.contains("drizzle") || lowercased.contains("storm") {
            return "雨"
        }
        if condition.contains("雪") || lowercased.contains("snow") || lowercased.contains("sleet") || lowercased.contains("blizzard") {
            return "雪"
        }
        if condition.contains("霧") || lowercased.contains("fog") || lowercased.contains("haze") || lowercased.contains("mist") || lowercased.contains("smoke") {
            return "霧"
        }
        return "不明"
    }

    static func canonicalWindCompassKey(for compass: String) -> String {
        switch compass.uppercased() {
        case "N":
            return "N"
        case "NE":
            return "NE"
        case "E":
            return "E"
        case "SE":
            return "SE"
        case "S":
            return "S"
        case "SW":
            return "SW"
        case "W":
            return "W"
        case "NW":
            return "NW"
        default:
            return compass
        }
    }
}

struct WeatherSnapshot: Identifiable {
    enum WarningLevel: String {
        case none
        case advisory
        case warning
    }

    let id = UUID()
    let timestamp: Date
    let condition: String
    let temperatureCelsius: Double
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
        temperatureCelsius: 24.0,
        windSpeed: 9.2,
        windDirection: 45,
        roadRisk: 0.6,
        precipitationStartMinutes: nil,
        warning: .none
    )
}
