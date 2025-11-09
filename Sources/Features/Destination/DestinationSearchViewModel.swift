import Foundation
import Combine
import CoreLocation

@MainActor
final class DestinationSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [Harbor] = Harbor.sample
    @Published var selectedDestination: Harbor?

    private var cancellables = Set<AnyCancellable>()

    init() {
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                guard !text.isEmpty else {
                    results = Harbor.sample
                    return
                }
                results = Harbor.sample.filter { $0.name.localizedCaseInsensitiveContains(text) }
            }
            .store(in: &cancellables)
    }

    func select(_ harbor: Harbor) {
        selectedDestination = harbor
    }
}
