import Foundation
import CoreLocation

final class NauticalRoutePlanner {
    private struct LandBox {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            coordinate.latitude >= minLat && coordinate.latitude <= maxLat &&
            coordinate.longitude >= minLon && coordinate.longitude <= maxLon
        }
    }

    private let landBoxes: [LandBox] = [
        LandBox(minLat: 35.30, maxLat: 35.45, minLon: 139.60, maxLon: 139.70), // Yokohama city
        LandBox(minLat: 35.20, maxLat: 35.32, minLon: 139.70, maxLon: 139.85), // Bay coastal area
        LandBox(minLat: 35.15, maxLat: 35.25, minLon: 139.80, maxLon: 139.90)
    ]

    private let coastalNodes: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.35, longitude: 139.72),
        CLLocationCoordinate2D(latitude: 35.29, longitude: 139.76),
        CLLocationCoordinate2D(latitude: 35.24, longitude: 139.78),
        CLLocationCoordinate2D(latitude: 35.18, longitude: 139.82),
        CLLocationCoordinate2D(latitude: 35.14, longitude: 139.85)
    ]

    func buildRoute(from start: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        var route: [CLLocationCoordinate2D] = [start]
        var current = start

        if crossesLand(from: current, to: destination) {
            if let detour = coastalNode(near: destination) {
                route.append(detour)
                current = detour
            }
        }

        route.append(destination)
        return smooth(route)
    }

    private func crossesLand(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Bool {
        for box in landBoxes {
            if box.contains(start) || box.contains(end) { return true }
            let minLat = min(start.latitude, end.latitude)
            let maxLat = max(start.latitude, end.latitude)
            let minLon = min(start.longitude, end.longitude)
            let maxLon = max(start.longitude, end.longitude)
            if maxLat >= box.minLat && minLat <= box.maxLat && maxLon >= box.minLon && minLon <= box.maxLon {
                return true
            }
        }
        return false
    }

    private func coastalNode(near destination: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        coastalNodes.min { $0.distance(to: destination) < $1.distance(to: destination) }
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
