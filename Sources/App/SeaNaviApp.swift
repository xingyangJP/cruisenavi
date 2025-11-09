import SwiftUI

@main
@MainActor
struct SeaNaviApp: App {
    @StateObject private var locationService: LocationService
    @StateObject private var dashboardViewModel: NavigationDashboardViewModel

    init() {
        let service = LocationService()
        _locationService = StateObject(wrappedValue: service)

        let weatherService: WeatherService
        if let configuration = WeatherConfigurationLoader.load() {
            weatherService = WeatherAPIClient(configuration: configuration)
        } else {
            weatherService = MockWeatherService()
        }

        let tideService: TideService = TideAPIClient()

        let viewModel = NavigationDashboardViewModel(
            locationService: service,
            weatherService: weatherService,
            tideService: tideService
        )
        _dashboardViewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView(viewModel: dashboardViewModel)
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootContainerView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @State private var showSplash = true

    var body: some View {
        ZStack {
            NavigationDashboardView(viewModel: viewModel)

            if showSplash {
                SplashView()
                    .transition(AnyTransition.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showSplash else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeInOut(duration: 0.6)) {
                showSplash = false
            }
        }
    }
}
