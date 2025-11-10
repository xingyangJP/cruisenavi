import Foundation
import MapKit

struct RouteSummary {
    let totalDistance: Double
    let etaMinutes: Int
    let primaryInstruction: String
    let secondaryInstruction: String
    let nextDistance: Double
    let routeCoordinates: [CLLocationCoordinate2D]?

    var etaString: String {
        let hours = etaMinutes / 60
        let minutes = etaMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var mapRegion: MKCoordinateRegion {
        guard let coords = routeCoordinates, coords.count > 1 else {
            return MKCoordinateRegion(
                center: routeCoordinates?.first ?? CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        let minLat = coords.map { $0.latitude }.min() ?? 0
        let maxLat = coords.map { $0.latitude }.max() ?? 0
        let minLon = coords.map { $0.longitude }.min() ?? 0
        let maxLon = coords.map { $0.longitude }.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.05),
                                    longitudeDelta: max((maxLon - minLon) * 1.3, 0.05))
        return MKCoordinateRegion(center: center, span: span)
    }
}
