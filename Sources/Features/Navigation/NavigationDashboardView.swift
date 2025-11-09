import SwiftUI

struct NavigationDashboardView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @State private var showDestinationSheet = false
    @State private var showDrivingMode = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.deepSeaBlue,
                    Color.deepSeaBlue.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 24) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("航行マップ")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            SeaMapView(locationService: viewModel.locationService)
                                .frame(height: 260)
                            HStack {
                                Label("ルートポイント \(viewModel.locationService.routePoints.count)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                Spacer()
                                Label("追跡中", systemImage: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(.green)
                            }
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    NavigationHUDView(
                        eta: viewModel.etaText,
                        distance: viewModel.distance,
                        speed: viewModel.speed,
                        heading: viewModel.heading,
                        warning: viewModel.warningMessage
                    )

                    TideWeatherCardView(
                        snapshot: viewModel.weatherSnapshot,
                        tideReport: viewModel.tideReport
                    )

                    LogbookListView(logs: viewModel.voyageLogs)

                    PortsListView(harbors: viewModel.harbors)

                    Button {
                        showDestinationSheet = true
                    } label: {
                        Label("目的地を設定してナビ開始", systemImage: "sailboat.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 20))
                }
                .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .safeAreaPadding(.top, 16)
                .safeAreaPadding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showDestinationSheet) {
            DestinationSearchView(
                viewModel: DestinationSearchViewModel()
            ) { harbor in
                viewModel.startNavigation(to: harbor)
                showDestinationSheet = false
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
                ProgressView().task {
                    showRoutePreview = false
                }
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
                    }
                )
            } else {
                ProgressView().task {
                    showDrivingMode = false
                }
            }
        }
        .onChange(of: viewModel.pendingRoute != nil) { hasPreview in
            showRoutePreview = hasPreview
        }
        .onChange(of: viewModel.routeSummary != nil) { hasRoute in
            showDrivingMode = hasRoute
        }
    }
}

struct NavigationHUDView: View {
    let eta: String
    let distance: Double
    let speed: Double
    let heading: String
    let warning: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 20) {
                Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        HUDMetric(label: "ETA", value: eta, icon: "clock")
                        HUDMetric(label: "距離", value: String(format: "%.1f nm", distance), icon: "arrow.triangle.turn.up.right.diamond")
                    }
                    GridRow {
                        HUDMetric(label: "速度", value: String(format: "%.1f kn", speed), icon: "speedometer")
                        HUDMetric(label: "方位", value: heading, icon: "safari")
                    }
                }

                if let warning {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("警告 \(warning)")
                }
            }
        }
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
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.15))
                )

            content
                .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}

private struct HUDMetric: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
