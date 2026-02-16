import SwiftUI

struct NavigationDashboardView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @State private var showDestinationSheet = false
    @State private var showDrivingMode = false
    @State private var showRoutePreview = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.citrusCanvasStart,
                    Color.citrusCanvasEnd
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 24) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("ライドマップ")
                                .font(.title2.bold())
                                .foregroundStyle(Color.citrusPrimaryText)
                            SeaMapView(locationService: viewModel.locationService)
                                .frame(height: 260)
                            HStack {
                                Label("ルートポイント \(viewModel.locationService.routePoints.count)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                Spacer()
                                Label(viewModel.locationService.trackingMode.label, systemImage: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(viewModel.locationService.trackingMode.isActive ? .green : .orange)
                            }
                            .font(.footnote)
                            .foregroundStyle(Color.citrusSecondaryText)

                            Text(viewModel.locationService.trackingStatusMessage)
                                .font(.caption2)
                                .foregroundStyle(Color.citrusSecondaryText)
                        }
                    }

                    WeatherCardView(
                        snapshot: viewModel.weatherSnapshot
                    )

                    LogbookListView(
                        logs: viewModel.voyageLogs,
                        healthStatuses: viewModel.rideLogHealthStatuses
                    )

                    Button {
                        showDestinationSheet = true
                    } label: {
                        Label("目的地を設定してナビ開始", systemImage: "bicycle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.citrusAmber, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))

                    Text(appVersionLabel)
                        .font(.caption2)
                        .foregroundStyle(Color.citrusSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .safeAreaPadding(.top, 16)
                .safeAreaPadding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showDestinationSheet) {
            DestinationSearchView(locationService: viewModel.locationService) { harbor in
                viewModel.startNavigation(to: harbor)
                showDestinationSheet = false
                showRoutePreview = true
            }
        }
        .fullScreenCover(isPresented: $showRoutePreview) {
            if let destination = viewModel.activeDestination,
               let preview = viewModel.pendingRoute {
                RoutePreviewView(
                    destination: destination,
                    routeSummary: preview,
                    onCancel: {
                        viewModel.cancelRoutePreview()
                        showRoutePreview = false
                    },
                    onStart: {
                        viewModel.beginDrivingNavigation()
                        showRoutePreview = false
                        showDrivingMode = true
                    }
                )
            } else {
                RoutePreviewLoadingView()
            }
        }
        .fullScreenCover(isPresented: $showDrivingMode) {
            if let destination = viewModel.activeDestination,
               let route = viewModel.routeSummary {
                DrivingNavigationView(
                    destination: destination,
                    routeSummary: route,
                    onExit: {
                        viewModel.endNavigation()
                        showDrivingMode = false
                    },
                    onChangeDestination: {
                        showDrivingMode = false
                        showDestinationSheet = true
                    },
                    locationService: viewModel.locationService
                )
            } else {
                ProgressView().task {
                    showDrivingMode = false
                }
            }
        }
        .onChange(of: viewModel.pendingRoute != nil) { hasPreview in
            if hasPreview {
                showDestinationSheet = false
            }
        }
        .onChange(of: viewModel.routeSummary != nil) { hasRoute in
            showDrivingMode = hasRoute
        }
        .onAppear {
            viewModel.locationService.requestAuthorization()
            viewModel.locationService.startTracking()
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.39"
        return "ver\(version)"
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.citrusCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.citrusBorder)
                )

            content
                .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}
