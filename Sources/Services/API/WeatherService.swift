import Foundation
import CoreLocation
import WeatherKit

enum APIError: Error {
    case invalidURL
    case transport(Error)
    case decoding
    case unknown
}

protocol WeatherService {
    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot
}

struct CoordinateReference {
    let latitude: Double
    let longitude: Double
}

struct ChainedWeatherService: WeatherService {
    let providers: [WeatherService]

    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        var lastError: Error = APIError.unknown
        for provider in providers {
            do {
                return try await provider.fetchSnapshot(for: coordinate)
            } catch {
                lastError = error
#if DEBUG
                print("Weather provider failed: \(type(of: provider)) error=\(error)")
#endif
            }
        }
        throw lastError
    }
}

final class AppleWeatherKitService: WeatherService {
    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
        let current = weather.currentWeather
        let windSpeed = current.wind.speed.converted(to: .metersPerSecond).value
        let windDirection = current.wind.direction.converted(to: .degrees).value
        let condition = weatherConditionText(current.condition)
#if DEBUG
        print("WeatherKit condition raw=\(current.condition) localized=\(condition)")
#endif
        let roadRisk = roadRiskScore(condition: condition, windSpeed: windSpeed)
        let precipitationStartMinutes = nextPrecipitationStartMinutes(from: weather)

        let warning: WeatherSnapshot.WarningLevel
        if windSpeed >= 20 || roadRisk >= 2.0 {
            warning = .warning
        } else if windSpeed >= 12 || roadRisk >= 1.2 {
            warning = .advisory
        } else {
            warning = .none
        }

        return WeatherSnapshot(
            timestamp: current.date,
            condition: condition,
            windSpeed: windSpeed,
            windDirection: windDirection,
            roadRisk: roadRisk,
            precipitationStartMinutes: precipitationStartMinutes,
            warning: warning
        )
    }

    private func roadRiskScore(condition: String, windSpeed: Double) -> Double {
        let rainLike = ["雨", "雷", "雪", "霧", "みぞれ"]
        let isWet = rainLike.contains { condition.contains($0) }
        let base = isWet ? 1.2 : 0.6
        return min(2.5, base + (windSpeed / 20.0))
    }

    private func weatherConditionText(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear:
            return "晴れ"
        case .partlyCloudy:
            return "晴れ時々くもり"
        case .cloudy, .mostlyCloudy:
            return "くもり"
        case .drizzle, .rain, .heavyRain, .isolatedThunderstorms, .thunderstorms, .strongStorms:
            return "雨"
        case .snow, .flurries, .sleet, .freezingRain, .wintryMix, .blizzard, .blowingSnow:
            return "雪"
        case .foggy, .haze, .smoky:
            return "霧"
        default:
            return "不明"
        }
    }

    private func nextPrecipitationStartMinutes(from weather: Weather) -> Int? {
        let now = Date()
        let rainConditions: Set<WeatherCondition> = [
            .drizzle, .rain, .heavyRain, .isolatedThunderstorms, .thunderstorms, .strongStorms
        ]

        if let nextRain = weather.hourlyForecast.forecast
            .first(where: { $0.date > now && rainConditions.contains($0.condition) }) {
            let minutes = Int(nextRain.date.timeIntervalSince(now) / 60.0)
            return max(minutes, 0)
        }
        return nil
    }
}

final class WeatherAPIClient: WeatherService {
    private let configuration: WeatherConfiguration
    private let session: URLSession

    init(configuration: WeatherConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        do {
            return try await fetchOneCallSnapshot(for: coordinate)
        } catch {
            return try await fetchCurrentWeatherSnapshot(for: coordinate)
        }
    }

    private func fetchOneCallSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "lon", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "appid", value: configuration.apiKey)
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.unknown
        }

        do {
            let payload = try JSONDecoder().decode(OneCallResponse.self, from: data)
            let current = payload.hourly.first ?? payload.current
            let precipitationStartMinutes = nextPrecipitationStartMinutes(from: payload.hourly, now: Date())

            let warning: WeatherSnapshot.WarningLevel
            if current.windSpeed >= 20 || (current.waveHeight ?? 0) >= 2 {
                warning = .warning
            } else if current.windSpeed >= 12 || (current.waveHeight ?? 0) >= 1.2 {
                warning = .advisory
            } else {
                warning = .none
            }

            return WeatherSnapshot(
                timestamp: Date(timeIntervalSince1970: current.timestamp),
                condition: current.condition ?? "不明",
                windSpeed: current.windSpeed,
                windDirection: current.windDirection,
                roadRisk: current.waveHeight ?? 0.6,
                precipitationStartMinutes: precipitationStartMinutes,
                warning: warning
            )
        } catch {
            throw APIError.decoding
        }
    }

    private func fetchCurrentWeatherSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        guard
            var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")
        else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "lon", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "appid", value: configuration.apiKey)
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw APIError.unknown
        }

        do {
            let payload = try JSONDecoder().decode(CurrentWeatherResponse.self, from: data)
            let current = payload.current

            let warning: WeatherSnapshot.WarningLevel
            if current.windSpeed >= 20 || payload.roadRisk >= 2 {
                warning = .warning
            } else if current.windSpeed >= 12 || payload.roadRisk >= 1.2 {
                warning = .advisory
            } else {
                warning = .none
            }

            return WeatherSnapshot(
                timestamp: Date(timeIntervalSince1970: current.timestamp),
                condition: payload.localizedCondition,
                windSpeed: current.windSpeed,
                windDirection: current.windDirection,
                roadRisk: payload.roadRisk,
                precipitationStartMinutes: nil,
                warning: warning
            )
        } catch {
            throw APIError.decoding
        }
    }
}

private extension WeatherAPIClient {
    func nextPrecipitationStartMinutes(from hourly: [OneCallResponse.Entry], now: Date) -> Int? {
        let nowUnix = now.timeIntervalSince1970
        for entry in hourly where entry.timestamp > nowUnix {
            if let pop = entry.pop, pop >= 0.4 {
                let minutes = Int((entry.timestamp - nowUnix) / 60.0)
                return max(minutes, 0)
            }
        }
        return nil
    }

    struct OneCallResponse: Decodable {
        struct WeatherElement: Decodable {
            let main: String?
            let description: String?
        }
        struct Entry: Decodable {
            let dt: TimeInterval
            let wind_speed: Double
            let wind_deg: Double
            let waves: Waves?
            let weather: [WeatherElement]?
            let pop: Double?

            struct Waves: Decodable {
                let wave_height: Double?
            }

            var timestamp: TimeInterval { dt }
            var windSpeed: Double { wind_speed }
            var windDirection: Double { wind_deg }
            var waveHeight: Double? { waves?.wave_height }
            var condition: String? { weather?.first?.description ?? weather?.first?.main }
        }

        let current: Entry
        let hourly: [Entry]
    }

    struct CurrentWeatherResponse: Decodable {
        struct Weather: Decodable {
            let main: String
            let description: String
        }

        struct Wind: Decodable {
            let speed: Double
            let deg: Double?
        }

        struct Entry {
            let timestamp: TimeInterval
            let windSpeed: Double
            let windDirection: Double
        }

        let dt: TimeInterval
        let weather: [Weather]
        let wind: Wind

        var current: Entry {
            Entry(
                timestamp: dt,
                windSpeed: wind.speed,
                windDirection: wind.deg ?? 0
            )
        }

        var condition: String {
            weather.first?.description ?? weather.first?.main ?? "不明"
        }

        var localizedCondition: String {
            let text = condition.lowercased()
            if text.contains("rain") || text.contains("drizzle") || text.contains("thunderstorm") {
                return "雨"
            }
            if text.contains("snow") || text.contains("sleet") {
                return "雪"
            }
            if text.contains("fog") || text.contains("mist") || text.contains("haze") {
                return "霧"
            }
            if text.contains("few clouds") || text.contains("scattered clouds") {
                return "晴れ時々くもり"
            }
            if text.contains("cloud") {
                return "くもり"
            }
            if text.contains("clear") {
                return "晴れ"
            }
            return "不明"
        }

        var roadRisk: Double {
            let text = condition.lowercased()
            let wetKeywords = ["rain", "drizzle", "thunderstorm", "snow", "mist", "fog"]
            let wet = wetKeywords.contains { text.contains($0) }
            let base = wet ? 1.2 : 0.6
            return min(2.5, base + (wind.speed / 20.0))
        }
    }
}

struct MockWeatherService: WeatherService {
    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: 100_000_000)
        return WeatherSnapshot.sample
    }
}
