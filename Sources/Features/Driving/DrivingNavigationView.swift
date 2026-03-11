import SwiftUI
import MapKit
import UIKit
import Combine

struct RouteProgressUpdate {
    let remainingRoute: [CLLocationCoordinate2D]
    let remainingDistanceKm: Double
}

struct RouteHazardAlert: Equatable {
    enum Kind: String {
        case sharpTurn = "急カーブ"
        case wetRoad = "路面悪化"
        case nightVisibility = "夜間視認性"
    }

    let kind: Kind
    let title: String
    let message: String
    let signature: String
}

enum RouteProgressEstimator {
    static func remainingProgress(
        currentCoordinate: CLLocationCoordinate2D,
        route: [CLLocationCoordinate2D]
    ) -> RouteProgressUpdate {
        guard route.count > 1 else {
            let connectorMeters = currentCoordinate.distance(to: route.first ?? currentCoordinate)
            return RouteProgressUpdate(
                remainingRoute: route,
                remainingDistanceKm: max(connectorMeters / 1000.0, 0)
            )
        }

        let nearestIndex = nearestRouteIndex(to: currentCoordinate, in: route)
        guard nearestIndex >= 0 else {
            return RouteProgressUpdate(
                remainingRoute: route,
                remainingDistanceKm: max(pathDistanceMeters(of: route) / 1000.0, 0)
            )
        }

        let remainingRoute = nearestIndex > 0 ? Array(route.dropFirst(nearestIndex)) : route
        let routeDistanceMeters = pathDistanceMeters(of: remainingRoute)
        let connectorMeters = currentCoordinate.distance(to: remainingRoute.first ?? currentCoordinate)
        return RouteProgressUpdate(
            remainingRoute: remainingRoute,
            remainingDistanceKm: max((routeDistanceMeters + connectorMeters) / 1000.0, 0)
        )
    }

    static func nearestRouteIndex(
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

    static func pathDistanceMeters(of route: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard route.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 1..<route.count {
            total += route[index - 1].distance(to: route[index])
        }
        return total
    }
}

enum RouteHazardEvaluator {
    static func detect(
        currentLocation: CLLocation,
        remainingRoute: [CLLocationCoordinate2D],
        weather: WeatherSnapshot,
        speedKmh: Double,
        now: Date = Date()
    ) -> RouteHazardAlert? {
        if let sharpTurnAlert = detectSharpTurnAhead(currentLocation: currentLocation, remainingRoute: remainingRoute) {
            return sharpTurnAlert
        }

        if speedKmh >= 14, (weather.warning == .warning || weather.roadRisk >= 1.2) {
            return RouteHazardAlert(
                kind: .wetRoad,
                title: "路面悪化注意",
                message: "雨/強風の影響あり。速度を落として走行してください",
                signature: "wetRoad-\(weather.warning.rawValue)"
            )
        }

        if speedKmh >= 18, isNightTime(now: now) {
            return RouteHazardAlert(
                kind: .nightVisibility,
                title: "夜間注意",
                message: "視認性が低い時間帯です。ライト点灯で減速走行してください",
                signature: "nightVisibility"
            )
        }
        return nil
    }

    private static func detectSharpTurnAhead(
        currentLocation: CLLocation,
        remainingRoute: [CLLocationCoordinate2D]
    ) -> RouteHazardAlert? {
        guard remainingRoute.count >= 4 else { return nil }

        let nearest = RouteProgressEstimator.nearestRouteIndex(to: currentLocation.coordinate, in: remainingRoute)
        guard nearest >= 0 else { return nil }

        let maxLookAheadDistance: CLLocationDistance = 160
        var traversedDistance: CLLocationDistance = 0
        var currentIndex = nearest

        while currentIndex + 2 < remainingRoute.count && traversedDistance <= maxLookAheadDistance {
            let a = remainingRoute[currentIndex]
            let b = remainingRoute[currentIndex + 1]
            let c = remainingRoute[currentIndex + 2]
            let segmentDistance = a.distance(to: b)
            traversedDistance += segmentDistance

            let firstBearing = bearing(from: a, to: b)
            let secondBearing = bearing(from: b, to: c)
            let delta = angularDelta(firstBearing, secondBearing)

            if delta >= 65, traversedDistance <= 140 {
                let meters = max(Int(traversedDistance.rounded()), 20)
                return RouteHazardAlert(
                    kind: .sharpTurn,
                    title: "前方急カーブ注意",
                    message: "約\(meters)m先で進行方向が大きく変わります。減速してください",
                    signature: "sharpTurn-\(currentIndex)"
                )
            }

            currentIndex += 1
        }
        return nil
    }

    private static func isNightTime(now: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= 19 || hour <= 5
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        let y = sin(lon2 - lon1) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)
        let angle = atan2(y, x) * 180 / .pi
        return fmod(angle + 360, 360)
    }

    private static func angularDelta(_ first: Double, _ second: Double) -> Double {
        let raw = abs(first - second)
        return min(raw, 360 - raw)
    }
}

struct DrivingNavigationView: View {
    let destination: Harbor
    let routeSummary: RouteSummary
    let rainAvoidanceAlert: RainAvoidanceAlert?
    let weatherSnapshot: WeatherSnapshot
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
    @State private var hasShownArrivalMessage = false
    @State private var showArrivalMessage = false
    @State private var arrivalMessage: String?
    @State private var hasTriggeredAutoExit = false
    @State private var showHydrationReminder = false
    @State private var hydrationReminderText = ""
    @State private var hydrationIntervalMinutes = 20
    @State private var lastHydrationReminderAt = Date()
    @State private var hydrationTimer: AnyCancellable?
    @State private var activeHazardAlert: RouteHazardAlert?
    @State private var showHazardAlert = false
    @State private var lastHazardAlertAt = Date.distantPast
    @State private var lastHazardSignature: String?

    init(
        destination: Harbor,
        routeSummary: RouteSummary,
        rainAvoidanceAlert: RainAvoidanceAlert?,
        weatherSnapshot: WeatherSnapshot,
        onExit: @escaping () -> Void,
        onChangeDestination: @escaping () -> Void,
        onRerouteRequest: @escaping (CLLocation, [CLLocationCoordinate2D]) -> Void,
        onApplyRainAvoidance: @escaping () -> Void,
        locationService: LocationService
    ) {
        self.destination = destination
        self.routeSummary = routeSummary
        self.rainAvoidanceAlert = rainAvoidanceAlert
        self.weatherSnapshot = weatherSnapshot
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
                refreshHydrationPlan()
                startHydrationTimer()
                // When navigation starts, zoom to the start point first.
                focusCameraOnStart(animated: false)
                focusCameraOnUser(animated: false)
            }
            .onDisappear {
                setNavigationAwakeMode(enabled: false)
                hydrationTimer?.cancel()
                hydrationTimer = nil
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                if let newLocation {
                    updateRemainingRoute(with: newLocation)
                    evaluateArrival()
                    if !hasShownArrivalMessage {
                        onRerouteRequest(newLocation, remainingRouteCoordinates)
                        evaluateHazardAlert(with: newLocation)
                    }
                }
                focusCameraOnUser(animated: true)
            }
            .onChange(of: locationService.currentSpeedKmh) { _, _ in
                refreshHydrationPlan()
            }
            .onChange(of: remainingDistanceKm) { _, _ in
                evaluateArrival()
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

                if showHazardAlert, let activeHazardAlert {
                    HazardAlertBanner(alert: activeHazardAlert)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showHydrationReminder {
                    HydrationReminderBanner(message: hydrationReminderText)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if showArrivalMessage, let arrivalMessage {
                    ArrivalCelebrationBanner(message: arrivalMessage)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
        let progress = RouteProgressEstimator.remainingProgress(
            currentCoordinate: location.coordinate,
            route: remainingRouteCoordinates
        )
        remainingRouteCoordinates = progress.remainingRoute
        remainingDistanceKm = progress.remainingDistanceKm
    }

    private func evaluateArrival() {
        guard !hasShownArrivalMessage else { return }
        let distanceToDestination: CLLocationDistance = {
            if let coordinate = locationService.currentLocation?.coordinate {
                return coordinate.distance(to: destination.coordinate)
            }
            if let routeEnd = remainingRouteCoordinates.last {
                return routeEnd.distance(to: destination.coordinate)
            }
            return .greatestFiniteMagnitude
        }()
        let isArrivedByRoute = remainingDistanceKm <= 0.08 || remainingRouteCoordinates.count <= 1
        let isArrived = distanceToDestination <= 45 || isArrivedByRoute
        guard isArrived else { return }

        hasShownArrivalMessage = true
        arrivalMessage = arrivalMessages.randomElement() ?? "目的地に到着しました。おつかれさまでした。"
        withAnimation(.spring(duration: 0.4)) {
            showArrivalMessage = true
        }
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showArrivalMessage = false
            }
        }
        triggerAutoExitAfterArrival()
    }

    private func triggerAutoExitAfterArrival() {
        guard !hasTriggeredAutoExit else { return }
        hasTriggeredAutoExit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            onExit()
        }
    }

    private var arrivalMessages: [String] {
        [
            "目的地に到着しました。最高のライドでした。",
            "ナビ完了です。ここからはゆっくり休憩しましょう。",
            "到着しました。今日の一本、いい走りです。",
            "ゴールです。安全運転ありがとうございました。"
        ]
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

    private func startHydrationTimer() {
        hydrationTimer?.cancel()
        hydrationTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                checkHydrationReminder()
            }
    }

    private func evaluateHazardAlert(with location: CLLocation) {
        guard !hasShownArrivalMessage else { return }
        guard !remainingRouteCoordinates.isEmpty else { return }

        guard let hazard = RouteHazardEvaluator.detect(
            currentLocation: location,
            remainingRoute: remainingRouteCoordinates,
            weather: weatherSnapshot,
            speedKmh: locationService.currentSpeedKmh
        ) else {
            return
        }

        let now = Date()
        let minInterval: TimeInterval = 18
        if now.timeIntervalSince(lastHazardAlertAt) < minInterval {
            return
        }
        if lastHazardSignature == hazard.signature,
           now.timeIntervalSince(lastHazardAlertAt) < 45 {
            return
        }

        lastHazardAlertAt = now
        lastHazardSignature = hazard.signature
        activeHazardAlert = hazard
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)
        withAnimation(.easeInOut(duration: 0.25)) {
            showHazardAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showHazardAlert = false
            }
        }
#if DEBUG
        print("Hazard alert: \(hazard.kind.rawValue) / \(hazard.message)")
#endif
    }

    private func refreshHydrationPlan() {
        var interval = 20
        let temp = weatherSnapshot.temperatureCelsius
        let speed = locationService.currentSpeedKmh

        if temp >= 30 {
            interval -= 6
        } else if temp >= 25 {
            interval -= 4
        } else if temp <= 5 {
            interval += 4
        }

        if speed >= 25 {
            interval -= 4
        } else if speed >= 18 {
            interval -= 2
        } else if speed < 10 {
            interval += 2
        }

        if weatherSnapshot.warning == .warning {
            interval -= 2
        }

        hydrationIntervalMinutes = min(max(interval, 8), 35)
        let caloriesPerHour = estimateCaloriesPerHour(speedKmh: max(speed, 8))
        hydrationReminderText = "\(hydrationIntervalMinutes)分ごとに給水 / 約\(caloriesPerHour)kcal/h"
    }

    private func checkHydrationReminder() {
        guard !hasShownArrivalMessage else { return }
        guard locationService.currentSpeedKmh >= 4 else { return }

        let elapsed = Date().timeIntervalSince(lastHydrationReminderAt)
        guard elapsed >= TimeInterval(hydrationIntervalMinutes * 60) else { return }
        lastHydrationReminderAt = Date()

        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)
        withAnimation(.easeInOut(duration: 0.25)) {
            showHydrationReminder = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showHydrationReminder = false
            }
        }
    }

    private func estimateCaloriesPerHour(speedKmh: Double) -> Int {
        let met: Double
        switch speedKmh {
        case ..<16:
            met = 6.8
        case ..<20:
            met = 8.0
        case ..<24:
            met = 10.0
        default:
            met = 12.0
        }
        let weightKg = 70.0
        return Int((met * 3.5 * weightKg) / 200 * 60)
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

private struct ArrivalCelebrationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.green)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.citrusPrimaryText)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
    }
}

private struct HydrationReminderBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.cyan)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.citrusPrimaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
    }
}

private struct HazardAlertBanner: View {
    let alert: RouteHazardAlert

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.citrusPrimaryText)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
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
