import SwiftUI
import MapKit

struct DrivingNavigationView: View {
    let destination: Harbor
    let routeSummary: RouteSummary
    let onExit: () -> Void
    let onChangeDestination: () -> Void
    @ObservedObject var locationService: LocationService

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var zoomSpan = MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
    @State private var lastKnownHeading: CLLocationDirection = 0

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                if let coordinates = routeSummary.routeCoordinates, coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.aquaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onAppear {
                locationService.requestAuthorization()
                locationService.startTracking()
                // When navigation starts, zoom to the start point first.
                focusCameraOnStart(animated: false)
                focusCameraOnUser(animated: false)
            }
            .onChange(of: locationService.currentLocation) { _, _ in
                focusCameraOnUser(animated: true)
            }
            .onChange(of: locationService.heading) { _, _ in
                focusCameraOnUser(animated: true)
            }

            VStack(spacing: 16) {
                DrivingInstructionCard(
                    route: routeSummary,
                    destination: destination,
                    currentSpeedKmh: max((locationService.currentLocation?.speed ?? 0) * 3.6, 0),
                    onChange: onChangeDestination
                )
                    .padding(.horizontal, 16)

                Spacer()

                HStack(spacing: 12) {
                    ControlButton(icon: "xmark.circle.fill", title: "終了", color: .citrusOrange, foreground: .white, action: onExit)
                    ControlButton(icon: "ellipsis.circle", title: "メニュー", color: .citrusCard, foreground: .citrusPrimaryText, action: onChangeDestination)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }

            Color.clear
                .overlay(alignment: .bottomTrailing) {
                    MapZoomControl(onZoomIn: zoomIn, onZoomOut: zoomOut)
                        .padding(.trailing, 16)
                        .padding(.bottom, 150)
                }
                .ignoresSafeArea()
                .zIndex(2)
        }
    }

    private func zoomIn() {
        zoomSpan.latitudeDelta = max(zoomSpan.latitudeDelta * 0.7, 0.001)
        zoomSpan.longitudeDelta = max(zoomSpan.longitudeDelta * 0.7, 0.001)
        focusCameraOnUser(animated: false)
    }

    private func zoomOut() {
        zoomSpan.latitudeDelta = min(zoomSpan.latitudeDelta * 1.4, 2.0)
        zoomSpan.longitudeDelta = min(zoomSpan.longitudeDelta * 1.4, 2.0)
        focusCameraOnUser(animated: false)
    }

    private func focusCameraOnStart(animated: Bool) {
        let start = routeSummary.routeCoordinates?.first ?? destination.coordinate
        setRegion(center: start, animated: animated)
    }

    private func focusCameraOnUser(animated: Bool) {
        let location = locationService.currentLocation
        let coordinate = location?.coordinate
            ?? routeSummary.routeCoordinates?.first
            ?? destination.coordinate
        let heading = currentHeading(from: location)
        setCamera(center: coordinate, heading: heading, animated: animated)
    }

    private func setRegion(center: CLLocationCoordinate2D, animated: Bool) {
        let region = MKCoordinateRegion(center: center, span: zoomSpan)
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    private func setCamera(center: CLLocationCoordinate2D, heading: CLLocationDirection, animated: Bool) {
        let distance = max(zoomSpan.latitudeDelta * 111_320.0 * 0.9, 80)
        let camera = MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: heading,
            pitch: 60
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)
        }
    }

    private func currentHeading(from location: CLLocation?) -> CLLocationDirection {
        if let heading = locationService.heading {
            let candidate = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
            if candidate >= 0 {
                let normalized = candidate.truncatingRemainder(dividingBy: 360)
                lastKnownHeading = normalized
                return normalized
            }
        }

        guard let location else { return lastKnownHeading }
        guard location.course >= 0 else { return lastKnownHeading }
        let normalized = location.course.truncatingRemainder(dividingBy: 360)
        lastKnownHeading = normalized
        return normalized
    }
}

private struct DrivingInstructionCard: View {
    let route: RouteSummary
    let destination: Harbor
    let currentSpeedKmh: Double
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(route.primaryInstruction)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.1f km", route.nextDistance))
                    .font(.title3.bold())
            }
            .foregroundStyle(Color.citrusPrimaryText)

            Text(route.secondaryInstruction)
                .font(.subheadline)
                .foregroundStyle(Color.citrusSecondaryText)

            HStack {
                Label("\(route.totalDistance, specifier: "%.1f") km", systemImage: "bicycle.circle")
                Spacer()
                Label(String(format: "%.1f km/h", currentSpeedKmh), systemImage: "speedometer")
                Spacer()
                Label("ETA \(route.etaString)", systemImage: "clock")
                Spacer()
                Button("目的地再設定", action: onChange)
                    .font(.footnote.bold())
            }
            .font(.footnote)
            .foregroundStyle(Color.citrusSecondaryText)
        }
        .padding(20)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.citrusBorder)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

private struct ControlButton: View {
    let icon: String
    let title: String
    let color: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(color, in: Capsule())
            .foregroundStyle(foreground)
        }
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

extension RouteSummary {
    static let sample = RouteSummary(
        totalDistance: 12.4,
        etaMinutes: 42,
        primaryInstruction: "800m 先、右へ",
        secondaryInstruction: "県道277号方面",
        nextDistance: 0.8,
        routeCoordinates: MockRouteProvider.tokyoBayRoute
    )
}
