import Foundation
import CoreLocation
import MapKit

struct Harbor: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let facilities: [String]
    let restrictions: [String]
    let distance: Double
    let etaMinutes: Int

    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D, facilities: [String], restrictions: [String], distance: Double, etaMinutes: Int) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.facilities = facilities
        self.restrictions = restrictions
        self.distance = distance
        self.etaMinutes = etaMinutes
    }

    static let sample: [Harbor] = [
        Harbor(
            id: UUID(),
            name: "横浜ベイサイドマリーナ",
            coordinate: CLLocationCoordinate2D(latitude: 35.3738, longitude: 139.6420),
            facilities: ["Fuel Dock", "Power", "Water"],
            restrictions: ["No wake zone", "Speed 5kt"],
            distance: 12.3,
            etaMinutes: 32
        ),
        Harbor(
            id: UUID(),
            name: "神戸マリンピア",
            coordinate: CLLocationCoordinate2D(latitude: 34.6420, longitude: 135.2200),
            facilities: ["Fuel Dock", "Dry Dock"],
            restrictions: ["Speed 8kt"],
            distance: 5.2,
            etaMinutes: 19
        )
    ]
}

extension Harbor {
    init(mapItem: MKMapItem, from origin: CLLocationCoordinate2D) {
        let coordinate = mapItem.placemark.coordinate
        let distanceMeters = coordinate.distance(to: origin)
        let distanceNm = distanceMeters / 1852.0
        let eta = max(Int(distanceMeters / (12.0 * 0.514444) / 60), 5)
        self.init(
            name: mapItem.name ?? "未命名の港",
            coordinate: coordinate,
            facilities: mapItem.pointOfInterestCategory == .marina ? ["Fuel", "Dock"] : ["Coast"] ,
            restrictions: [],
            distance: distanceNm,
            etaMinutes: eta
        )
    }
}
