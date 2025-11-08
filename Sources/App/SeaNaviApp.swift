import SwiftUI

@main
struct SeaNaviApp: App {
    @StateObject private var locationService: LocationService
    @StateObject private var dashboardViewModel: NavigationDashboardViewModel

    init() {
        let service = LocationService()
        _locationService = StateObject(wrappedValue: service)
        _dashboardViewModel = StateObject(
            wrappedValue: NavigationDashboardViewModel(locationService: service)
        )
    }

    var body: some Scene {
        WindowGroup {
            NavigationDashboardView(viewModel: dashboardViewModel)
                .preferredColorScheme(.dark)
        }
    }
}
