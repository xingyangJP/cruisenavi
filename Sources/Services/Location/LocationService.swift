import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var routePoints: [CLLocationCoordinate2D] = []

    private let locationManager = CLLocationManager()
    private var playbackTimer: AnyCancellable?
    private var playbackIndex: Int = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.headingFilter = 3
    }

    func requestAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startAuthorizedUpdates()
        default:
            break
        }
    }

    func startTracking() {
        guard CLLocationManager.locationServicesEnabled() else {
            startMockPlayback()
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startAuthorizedUpdates()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            startMockPlayback()
        @unknown default:
            startMockPlayback()
        }
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        playbackTimer?.cancel()
    }

    func currentCoordinateOrDefault() -> CLLocationCoordinate2D {
        if let coordinate = currentLocation?.coordinate {
            return coordinate
        }
        if let last = routePoints.last {
            return last
        }
        return CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    }

    private func startAuthorizedUpdates() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    private func startMockPlayback() {
        let mockPoints = MockRouteProvider.tokyoBayRoute
        playbackTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard !mockPoints.isEmpty else { return }

                let point = mockPoints[playbackIndex % mockPoints.count]
                playbackIndex += 1

                routePoints.append(point)
                currentLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        routePoints.append(location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorizedUpdates()
        case .denied, .restricted:
            stopTracking()
            startMockPlayback()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

enum MockRouteProvider {
    static let tokyoBayRoute: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6225, longitude: 139.7900),
        CLLocationCoordinate2D(latitude: 35.6150, longitude: 139.8000),
        CLLocationCoordinate2D(latitude: 35.6070, longitude: 139.8200),
        CLLocationCoordinate2D(latitude: 35.6001, longitude: 139.8450),
        CLLocationCoordinate2D(latitude: 35.5930, longitude: 139.8700)
    ]
}
