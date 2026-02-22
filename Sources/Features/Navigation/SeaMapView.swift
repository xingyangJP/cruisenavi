import SwiftUI
import MapKit

struct SeaMapView: View {
    @ObservedObject var locationService: LocationService
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        )
    )

    var body: some View {
        Map(position: $cameraPosition) {
            if let coordinate = locationService.currentLocation?.coordinate {
                Annotation("現在地", coordinate: coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.aquaTeal.opacity(0.25))
                            .frame(width: 32, height: 32)
                        Image(systemName: "bicycle")
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
        .mapStyle(.standard(elevation: .realistic))
        .onChange(of: locationService.currentLocation) { _, _ in
            cameraPosition = .userLocation(
                followsHeading: false,
                fallback: .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                    )
                )
            )
        }
        .onAppear {
            locationService.requestAuthorization()
            locationService.startTracking()
        }
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
