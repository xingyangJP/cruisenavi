import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class NavigationDashboardViewModel: ObservableObject {
    @Published var etaText: String = "14:35"
    @Published var distance: Double = 3.2
    @Published var speed: Double = 12.5
    @Published var heading: String = "045°"
    @Published var weatherSnapshot: WeatherSnapshot = .sample
    @Published var tideReport: TideReport?
    @Published var voyageLogs: [VoyageLog] = VoyageLog.sample
    @Published var harbors: [Harbor] = Harbor.sample
    @Published var warningMessage: String?
    @Published var activeDestination: Harbor?
    @Published var routeSummary: RouteSummary?
    @Published var isGeneratingRoute = false

    let locationService: LocationService
    private let weatherService: WeatherService
    private let tideService: TideService
    private let routePlanner = NauticalRoutePlanner()
    private var metricsTimer: AnyCancellable?
    private var weatherTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init(
        locationService: LocationService,
        weatherService: WeatherService = MockWeatherService(),
        tideService: TideService = MockTideService()
    ) {
        self.locationService = locationService
        self.weatherService = weatherService
        self.tideService = tideService

        bindLocation()
        startMockUpdates()
        startWeatherPolling()
        Task { await refreshConditions() }
    }

    func startNavigation(to harbor: Harbor) {
        activeDestination = harbor
        routeSummary = nil
        isGeneratingRoute = true
        Task { await generateRoute(to: harbor) }
    }

    func endNavigation() {
        activeDestination = nil
        routeSummary = nil
        isGeneratingRoute = false
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
                Task { await self.refreshConditions() }
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

    private func refreshConditions() async {
        let coordinate = locationService.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        do {
            async let weatherTask = weatherService.fetchSnapshot(
                for: CoordinateReference(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            async let tideTask = tideService.fetchTide(
                for: CoordinateReference(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            let (snapshot, tide) = try await (weatherTask, tideTask)
            await MainActor.run {
                weatherSnapshot = snapshot
                tideReport = tide
                warningMessage = snapshot.warning == .warning ? "強風/高波警報" : nil
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

    private func generateRoute(to harbor: Harbor) async {
        let userCoordinate = locationService.currentCoordinateOrDefault()
        let start = nearestHarborCoordinate(to: userCoordinate)
        let marineRoute = routePlanner.buildRoute(from: start, to: harbor.coordinate)
        let distanceMeters = marineRouteDistance(marineRoute)
        let cruisingSpeedKnots = 14.0
        let etaMinutes = Int(distanceMeters / (cruisingSpeedKnots * 0.514444) / 60)

        await MainActor.run {
            routeSummary = RouteSummary(
                totalDistance: distanceMeters / 1852.0,
                etaMinutes: max(etaMinutes, harbor.etaMinutes),
                primaryInstruction: "航路に沿って進む",
                secondaryInstruction: harbor.name,
                nextDistance: distanceMeters / 1000.0,
                routeCoordinates: marineRoute
            )
            isGeneratingRoute = false
        }
    }

    private func nearestHarborCoordinate(to coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard let nearest = harbors.min(by: { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) }) else {
            return coordinate
        }
        return nearest.coordinate
    }
    private func marineRouteDistance(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var distance: Double = 0
        for index in 1..<coordinates.count {
            let prev = CLLocation(latitude: coordinates[index - 1].latitude, longitude: coordinates[index - 1].longitude)
            let next = CLLocation(latitude: coordinates[index].latitude, longitude: coordinates[index].longitude)
            distance += prev.distance(from: next)
        }
        return distance
    }
}
