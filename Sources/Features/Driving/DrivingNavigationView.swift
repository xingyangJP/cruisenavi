import SwiftUI
import MapKit
import UIKit

struct DrivingNavigationView: View {
    let destination: Harbor
    let routeSummary: RouteSummary
    let rainAvoidanceAlert: RainAvoidanceAlert?
    let onExit: () -> Void
    let onChangeDestination: () -> Void
    let onRerouteRequest: (CLLocation, [CLLocationCoordinate2D]) -> Void
    let onApplyRainAvoidance: () -> Void
    @ObservedObject var locationService: LocationService

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var zoomSpan = MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
    @State private var lastKnownHeading: CLLocationDirection = 0
    @State private var remainingRouteCoordinates: [CLLocationCoordinate2D]
    @State private var remainingDistanceKm: Double

    init(
        destination: Harbor,
        routeSummary: RouteSummary,
        rainAvoidanceAlert: RainAvoidanceAlert?,
        onExit: @escaping () -> Void,
        onChangeDestination: @escaping () -> Void,
        onRerouteRequest: @escaping (CLLocation, [CLLocationCoordinate2D]) -> Void,
        onApplyRainAvoidance: @escaping () -> Void,
        locationService: LocationService
    ) {
        self.destination = destination
        self.routeSummary = routeSummary
        self.rainAvoidanceAlert = rainAvoidanceAlert
        self.onExit = onExit
        self.onChangeDestination = onChangeDestination
        self.onRerouteRequest = onRerouteRequest
        self.onApplyRainAvoidance = onApplyRainAvoidance
        self.locationService = locationService
        let initialCoordinates = routeSummary.routeCoordinates ?? []
        _remainingRouteCoordinates = State(initialValue: initialCoordinates)
        _remainingDistanceKm = State(initialValue: routeSummary.totalDistance)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                if remainingRouteCoordinates.count > 1 {
                    MapPolyline(coordinates: remainingRouteCoordinates)
                        .stroke(Color.aquaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()
            .onAppear {
                locationService.requestAuthorization()
                locationService.startTracking()
                setNavigationAwakeMode(enabled: true)
                // When navigation starts, zoom to the start point first.
                focusCameraOnStart(animated: false)
                focusCameraOnUser(animated: false)
            }
            .onDisappear {
                setNavigationAwakeMode(enabled: false)
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                if let newLocation {
                    updateRemainingRoute(with: newLocation)
                    onRerouteRequest(newLocation, remainingRouteCoordinates)
                }
                focusCameraOnUser(animated: true)
            }
            .onChange(of: locationService.heading) { _, _ in
                focusCameraOnUser(animated: true)
            }
            .onChange(of: routeSummary.totalDistance) { _, _ in
                resetRemainingRoute()
            }
            .onChange(of: routeSummary.routeCoordinates?.count ?? 0) { _, _ in
                resetRemainingRoute()
            }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(spacing: 10) {
                        ControlButton(icon: "xmark", color: .citrusOrange, foreground: .white, action: onExit)
                        ControlButton(icon: "line.3.horizontal", color: .citrusCard, foreground: .citrusPrimaryText, action: onChangeDestination)
                    }

                    Spacer()

                    MapZoomControl(onZoomIn: zoomIn, onZoomOut: zoomOut)
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)

                if let rainAvoidanceAlert {
                    rainAvoidanceBanner(alert: rainAvoidanceAlert)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                Spacer()

                DrivingInstructionCard(
                    route: routeSummary,
                    currentSpeedKmh: locationService.currentSpeedKmh,
                    remainingDistanceKm: remainingDistanceKm,
                    onChange: onChangeDestination
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .zIndex(2)
        }
    }

    private func resetRemainingRoute() {
        remainingRouteCoordinates = routeSummary.routeCoordinates ?? []
        remainingDistanceKm = routeSummary.totalDistance
    }

    private func updateRemainingRoute(with location: CLLocation) {
        guard remainingRouteCoordinates.count > 1 else { return }

        let currentCoordinate = location.coordinate
        let nearestIndex = nearestRouteIndex(to: currentCoordinate, in: remainingRouteCoordinates)
        guard nearestIndex >= 0 else { return }

        if nearestIndex > 0 {
            remainingRouteCoordinates = Array(remainingRouteCoordinates.dropFirst(nearestIndex))
        }

        let routeDistanceMeters = pathDistance(of: remainingRouteCoordinates)
        let connectorMeters: Double = {
            guard let head = remainingRouteCoordinates.first else { return 0 }
            return currentCoordinate.distance(to: head)
        }()

        remainingDistanceKm = max((routeDistanceMeters + connectorMeters) / 1000.0, 0)
    }

    private func nearestRouteIndex(
        to coordinate: CLLocationCoordinate2D,
        in route: [CLLocationCoordinate2D]
    ) -> Int {
        guard !route.isEmpty else { return -1 }
        var nearestIndex = 0
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude
        for (index, point) in route.enumerated() {
            let distance = coordinate.distance(to: point)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }

    private func pathDistance(of route: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard route.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 1..<route.count {
            total += route[index - 1].distance(to: route[index])
        }
        return total
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

    private func setNavigationAwakeMode(enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    private func rainAvoidanceBanner(alert: RainAvoidanceAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cloud.rain")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.citrusOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.citrusPrimaryText)
                Text(alert.message)
                    .font(.caption2)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("回避ルート提案") {
                onApplyRainAvoidance()
            }
            .font(.caption2.weight(.bold))
            .buttonStyle(.borderedProminent)
            .tint(Color.citrusAmber)
            .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))
        }
        .padding(12)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.citrusBorder)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

private struct DrivingInstructionCard: View {
    let route: RouteSummary
    let currentSpeedKmh: Double
    let remainingDistanceKm: Double
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(route.primaryInstruction)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(String(format: "%.1f km/h", currentSpeedKmh), systemImage: "speedometer")
                    Label(String(format: "%.1f km", remainingDistanceKm), systemImage: "bicycle.circle")
                }
                .font(.footnote.bold())
                .foregroundStyle(Color.citrusSecondaryText)
            }
            .foregroundStyle(Color.citrusPrimaryText)

            Text(route.secondaryInstruction)
                .font(.subheadline)
                .foregroundStyle(Color.citrusSecondaryText)

            HStack {
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
    let color: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .frame(width: 46, height: 46)
                .background(color, in: Circle())
                .foregroundStyle(foreground)
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
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
