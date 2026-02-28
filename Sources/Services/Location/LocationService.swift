import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    enum TrackingMode {
        case gps
        case mockPlayback
        case unavailable

        var label: String {
            switch self {
            case .gps:
                return "実GPS"
            case .mockPlayback:
                return "フォールバック"
            case .unavailable:
                return "位置情報なし"
            }
        }

        var isActive: Bool {
            switch self {
            case .gps, .mockPlayback:
                return true
            case .unavailable:
                return false
            }
        }
    }

    @Published var currentLocation: CLLocation?
    @Published var heading: CLHeading?
    @Published var routePoints: [CLLocationCoordinate2D] = []
    @Published var currentSpeedKmh: Double = 0
    @Published var trackingMode: TrackingMode = .unavailable
    @Published var trackingStatusMessage: String = "位置情報の取得を待機中"

    private let locationManager = CLLocationManager()
    private var playbackTimer: AnyCancellable?
    private var playbackIndex: Int = 0
    private let allowMockFallback: Bool
    private var lastSpeedSampleLocation: CLLocation?

    init(allowMockFallback: Bool = false) {
        self.allowMockFallback = allowMockFallback
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
        case .denied, .restricted:
            handleUnavailable(reason: "位置情報の許可が必要です")
        @unknown default:
            handleUnavailable(reason: "位置情報状態を判定できません")
        }
    }

    func startTracking() {
        guard CLLocationManager.locationServicesEnabled() else {
            handleNoLocationService(reason: "端末の位置情報サービスが無効です")
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startAuthorizedUpdates()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            trackingMode = .unavailable
            trackingStatusMessage = "位置情報の許可待ち"
        case .denied, .restricted:
            handleNoLocationService(reason: "位置情報の許可がありません")
        @unknown default:
            handleNoLocationService(reason: "位置情報状態を判定できません")
        }
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        playbackTimer?.cancel()
        playbackTimer = nil
    }

    func currentCoordinateOrDefault() -> CLLocationCoordinate2D {
        if let coordinate = currentLocation?.coordinate {
            return coordinate
        }
        if let managerCoordinate = locationManager.location?.coordinate {
            return managerCoordinate
        }
        if let last = routePoints.last {
            return last
        }
        return CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    }

    private func startAuthorizedUpdates() {
        playbackTimer?.cancel()
        playbackTimer = nil
        lastSpeedSampleLocation = nil
        currentSpeedKmh = 0
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        locationManager.requestLocation()
        trackingMode = .gps
        trackingStatusMessage = "GPSアクティブ"
    }

    private func handleNoLocationService(reason: String) {
        if allowMockFallback {
            startMockPlayback()
        } else {
            handleUnavailable(reason: reason)
        }
    }

    private func handleUnavailable(reason: String) {
        stopTracking()
        trackingMode = .unavailable
        trackingStatusMessage = reason
        currentSpeedKmh = 0
        lastSpeedSampleLocation = nil
    }

    private func startMockPlayback() {
        stopTracking()
        trackingMode = .mockPlayback
        trackingStatusMessage = "モック位置で追跡中"

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
                currentSpeedKmh = 0
            }
    }

    private func normalizeSpeedKmh(from location: CLLocation) -> Double {
        let result = SpeedNormalizer.normalizedSpeed(
            currentSpeedKmh: currentSpeedKmh,
            location: location,
            lastSampleLocation: lastSpeedSampleLocation,
            now: Date()
        )

        #if DEBUG
        if let fallbackKmh = result.fallbackKmhUsed {
            print(String(format: "Speed fallback applied: %.2f km/h", fallbackKmh))
        }
        #endif

        return result.speedKmh
    }
}

struct SpeedNormalizationResult {
    let speedKmh: Double
    let fallbackKmhUsed: Double?
}

enum SpeedNormalizer {
    static func normalizedSpeed(
        currentSpeedKmh: Double,
        location: CLLocation,
        lastSampleLocation: CLLocation?,
        now: Date,
        gpsFreshThreshold: TimeInterval = 5,
        stopThresholdKmh: Double = 0.8,
        alpha: Double = 0.35
    ) -> SpeedNormalizationResult {
        let gpsSpeedKmh: Double? = {
            guard location.speed >= 0 else { return nil }
            guard abs(location.timestamp.timeIntervalSince(now)) <= gpsFreshThreshold else { return nil }
            return location.speed * 3.6
        }()

        let fallbackKmh: Double? = {
            guard let last = lastSampleLocation else { return nil }
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0.5 && dt < 15 else { return nil }
            let meters = location.distance(from: last)
            return (meters / dt) * 3.6
        }()

        var raw = gpsSpeedKmh ?? fallbackKmh ?? 0
        if raw < stopThresholdKmh {
            raw = 0
        }

        let smoothed = (alpha * raw) + ((1 - alpha) * currentSpeedKmh)
        let speed = smoothed < stopThresholdKmh ? 0 : smoothed
        let fallbackUsed = gpsSpeedKmh == nil ? fallbackKmh : nil
        return SpeedNormalizationResult(speedKmh: speed, fallbackKmhUsed: fallbackUsed)
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentSpeedKmh = normalizeSpeedKmh(from: location)
        currentLocation = location
        routePoints.append(location.coordinate)
        lastSpeedSampleLocation = location
        trackingMode = .gps
        trackingStatusMessage = "GPSアクティブ"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location manager error:", error)
        #endif
        if trackingMode == .gps {
            trackingStatusMessage = "GPS更新エラー"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorizedUpdates()
        case .denied, .restricted:
            handleNoLocationService(reason: "位置情報の許可がありません")
        case .notDetermined:
            trackingMode = .unavailable
            trackingStatusMessage = "位置情報の許可待ち"
        @unknown default:
            trackingMode = .unavailable
            trackingStatusMessage = "位置情報状態を判定できません"
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
