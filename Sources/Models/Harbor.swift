import Foundation
import CoreLocation
import MapKit
import Combine

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
            name: "三角西エリア 公園前",
            coordinate: CLLocationCoordinate2D(latitude: 32.60661111, longitude: 130.47005556),
            facilities: ["休憩所", "トイレ"],
            restrictions: ["歩行者優先区間あり"],
            distance: 4.2,
            etaMinutes: 12
        ),
        Harbor(
            name: "本渡運動公園",
            coordinate: CLLocationCoordinate2D(latitude: 32.45755556, longitude: 130.19819444),
            facilities: ["自販機", "ベンチ"],
            restrictions: ["一部急坂あり"],
            distance: 8.4,
            etaMinutes: 24
        ),
        Harbor(
            name: "牛深ハイヤ大橋 展望ポイント",
            coordinate: CLLocationCoordinate2D(latitude: 32.19313889, longitude: 130.02697222),
            facilities: ["眺望", "休憩所"],
            restrictions: ["強風時は注意"],
            distance: 14.6,
            etaMinutes: 38
        ),
        Harbor(
            name: "上天草市役所 前",
            coordinate: CLLocationCoordinate2D(latitude: 32.49388889, longitude: 130.29283333),
            facilities: ["休憩所", "展望デッキ"],
            restrictions: ["交差点が多い"],
            distance: 6.1,
            etaMinutes: 18
        ),
        Harbor(
            name: "松島総合運動公園",
            coordinate: CLLocationCoordinate2D(latitude: 32.48730556, longitude: 130.28808333),
            facilities: ["給水", "休憩所"],
            restrictions: ["夜間照明が少ない"],
            distance: 6.5,
            etaMinutes: 20
        ),
        Harbor(
            name: "姫戸 しおさい公園",
            coordinate: CLLocationCoordinate2D(latitude: 32.43730556, longitude: 130.41169444),
            facilities: ["休憩所", "展望デッキ"],
            restrictions: ["一部急坂あり"],
            distance: 9.8,
            etaMinutes: 28
        ),
        Harbor(
            name: "御所浦 白亜紀資料館 前",
            coordinate: CLLocationCoordinate2D(latitude: 32.29247222, longitude: 130.23572222),
            facilities: ["休憩所", "展望デッキ"],
            restrictions: ["押し歩き区間あり"],
            distance: 11.2,
            etaMinutes: 30
        ),
        Harbor(
            name: "下田温泉 足湯広場",
            coordinate: CLLocationCoordinate2D(latitude: 32.42288889, longitude: 130.00497222),
            facilities: ["展望", "ベンチ"],
            restrictions: ["交差点が多い"],
            distance: 13.4,
            etaMinutes: 36
        ),
        Harbor(
            name: "二江ぐるっと展望所",
            coordinate: CLLocationCoordinate2D(latitude: 32.54527778, longitude: 130.11797222),
            facilities: ["展望", "ベンチ"],
            restrictions: ["坂道区間あり"],
            distance: 10.6,
            etaMinutes: 32
        )
    ]
}

extension Harbor {
    init(mapItem: MKMapItem, from origin: CLLocationCoordinate2D) {
        let coordinate = mapItem.placemark.coordinate
        let distanceMeters = coordinate.distance(to: origin)
        let distanceKm = distanceMeters / 1000.0
        let eta = max(Int(distanceMeters / (18.0 / 3.6) / 60), 5)
        self.init(
            name: mapItem.name ?? "未命名のスポット",
            coordinate: coordinate,
            facilities: ["スポット"] ,
            restrictions: [],
            distance: distanceKm,
            etaMinutes: eta
        )
    }
}

struct FavoriteDestination: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    var lastUsedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D, lastUsedAt: Date = .now) {
        self.id = FavoriteDestination.makeID(name: name, coordinate: coordinate)
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.lastUsedAt = lastUsedAt
    }

    private static func makeID(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let lat = (coordinate.latitude * 10_000).rounded() / 10_000
        let lon = (coordinate.longitude * 10_000).rounded() / 10_000
        return "\(normalizedName)_\(lat)_\(lon)"
    }
}

@MainActor
final class FavoriteDestinationStore: ObservableObject {
    static let shared = FavoriteDestinationStore()

    @Published private(set) var favorites: [FavoriteDestination] = []
    private let userDefaults: UserDefaults
    private let key = "favorite.destinations.v1"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func isFavorite(_ harbor: Harbor) -> Bool {
        let candidate = FavoriteDestination(name: harbor.name, coordinate: harbor.coordinate)
        return favorites.contains(where: { $0.id == candidate.id })
    }

    func toggle(_ harbor: Harbor) {
        if isFavorite(harbor) {
            remove(harbor)
        } else {
            addOrUpdate(harbor)
        }
    }

    func addOrUpdate(_ harbor: Harbor) {
        let candidate = FavoriteDestination(name: harbor.name, coordinate: harbor.coordinate)
        if let index = favorites.firstIndex(where: { $0.id == candidate.id }) {
            favorites[index].lastUsedAt = .now
        } else {
            favorites.append(candidate)
        }
        sortAndPersist()
    }

    func remove(_ harbor: Harbor) {
        let candidate = FavoriteDestination(name: harbor.name, coordinate: harbor.coordinate)
        favorites.removeAll { $0.id == candidate.id }
        sortAndPersist()
    }

    func markUsed(_ harbor: Harbor) {
        let candidate = FavoriteDestination(name: harbor.name, coordinate: harbor.coordinate)
        guard let index = favorites.firstIndex(where: { $0.id == candidate.id }) else { return }
        favorites[index].lastUsedAt = .now
        sortAndPersist()
    }

    func harborList(origin: CLLocationCoordinate2D) -> [Harbor] {
        favorites
            .map { favorite in
                let distanceMeters = favorite.coordinate.distance(to: origin)
                let distanceKm = distanceMeters / 1000.0
                let eta = max(Int(distanceMeters / (18.0 / 3.6) / 60), 5)
                return Harbor(
                    name: favorite.name,
                    coordinate: favorite.coordinate,
                    facilities: ["お気に入り"],
                    restrictions: [],
                    distance: distanceKm,
                    etaMinutes: eta
                )
            }
            .sorted { $0.distance < $1.distance }
    }

    private func sortAndPersist() {
        favorites.sort { $0.lastUsedAt > $1.lastUsedAt }
        persist()
    }

    private func load() {
        guard let data = userDefaults.data(forKey: key) else { return }
        do {
            favorites = try JSONDecoder().decode([FavoriteDestination].self, from: data)
            favorites.sort { $0.lastUsedAt > $1.lastUsedAt }
        } catch {
            favorites = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(favorites)
            userDefaults.set(data, forKey: key)
        } catch {
            #if DEBUG
            print("Failed to save favorite destinations:", error)
            #endif
        }
    }
}
