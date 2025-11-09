import Foundation
import CoreLocation

struct Harbor: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let facilities: [String]
    let restrictions: [String]
    let distance: Double
    let etaMinutes: Int

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
