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
        if let first = routeCoordinates?.first {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }
}
