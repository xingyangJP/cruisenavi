import Foundation
import CoreLocation

final class NauticalRoutePlanner {
    private let candidateWaypoints: [RoutingWaypoint] = [
        RoutingWaypoint(coordinate: CLLocationCoordinate2D(latitude: 35.363, longitude: 139.65), depth: 20, name: "Yokohama Offshore"),
        RoutingWaypoint(coordinate: CLLocationCoordinate2D(latitude: 35.30, longitude: 139.70), depth: 35, name: "Tokyo Bay South"),
        RoutingWaypoint(coordinate: CLLocationCoordinate2D(latitude: 35.25, longitude: 139.74), depth: 45, name: "Kannon Reef"),
        RoutingWaypoint(coordinate: CLLocationCoordinate2D(latitude: 35.20, longitude: 139.80), depth: 30, name: "Uraga Channel"),
        RoutingWaypoint(coordinate: CLLocationCoordinate2D(latitude: 35.18, longitude: 139.82), depth: 25, name: "Kurihama Marker")
    ]

    func buildRoute(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        // simple fallback: start, intermediate, destination
        let bestWaypoint = candidateWaypoints.min { $0.coordinate.distance(to: destination) < $1.coordinate.distance(to: destination) }
        var route: [CLLocationCoordinate2D] = [start]
        if let waypoint = bestWaypoint {
            route.append(waypoint.coordinate)
        }
        route.append(destination)
        return smooth(route)
    }

    private func smooth(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3 else { return coordinates }
        var result: [CLLocationCoordinate2D] = []
        for idx in 0..<coordinates.count {
            let point = coordinates[idx]
            result.append(point)
            if idx < coordinates.count - 1 {
                let next = coordinates[idx + 1]
                let mid = CLLocationCoordinate2D(
                    latitude: (point.latitude + next.latitude) / 2,
                    longitude: (point.longitude + next.longitude) / 2
                )
                result.append(mid)
            }
        }
        return result
    }
}
