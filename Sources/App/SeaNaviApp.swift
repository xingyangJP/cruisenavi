import SwiftUI

@main
struct SeaNaviApp: App {
    @StateObject private var dashboardViewModel = NavigationDashboardViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationDashboardView(viewModel: dashboardViewModel)
                .preferredColorScheme(.dark)
        }
    }
}
