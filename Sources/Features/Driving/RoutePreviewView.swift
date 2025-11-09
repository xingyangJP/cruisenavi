import SwiftUI
import MapKit

struct RoutePreviewView: View {
    let destination: Harbor
    let routeSummary: RouteSummary
    var onCancel: () -> Void
    var onStart: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                if let coordinates = routeSummary.routeCoordinates, coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.aquaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                if let startCoordinate = routeSummary.routeCoordinates?.first {
                    Annotation("スタート", coordinate: startCoordinate) {
                        Circle().fill(Color.white)
                            .frame(width: 14, height: 14)
                    }
                }
                Annotation(destination.name, coordinate: destination.coordinate) {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.orange)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            VStack(spacing: 16) {
                previewCard
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Label("キャンセル", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
                    }
                    Button(action: onStart) {
                        Label("スタート", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.aquaTeal, in: RoundedRectangle(cornerRadius: 18))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraPosition = .region(routeSummary.mapRegion)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(destination.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("スタート地点から目的地までの海上ルート")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            HStack {
                Label(String(format: "%.1f nm", routeSummary.totalDistance), systemImage: "location.north")
                Spacer()
                Label("ETA \(routeSummary.etaString)", systemImage: "clock")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
    }
}
