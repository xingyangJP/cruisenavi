import CoreLocation

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let start = CLLocation(latitude: latitude, longitude: longitude)
        let end = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return start.distance(from: end)
    }
}
