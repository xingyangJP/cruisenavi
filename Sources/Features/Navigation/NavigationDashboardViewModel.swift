import Foundation
import Combine
import CoreLocation

@MainActor
final class NavigationDashboardViewModel: ObservableObject {
    @Published var etaText: String = "14:35"
    @Published var distance: Double = 3.2
    @Published var speed: Double = 12.5
    @Published var heading: String = "045°"
    @Published var weatherSnapshot: WeatherSnapshot = .sample
    @Published var voyageLogs: [VoyageLog] = VoyageLog.sample
    @Published var harbors: [Harbor] = Harbor.sample
    @Published var warningMessage: String?

    let locationService: LocationService
    private let weatherService: WeatherService
    private var metricsTimer: AnyCancellable?
    private var weatherTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init(
        locationService: LocationService,
        weatherService: WeatherService = MockWeatherService()
    ) {
        self.locationService = locationService
        self.weatherService = weatherService

        bindLocation()
        startMockUpdates()
        startWeatherPolling()
        Task { await refreshWeather() }
    }

    private func startMockUpdates() {
        metricsTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                distance = max(distance - 0.1, 0)
                speed = 12.0 + Double.random(in: -0.5...0.5)
                warningMessage = distance < 0.3 ? "浅瀬注意: 300m" : nil
            }
    }

    private func startWeatherPolling() {
        weatherTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshWeather() }
            }
    }

    private func bindLocation() {
        locationService.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self else { return }
                speed = max(location.speed, 0)
                heading = Self.headingFormatter(location.course)
            }
            .store(in: &cancellables)
    }

    private func refreshWeather() async {
        let coordinate = locationService.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        do {
            let snapshot = try await weatherService.fetchSnapshot(
                for: CoordinateReference(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            await MainActor.run {
                weatherSnapshot = snapshot
            }
        } catch {
            await MainActor.run {
                warningMessage = "気象データ更新に失敗"
            }
        }
    }

    private static func headingFormatter(_ course: CLLocationDirection) -> String {
        guard course >= 0 else { return "—" }
        return String(format: "%03.0f°", course)
    }
}
