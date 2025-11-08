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
    func fetchTide(for stationId: String) async throws -> TideReport
}

struct CoordinateReference {
    let latitude: Double
    let longitude: Double
}

struct WeatherAPIConfiguration: Sendable {
    let baseURL: URL
    let apiKey: String
}

final class WeatherAPIClient: WeatherService {
    private let configuration: WeatherAPIConfiguration
    private let session: URLSession

    init(configuration: WeatherAPIConfiguration, session: URLSession = .shared) {
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

        // Stub decode until real schema is defined.
        print("Received \(data.count) bytes from \(url)")
        return WeatherSnapshot(
            timestamp: Date(),
            tideHeight: 1.6,
            tideState: "Ebb",
            windSpeed: 8.1,
            windDirection: 60,
            waveHeight: 0.7,
            warning: .none
        )
    }
}

final class TideAPIClient: TideService {
    func fetchTide(for stationId: String) async throws -> TideReport {
        // Placeholder implementation
        try await Task.sleep(nanoseconds: 250_000_000)
        return TideReport(
            stationId: stationId,
            timestamp: Date(),
            height: 1.4,
            state: "Flood"
        )
    }
}

struct MockWeatherService: WeatherService {
    func fetchSnapshot(for coordinate: CoordinateReference) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: 100_000_000)
        return WeatherSnapshot.sample
    }
}

struct MockTideService: TideService {
    func fetchTide(for stationId: String) async throws -> TideReport {
        try await Task.sleep(nanoseconds: 100_000_000)
        return TideReport(
            stationId: stationId,
            timestamp: Date(),
            height: 1.7,
            state: "Slack"
        )
    }
}
