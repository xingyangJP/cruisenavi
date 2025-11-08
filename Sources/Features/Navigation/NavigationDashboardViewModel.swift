import Foundation
import Combine

@MainActor
final class NavigationDashboardViewModel: ObservableObject {
    @Published var etaText: String = "14:35"
    @Published var distance: Double = 3.2
    @Published var speed: Double = 12.5
    @Published var heading: String = "045°"
    @Published var weatherSnapshot: WeatherSnapshot = .sample
    @Published var voyageLogs: [VoyageLog] = VoyageLog.sample
    @Published var harbors: [Harbor] = Harbor.sample
    @Published var warningMessage: String?

    private var timer: AnyCancellable?

    init() {
        startMockUpdates()
    }

    private func startMockUpdates() {
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                distance = max(distance - 0.1, 0)
                speed = 12.0 + Double.random(in: -0.5...0.5)
                weatherSnapshot = WeatherSnapshot.sample
                warningMessage = distance < 0.3 ? "浅瀬注意: 300m" : nil
            }
    }
}
