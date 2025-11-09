import SwiftUI
import MapKit

struct SeaMapView: View {
    @ObservedObject var locationService: LocationService
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6225, longitude: 139.79),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        Map(position: $cameraPosition) {
            if let coordinate = locationService.currentLocation?.coordinate {
                Annotation("現在地", coordinate: coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.3))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sailboat.fill")
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("現在位置")
                }
            }

            let route = locationService.routePoints
            if route.count > 1 {
                MapPolyline(coordinates: route)
                    .stroke(.teal, lineWidth: 3)
                MapPolygon(coordinates: MockRestrictedArea.osakaBay)
                    .foregroundStyle(.red.opacity(0.15))
                    .stroke(.red.opacity(0.4), lineWidth: 1)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onChange(of: locationService.currentLocation) { newValue in
            guard let coordinate = newValue?.coordinate else { return }
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
        .onAppear {
            locationService.requestAuthorization()
            locationService.startTracking()
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(radius: 20, y: 10)
    }
}

enum MockRestrictedArea {
    static let osakaBay: [CLLocationCoordinate2D] = [
        .init(latitude: 34.65, longitude: 135.1),
        .init(latitude: 34.68, longitude: 135.2),
        .init(latitude: 34.62, longitude: 135.25),
        .init(latitude: 34.6, longitude: 135.18)
    ]
}
