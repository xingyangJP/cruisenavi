import Foundation
import CoreLocation

struct RoutingWaypoint: Identifiable, Hashable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let depth: Double
    let name: String

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, depth: Double, name: String) {
        self.id = id
        self.coordinate = coordinate
        self.depth = depth
        self.name = name
    }

    static func == (lhs: RoutingWaypoint, rhs: RoutingWaypoint) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum NauticalError: Error {
    case noRouteFound
}
