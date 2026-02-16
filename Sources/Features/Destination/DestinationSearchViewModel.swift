import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class DestinationSearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { scheduleSearch() }
    }
    @Published var results: [Harbor] = []
    @Published var isSearching = false
    @Published var selectedDestination: Harbor?

    static let nearbyRadiusKm: Double = 100.0

    private let locationService: LocationService
    private let spotProvider = NearbySpotProvider()
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: Int = 0

    init(locationService: LocationService) {
        self.locationService = locationService
        scheduleSearch()
    }

    private func scheduleSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = trimmed.isEmpty ? nil : trimmed

        searchGeneration += 1
        let generation = searchGeneration

        searchTask?.cancel()
        isSearching = true

        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self.updateResults(filter: filter, generation: generation)
        }
    }

    private func updateResults(filter: String?, generation: Int) async {
        let origin = locationService.currentCoordinateOrDefault()
        let nearby = await spotProvider.fetchNearby(
            origin: origin,
            radiusKm: Self.nearbyRadiusKm,
            query: filter
        )

        guard generation == searchGeneration else { return }

        if !nearby.isEmpty {
            results = nearby
            isSearching = false
            return
        }

        // Offline or no map search response: keep app usable with local fallback.
        results = Harbor.sample
            .map { harbor -> Harbor in
                let distanceMeters = harbor.coordinate.distance(to: origin)
                let distanceKm = distanceMeters / 1000.0
                let eta = max(Int(distanceMeters / (18.0 / 3.6) / 60), 5)
                return Harbor(
                    name: harbor.name,
                    coordinate: harbor.coordinate,
                    facilities: harbor.facilities,
                    restrictions: harbor.restrictions,
                    distance: distanceKm,
                    etaMinutes: eta
                )
            }
            .filter { $0.distance <= Self.nearbyRadiusKm }
            .filter { harbor in
                guard let filter else { return true }
                return harbor.name.localizedCaseInsensitiveContains(filter)
            }
            .sorted { $0.distance < $1.distance }

        isSearching = false
    }

    func select(_ harbor: Harbor) {
        selectedDestination = harbor
    }
}

final class NearbySpotProvider {
    private let defaultQueries = [
        "自転車", "サイクリング", "公園", "休憩", "展望", "カフェ"
    ]

    func fetchNearby(
        origin: CLLocationCoordinate2D,
        radiusKm: Double,
        query: String?
    ) async -> [Harbor] {
        var candidates: [String] = []
        if let query, !query.isEmpty {
            candidates.append(query)
        } else {
            candidates.append(contentsOf: defaultQueries)
        }

        let region = MKCoordinateRegion(
            center: origin,
            latitudinalMeters: radiusKm * 1000 * 2,
            longitudinalMeters: radiusKm * 1000 * 2
        )

        let fetched = await withTaskGroup(of: [Harbor].self) { group in
            for keyword in candidates {
                group.addTask {
                    if Task.isCancelled { return [] }
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = keyword
                    request.region = region
                    request.resultTypes = [.pointOfInterest, .address]

                    do {
                        let response = try await MKLocalSearch(request: request).start()
                        return response.mapItems
                            .map { Harbor(mapItem: $0, from: origin) }
                            .filter { $0.distance <= radiusKm }
                    } catch {
                        return []
                    }
                }
            }

            var all: [Harbor] = []
            for await spots in group {
                all.append(contentsOf: spots)
            }
            return all
        }

        var indexed: [String: Harbor] = [:]
        for harbor in fetched {
            let key = dedupeKey(for: harbor)
            if indexed[key] == nil || harbor.distance < indexed[key]!.distance {
                indexed[key] = harbor
            }
        }

        return indexed.values
            .sorted { $0.distance < $1.distance }
            .prefix(60)
            .map { $0 }
    }

    private func dedupeKey(for harbor: Harbor) -> String {
        let lat = (harbor.coordinate.latitude * 10_000).rounded() / 10_000
        let lon = (harbor.coordinate.longitude * 10_000).rounded() / 10_000
        return "\(harbor.name.lowercased())_\(lat)_\(lon)"
    }
}
