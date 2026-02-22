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
                VStack(spacing: 24) {
                    SeaMapView(locationService: viewModel.locationService)
                        .frame(maxWidth: .infinity)
                        .frame(height: 340)
                        .ignoresSafeArea(edges: .top)

                    LazyVStack(spacing: 24) {
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

                        WeatherCardView(
                            snapshot: viewModel.weatherSnapshot
                        )

                        LogbookListView(
                            logs: viewModel.voyageLogs,
                            healthStatuses: viewModel.rideLogHealthStatuses
                        )

                        VStack(spacing: 2) {
                            Text(appVersionLabel)
                                .font(.caption2)
                                .foregroundStyle(Color.citrusSecondaryText)
                            Text("XerographiX Inc.")
                                .font(.caption2)
                                .foregroundStyle(Color.citrusSecondaryText.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
                .safeAreaPadding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                Image("splash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 720, height: 192)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showDestinationSheet) {
            DestinationSearchView(locationService: viewModel.locationService) { harbor, routeMode in
                viewModel.startNavigation(to: harbor, mode: routeMode)
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
                    rainAvoidanceAlert: viewModel.rainAvoidanceAlert,
                    onApplyRainAvoidance: {
                        viewModel.applyRainAvoidanceReroute()
                    },
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
                    rainAvoidanceAlert: viewModel.rainAvoidanceAlert,
                    onExit: {
                        viewModel.endNavigation()
                        showDrivingMode = false
                    },
                    onChangeDestination: {
                        showDrivingMode = false
                        showDestinationSheet = true
                    },
                    onRerouteRequest: { location, routeCoordinates in
                        viewModel.requestRerouteIfOffRoute(
                            currentLocation: location,
                            referenceRoute: routeCoordinates
                        )
                    },
                    onApplyRainAvoidance: {
                        viewModel.applyRainAvoidanceReroute()
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.58"
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
