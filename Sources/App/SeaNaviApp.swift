import SwiftUI
import FirebaseCore
import FirebaseAnalytics

@main
@MainActor
struct SeaNaviApp: App {
    @StateObject private var locationService: LocationService
    @StateObject private var dashboardViewModel: NavigationDashboardViewModel

    init() {
        Self.configureFirebaseIfPossible()

        let enableMockFallback = ProcessInfo.processInfo.environment["ENABLE_MOCK_LOCATION"] == "1"
        let enableMockWeather = ProcessInfo.processInfo.environment["ENABLE_MOCK_WEATHER"] == "1"
        let service = LocationService(allowMockFallback: enableMockFallback)
        _locationService = StateObject(wrappedValue: service)

        var weatherProviders: [WeatherService] = [AppleWeatherKitService()]
        if let configuration = WeatherConfigurationLoader.load() {
            weatherProviders.append(WeatherAPIClient(configuration: configuration))
        }
        if enableMockWeather {
            weatherProviders.append(MockWeatherService())
        }
        let weatherService = ChainedWeatherService(providers: weatherProviders)

        let viewModel = NavigationDashboardViewModel(
            locationService: service,
            weatherService: weatherService,
            rideLogSyncService: HealthWorkoutSyncService()
        )
        _dashboardViewModel = StateObject(wrappedValue: viewModel)
    }

    private static func configureFirebaseIfPossible() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("GoogleService-Info.plist not found in app bundle. Firebase Analytics disabled.")
            #endif
            return
        }
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView(viewModel: dashboardViewModel)
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
