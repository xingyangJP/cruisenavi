import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class DestinationSearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { scheduleSearch() }
    }
    @Published var results: [Harbor] = Harbor.sample
    @Published var isSearching = false
    @Published var selectedDestination: Harbor?

    private let locationService: LocationService
    private var searchTask: Task<Void, Never>?

    init(locationService: LocationService) {
        self.locationService = locationService
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = Harbor.sample
            return
        }
        searchTask = Task { await performSearch(for: trimmed) }
    }

    private func performSearch(for text: String) async {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.marina, .beach])

        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = locationService.currentCoordinateOrDefault()
            var mapped = response.mapItems.map { Harbor(mapItem: $0, from: origin) }
            if mapped.isEmpty {
                mapped = Harbor.sample
            } else {
                mapped.sort { $0.distance < $1.distance }
            }
            results = mapped
        } catch {
            results = Harbor.sample
        }
    }

    func select(_ harbor: Harbor) {
        selectedDestination = harbor
    }
}
