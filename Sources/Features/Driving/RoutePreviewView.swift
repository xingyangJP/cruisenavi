import SwiftUI
import MapKit

struct RoutePreviewView: View {
    let destination: Harbor
    let routeSummary: RouteSummary
    let rainAvoidanceAlert: RainAvoidanceAlert?
    var onApplyRainAvoidance: () -> Void
    var onCancel: () -> Void
    var onStart: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentRegion: MKCoordinateRegion?

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                if let coordinates = routeSummary.routeCoordinates, coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.aquaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                if let startCoordinate = routeSummary.routeCoordinates?.first {
                    Annotation("出発", coordinate: startCoordinate) {
                        Circle().fill(Color.white)
                            .frame(width: 14, height: 14)
                    }
                }
                Annotation(destination.name, coordinate: destination.coordinate) {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.citrusOrange)
                        .padding(6)
                        .background(Color.citrusCard, in: Circle())
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    MapZoomControl(onZoomIn: zoomIn, onZoomOut: zoomOut)
                }
                .padding(.horizontal, 16)
                .padding(.top, 80)

                Spacer()
            }

            VStack(spacing: 16) {
                if let rainAvoidanceAlert {
                    rainAvoidanceBanner(alert: rainAvoidanceAlert)
                }
                previewCard
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Label("キャンセル", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .foregroundStyle(Color.citrusPrimaryText)

                    Button(action: onStart) {
                        Label("スタート", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.citrusAmber, in: RoundedRectangle(cornerRadius: 18))
                            .foregroundColor(Color(red: 0.36, green: 0.26, blue: 0))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Preview should show the entire route from start to goal.
            let region = routeSummary.mapRegion
            currentRegion = region
            cameraPosition = .region(region)
        }
    }

    private func rainAvoidanceBanner(alert: RainAvoidanceAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cloud.rain")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.citrusOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.citrusPrimaryText)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("回避ルート提案") {
                onApplyRainAvoidance()
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.borderedProminent)
            .tint(Color.citrusAmber)
            .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.citrusBorder)
        )
        .padding(.horizontal, 20)
    }

    private func zoomIn() {
        guard var region = currentRegion else { return }
        region.span.latitudeDelta = max(region.span.latitudeDelta * 0.7, 0.001)
        region.span.longitudeDelta = max(region.span.longitudeDelta * 0.7, 0.001)
        currentRegion = region
        cameraPosition = .region(region)
    }

    private func zoomOut() {
        guard var region = currentRegion else { return }
        region.span.latitudeDelta = min(region.span.latitudeDelta * 1.4, 2.0)
        region.span.longitudeDelta = min(region.span.longitudeDelta * 1.4, 2.0)
        currentRegion = region
        cameraPosition = .region(region)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(destination.name)
                .font(.title2.bold())
                .foregroundStyle(Color.citrusPrimaryText)
            Text("スタート地点から目的地までの推奨ルート")
                .font(.subheadline)
                .foregroundStyle(Color.citrusSecondaryText)
            HStack {
                Label(String(format: "%.1f km", routeSummary.totalDistance), systemImage: "bicycle")
                Spacer()
                Label("ETA \(routeSummary.etaString)", systemImage: "clock")
            }
            .font(.footnote)
            .foregroundStyle(Color.citrusSecondaryText)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.citrusBorder)
        )
        .padding(.horizontal, 20)
    }
}

private struct MapZoomControl: View {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onZoomIn) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 12))

            Button(action: onZoomOut) {
                Image(systemName: "minus")
                    .font(.headline.weight(.bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(Color.citrusPrimaryText)
    }
}
