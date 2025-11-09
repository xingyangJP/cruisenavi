import Foundation

enum APIError: Error {
    case invalidURL
    case transport(Error)
    case decoding
    case unknown
}

protocol WeatherService {
    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot
}

protocol TideService {
    func fetchTide(for coordinate: CoordinateReference) async throws -> TideReport
}

struct CoordinateReference {
    let latitude: Double
    let longitude: Double
}

final class WeatherAPIClient: WeatherService {
    private let configuration: WeatherConfiguration
    private let session: URLSession

    init(configuration: WeatherConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
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
            let reference = payload.hourly.first ?? payload.current
            let next = payload.hourly.dropFirst().first ?? reference

            let tideHeightMeters = reference.derivedSeaLevel
            let nextHeight = next.derivedSeaLevel
            let tideState: String
            if nextHeight > tideHeightMeters + 0.05 {
                tideState = "Rising"
            } else if nextHeight + 0.05 < tideHeightMeters {
                tideState = "Falling"
            } else {
                tideState = "Slack"
            }

            let warning: WeatherSnapshot.WarningLevel
            if reference.windSpeed >= 20 || (reference.waveHeight ?? 0) >= 2 {
                warning = .warning
            } else if reference.windSpeed >= 12 || (reference.waveHeight ?? 0) >= 1.2 {
                warning = .advisory
            } else {
                warning = .none
            }

            return WeatherSnapshot(
                timestamp: Date(timeIntervalSince1970: reference.timestamp),
                tideHeight: tideHeightMeters,
                tideState: tideState,
                windSpeed: reference.windSpeed,
                windDirection: reference.windDirection,
                waveHeight: reference.waveHeight ?? 0.6,
                warning: warning
            )
        } catch {
            throw APIError.decoding
        }
    }
}

private extension WeatherAPIClient {
    struct OneCallResponse: Decodable {
        struct Entry: Decodable {
            let dt: TimeInterval
            let wind_speed: Double
            let wind_deg: Double
            let sea_level: Double?
            let pressure: Double?
            let waves: Waves?

            struct Waves: Decodable {
                let wave_height: Double?
            }

            var timestamp: TimeInterval { dt }
            var windSpeed: Double { wind_speed }
            var windDirection: Double { wind_deg }
            var waveHeight: Double? { waves?.wave_height }
            var derivedSeaLevel: Double {
                if let sea = sea_level {
                    return sea / 100.0
                } else if let pressure = pressure {
                    return pressure / 100.0
                } else {
                    return 0.0
                }
            }
        }

        let current: Entry
        let hourly: [Entry]
    }
}

final class TideAPIClient: TideService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(
        baseURL: URL = URL(string: "https://marine-api.open-meteo.com/v1/marine")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchTide(for coordinate: CoordinateReference) async throws -> TideReport {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "hourly", value: "tide_height"),
            URLQueryItem(name: "length", value: "2"),
            URLQueryItem(name: "timezone", value: "UTC")
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
            let payload = try decoder.decode(OpenMeteoTideResponse.self, from: data)
            guard
                let firstHeight = payload.hourly.tide_height?.first,
                let firstTimeString = payload.hourly.time.first,
                let timestamp = isoFormatter.date(from: firstTimeString) ?? ISO8601DateFormatter().date(from: firstTimeString)
            else {
                throw APIError.decoding
            }

            let nextHeight = payload.hourly.tide_height?.dropFirst().first ?? firstHeight
            let state: String
            if nextHeight > firstHeight + 0.05 {
                state = "Rising"
            } else if nextHeight + 0.05 < firstHeight {
                state = "Falling"
            } else {
                state = "Slack"
            }

            return TideReport(
                timestamp: timestamp,
                height: firstHeight,
                state: state,
                source: "Open-Meteo"
            )
        } catch {
            throw APIError.decoding
        }
    }

    private struct OpenMeteoTideResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let tide_height: [Double]?
        }

        let hourly: Hourly
    }
}

struct MockWeatherService: WeatherService {
    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: 100_000_000)
        return WeatherSnapshot.sample
    }
}

struct MockTideService: TideService {
    func fetchTide(for coordinate: CoordinateReference) async throws -> TideReport {
        try await Task.sleep(nanoseconds: 100_000_000)
        return TideReport(
            timestamp: Date(),
            height: 1.7,
            state: "Slack",
            source: "Mock"
        )
    }
}
