import Foundation
import Combine
import CoreLocation
import MapKit

enum CyclingRouteMode: String, CaseIterable, Identifiable {
    case flat
    case hillClimb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat:
            return "平坦優先"
        case .hillClimb:
            return "ヒルクライム"
        }
    }

    var description: String {
        switch self {
        case .flat:
            return "獲得標高を抑えた走りやすいルートを優先"
        case .hillClimb:
            return "トレーニング向けに登り寄りのルートを優先"
        }
    }
}

struct RainAvoidanceAlert: Equatable {
    let minutesUntilRain: Int
    let createdAt: Date

    var title: String { "雨回避アラート" }
    var message: String {
        "\(minutesUntilRain)分後にルート上で降雨予測。回避ルートを提案できます"
    }
}

struct TodayRideSuggestion: Identifiable {
    let id = UUID()
    let harbor: Harbor
    let title: String
    let subtitle: String
}

struct WeeklyMissionProgress: Equatable {
    let title: String
    let targetKm: Double
    let currentKm: Double

    var progress: Double {
        guard targetKm > 0 else { return 0 }
        return min(max(currentKm / targetKm, 0), 1)
    }

    var remainingKm: Double {
        max(targetKm - currentKm, 0)
    }

    var isCompleted: Bool {
        currentKm >= targetKm
    }
}

struct RideCompletionReward: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let badges: [String]
}

@MainActor
final class NavigationDashboardViewModel: ObservableObject {
    enum RideLogHealthStatus {
        case syncing
        case synced
        case skipped(String)
        case failed(String)

        var text: String {
            switch self {
            case .syncing:
                return "同期中..."
            case .synced:
                return "Health同期済み"
            case .skipped(let reason):
                return reason
            case .failed(let reason):
                return "同期失敗: \(reason)"
            }
        }
    }
    @Published var weatherSnapshot: WeatherSnapshot = .sample
    @Published var voyageLogs: [VoyageLog] = []
    @Published var rideLogHealthStatuses: [UUID: RideLogHealthStatus] = [:]
    @Published var harbors: [Harbor] = Harbor.sample
    @Published var warningMessage: String?
    @Published var activeDestination: Harbor?
    @Published var routeSummary: RouteSummary?
    @Published var isGeneratingRoute = false
    @Published var pendingRoute: RouteSummary?
    @Published var selectedRouteMode: CyclingRouteMode = .flat
    @Published var rainAvoidanceAlert: RainAvoidanceAlert?
    @Published var todayRideSuggestion: TodayRideSuggestion?
    @Published var weeklyMission: WeeklyMissionProgress = .init(title: "今週40km", targetKm: 40, currentKm: 0)
    @Published var latestRideReward: RideCompletionReward?

    let locationService: LocationService
    private let weatherService: WeatherService
    private let rideLogSyncService: RideLogSyncService
    private let routePlanner = MapKitRoadRoutePlanner()
    private let spotProvider = NearbySpotProvider()
    private var weatherTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var lastRouteOrigin: CLLocationCoordinate2D?
    private var lastSpotsOrigin: CLLocationCoordinate2D?
    private var spotsTask: Task<Void, Never>?
    private var activeRideStartTime: Date?
    private var activeRideStartRouteIndex: Int?
    private var lastOffRouteRerouteAt: Date = .distantPast
    private var lastWeatherCoordinate: CLLocationCoordinate2D?
    private var lastWeatherRefreshAt: Date = .distantPast
    private var lastRainAlertRefreshAt: Date = .distantPast
    private static let voyageLogsFileName = "voyage_logs.json"
    private static let dashboardNearbyRadiusKm: Double = 30.0
    private static let rainAlertRefreshInterval: TimeInterval = 300
    private static let rainAlertTargetRange = 30...60

    init(
        locationService: LocationService,
        weatherService: WeatherService,
        rideLogSyncService: RideLogSyncService = NoopRideLogSyncService()
    ) {
        self.locationService = locationService
        self.weatherService = weatherService
        self.rideLogSyncService = rideLogSyncService

        bindLocation()
        startWeatherPolling()
        loadVoyageLogsFromDisk()
        recalculateGrowthWidgets()
        Task { await refreshConditions() }
        Task { await refreshNearbySpots(force: true) }
    }

    func consumeLatestRideReward() {
        latestRideReward = nil
    }

    func startNavigation(to harbor: Harbor, mode: CyclingRouteMode) {
        selectedRouteMode = mode
        activeDestination = harbor
        routeSummary = nil
        pendingRoute = nil
        rainAvoidanceAlert = nil
        lastRainAlertRefreshAt = .distantPast
        isGeneratingRoute = true
        Task { await generateRoute(to: harbor) }
    }

    func endNavigation() {
        finalizeRideLogIfNeeded()
        activeDestination = nil
        routeSummary = nil
        pendingRoute = nil
        rainAvoidanceAlert = nil
        lastRainAlertRefreshAt = .distantPast
        isGeneratingRoute = false
    }

    func beginDrivingNavigation() {
        guard let pendingRoute else { return }
        routeSummary = pendingRoute
        self.pendingRoute = nil
        beginRideLogIfNeeded()
        Task { await refreshRainAvoidanceAlert(force: true) }
    }

    func cancelRoutePreview() {
        pendingRoute = nil
        activeDestination = nil
        rainAvoidanceAlert = nil
        lastRainAlertRefreshAt = .distantPast
        isGeneratingRoute = false
    }

    func applyRainAvoidanceReroute() {
        guard let destination = activeDestination else { return }
        guard !isGeneratingRoute else { return }
        selectedRouteMode = .flat
        isGeneratingRoute = true
        #if DEBUG
        print("Rain avoidance reroute requested.")
        #endif
        Task { await generateRoute(to: destination) }
    }

    func requestRerouteIfOffRoute(currentLocation: CLLocation, referenceRoute: [CLLocationCoordinate2D]) {
        guard let destination = activeDestination else { return }
        guard !referenceRoute.isEmpty else { return }
        guard !isGeneratingRoute else { return }
        let offRouteThresholdMeters: CLLocationDistance = 35
        let cooldown: TimeInterval = 8

        let distance = RouteGeometry.distanceFromRoute(currentLocation.coordinate, route: referenceRoute)
        guard distance > offRouteThresholdMeters else { return }
        guard Date().timeIntervalSince(lastOffRouteRerouteAt) >= cooldown else { return }

        #if DEBUG
        print("Off-route detected (\(Int(distance))m). Triggering reroute.")
        #endif

        lastOffRouteRerouteAt = Date()
        isGeneratingRoute = true
        Task { await generateRoute(to: destination) }
    }

    private func startWeatherPolling() {
        weatherTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshConditions(force: true) }
            }
    }

    private func bindLocation() {
        locationService.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self else { return }
                handleLocationUpdate(location)
                scheduleNearbySpotsRefresh(for: location.coordinate)
                Task { await self.refreshConditions() }
            }
            .store(in: &cancellables)
    }

    private func refreshConditions(force: Bool = false) async {
        guard let coordinate = locationService.currentLocation?.coordinate else {
            return
        }

        let now = Date()
        if !force,
           let lastWeatherCoordinate,
           now.timeIntervalSince(lastWeatherRefreshAt) < 45 {
            let moved = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: lastWeatherCoordinate.latitude, longitude: lastWeatherCoordinate.longitude))
            if moved < 300 {
                return
            }
        }

        do {
            let snapshot = try await weatherService.fetchSnapshot(
                for: CoordinateReference(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            weatherSnapshot = snapshot
            lastWeatherCoordinate = coordinate
            lastWeatherRefreshAt = now
            if warningMessage == nil {
                warningMessage = snapshot.warning == .warning ? "強風注意" : nil
            }
#if DEBUG
            print(
                String(
                    format: "Weather updated: lat=%.5f lon=%.5f condition=%@",
                    coordinate.latitude,
                    coordinate.longitude,
                    snapshot.condition
                )
            )
#endif
            await refreshRainAvoidanceAlert()
            recalculateGrowthWidgets()
        } catch {
            if warningMessage == nil {
                warningMessage = "気象データ更新に失敗"
            }
#if DEBUG
            print(
                String(
                    format: "Weather update failed: lat=%.5f lon=%.5f error=%@",
                    coordinate.latitude,
                    coordinate.longitude,
                    String(describing: error)
                )
            )
#endif
        }
    }

    private func generateRoute(to harbor: Harbor) async {
        let userCoordinate = locationService.currentCoordinateOrDefault()
        lastRouteOrigin = userCoordinate

        let computation = await routePlanner.calculateRoute(
            from: userCoordinate,
            to: harbor.coordinate,
            destinationName: harbor.name,
            routeMode: selectedRouteMode
        )

        if let roadRoute = computation.route {
            let cyclingSpeedKmh = 18.0
            let etaMinutes = Int(roadRoute.distanceMeters / (cyclingSpeedKmh / 3.6) / 60)
            await MainActor.run {
                let summary = RouteSummary(
                    totalDistance: roadRoute.distanceMeters / 1000.0,
                    etaMinutes: max(etaMinutes, harbor.etaMinutes),
                    primaryInstruction: roadRoute.primaryInstruction,
                    secondaryInstruction: roadRoute.secondaryInstruction,
                    nextDistance: roadRoute.nextDistanceMeters / 1000.0,
                    routeCoordinates: roadRoute.coordinates
                )
                if routeSummary != nil {
                    routeSummary = summary
                } else {
                    pendingRoute = summary
                }
                #if DEBUG
                print("Reroute completed.")
                #endif
                warningMessage = computation.usedSnappedDestination ? "目的地を最寄り道路に補正して案内中" : nil
                isGeneratingRoute = false
            }
            await refreshRainAvoidanceAlert(force: true)
            return
        }

        // Fallback when routing API fails/offline.
        // Avoid presenting long straight-line routes because they are unsafe/useless for navigation.
        let fallbackRoute = [userCoordinate, harbor.coordinate]
        let distanceMeters = routeDistance(fallbackRoute)
        if distanceMeters > 300 {
            await MainActor.run {
                warningMessage = "道路ルート取得失敗: \(computation.failureReason)"
                pendingRoute = nil
                rainAvoidanceAlert = nil
                isGeneratingRoute = false
                #if DEBUG
                print("Reroute failed: \(computation.failureReason)")
                #endif
            }
            return
        }

        let cyclingSpeedKmh = 18.0
        let etaMinutes = Int(distanceMeters / (cyclingSpeedKmh / 3.6) / 60)

        await MainActor.run {
            let summary = RouteSummary(
                totalDistance: distanceMeters / 1000.0,
                etaMinutes: max(etaMinutes, harbor.etaMinutes),
                primaryInstruction: "推奨ルートを進む",
                secondaryInstruction: harbor.name,
                nextDistance: distanceMeters / 1000.0,
                routeCoordinates: fallbackRoute
            )
            if routeSummary != nil {
                routeSummary = summary
            } else {
                pendingRoute = summary
            }
            #if DEBUG
            print("Reroute completed with short fallback route.")
            #endif
            warningMessage = "近距離直線補助: \(computation.failureReason)"
            isGeneratingRoute = false
        }
        await refreshRainAvoidanceAlert(force: true)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        maybeRefreshRoute(for: location.coordinate)
    }

    private func maybeRefreshRoute(for coordinate: CLLocationCoordinate2D) {
        guard let destination = activeDestination else { return }
        guard !isGeneratingRoute else { return }
        // While actively driving, reroute is controlled by off-route detection.
        guard routeSummary == nil else { return }
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return }
        let threshold: CLLocationDistance = 200
        if let lastOrigin = lastRouteOrigin {
            if coordinate.distance(to: lastOrigin) < threshold { return }
        }
        isGeneratingRoute = true
        Task { await generateRoute(to: destination) }
    }

    private func refreshRainAvoidanceAlert(force: Bool = false) async {
        guard activeDestination != nil else {
            rainAvoidanceAlert = nil
            return
        }

        guard let routeCoordinates = (routeSummary?.routeCoordinates ?? pendingRoute?.routeCoordinates),
              routeCoordinates.count > 1 else {
            rainAvoidanceAlert = nil
            return
        }

        let now = Date()
        if !force, now.timeIntervalSince(lastRainAlertRefreshAt) < Self.rainAlertRefreshInterval {
            return
        }
        lastRainAlertRefreshAt = now

        var predictedMinutes: [Int] = []

        if let localMinutes = rainAlertCandidateMinutes(from: weatherSnapshot.precipitationStartMinutes) {
            predictedMinutes.append(localMinutes)
        }

        let samples = sampledRouteCoordinates(from: routeCoordinates)
        for sample in samples {
            do {
                let snapshot = try await weatherService.fetchSnapshot(
                    for: CoordinateReference(latitude: sample.latitude, longitude: sample.longitude)
                )
                if let minutes = rainAlertCandidateMinutes(from: snapshot.precipitationStartMinutes) {
                    predictedMinutes.append(minutes)
                }
            } catch {
                #if DEBUG
                print(
                    String(
                        format: "Rain alert sampling failed: lat=%.5f lon=%.5f error=%@",
                        sample.latitude,
                        sample.longitude,
                        String(describing: error)
                    )
                )
                #endif
            }
        }

        if let nearestMinutes = predictedMinutes.min() {
            rainAvoidanceAlert = RainAvoidanceAlert(minutesUntilRain: nearestMinutes, createdAt: now)
            #if DEBUG
            print("Rain avoidance alert active: rain in \(nearestMinutes) minutes.")
            #endif
        } else {
            rainAvoidanceAlert = nil
        }
    }

    private func rainAlertCandidateMinutes(from minutes: Int?) -> Int? {
        guard let minutes else { return nil }
        guard Self.rainAlertTargetRange.contains(minutes) else { return nil }
        return minutes
    }

    private func sampledRouteCoordinates(from route: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !route.isEmpty else { return [] }
        let quarter = min(route.count - 1, max(0, route.count / 4))
        let middle = min(route.count - 1, max(0, route.count / 2))
        let end = route.count - 1
        let indices = [quarter, middle, end]
        var sampled: [CLLocationCoordinate2D] = []
        var seenKeys = Set<String>()

        for index in indices {
            let coordinate = route[index]
            let key = "\(Int((coordinate.latitude * 10_000).rounded())):\(Int((coordinate.longitude * 10_000).rounded()))"
            if seenKeys.insert(key).inserted {
                sampled.append(coordinate)
            }
        }
        return sampled
    }

    private func scheduleNearbySpotsRefresh(for coordinate: CLLocationCoordinate2D) {
        let threshold: CLLocationDistance = 500
        if let last = lastSpotsOrigin, coordinate.distance(to: last) < threshold {
            return
        }
        spotsTask?.cancel()
        spotsTask = Task { [weak self] in
            await self?.refreshNearbySpots(force: false)
        }
    }

    private func refreshNearbySpots(force: Bool) async {
        let origin = locationService.currentCoordinateOrDefault()
        if !force, let last = lastSpotsOrigin, origin.distance(to: last) < 500 {
            return
        }

        let nearby = await spotProvider.fetchNearby(
            origin: origin,
            radiusKm: Self.dashboardNearbyRadiusKm,
            query: nil
        )

        await MainActor.run {
            if !nearby.isEmpty {
                harbors = nearby
            } else {
                harbors = Harbor.sample
                    .map { harbor -> Harbor in
                        let distanceMeters = harbor.coordinate.distance(to: origin)
                        let distanceKm = distanceMeters / 1000.0
                        let eta = max(Int(distanceMeters / (18.0 / 3.6) / 60), 5)
                        return Harbor(
                            name: harbor.name,
                            coordinate: harbor.coordinate,
                            facilities: harbor.facilities,
                            restrictions: harbor.restrictions,
                            distance: distanceKm,
                            etaMinutes: eta
                        )
                    }
                    .filter { $0.distance <= Self.dashboardNearbyRadiusKm }
                    .sorted { $0.distance < $1.distance }
            }
            lastSpotsOrigin = origin
            recalculateGrowthWidgets()
        }
    }

    private func routeDistance(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var distance: Double = 0
        for index in 1..<coordinates.count {
            let prev = CLLocation(latitude: coordinates[index - 1].latitude, longitude: coordinates[index - 1].longitude)
            let next = CLLocation(latitude: coordinates[index].latitude, longitude: coordinates[index].longitude)
            distance += prev.distance(from: next)
        }
        return distance
    }

    private func beginRideLogIfNeeded() {
        guard activeRideStartTime == nil else { return }
        activeRideStartTime = Date()
        activeRideStartRouteIndex = locationService.routePoints.count
    }

    private func finalizeRideLogIfNeeded() {
        guard let startTime = activeRideStartTime else { return }
        let endTime = Date()
        let startIndex = min(activeRideStartRouteIndex ?? 0, locationService.routePoints.count)
        let capturedRoute = Array(locationService.routePoints.dropFirst(startIndex))
        let distanceMeters = routeDistance(capturedRoute)
        let duration = max(endTime.timeIntervalSince(startTime), 1)
        let averageSpeedKmh = (distanceMeters / duration) * 3.6
        let weatherSummary = String(
            format: "風 %@ %.0fkm/h / 路面リスク %.1f",
            weatherSnapshot.windCompass,
            weatherSnapshot.windSpeed * 3.6,
            weatherSnapshot.roadRisk
        )
        let previousBestDistance = voyageLogs.map(\.distance).max() ?? 0

        let newLog = VoyageLog(
            id: UUID(),
            startTime: startTime,
            endTime: endTime,
            routePoints: capturedRoute,
            distance: distanceMeters / 1000.0,
            averageSpeed: averageSpeedKmh,
            weatherSummary: weatherSummary
        )
        voyageLogs.insert(newLog, at: 0)
        latestRideReward = buildRideCompletionReward(newLog: newLog, previousBestDistance: previousBestDistance)
        recalculateGrowthWidgets()
        rideLogHealthStatuses[newLog.id] = .syncing
        persistVoyageLogs()
        Task { [rideLogSyncService] in
            let result = await rideLogSyncService.syncRideLog(newLog)
            await MainActor.run {
                switch result {
                case .synced:
                    rideLogHealthStatuses[newLog.id] = .synced
                case .skipped(let reason):
                    rideLogHealthStatuses[newLog.id] = .skipped(reason)
                case .failed(let reason):
                    rideLogHealthStatuses[newLog.id] = .failed(reason)
                }
            }
        }

        activeRideStartTime = nil
        activeRideStartRouteIndex = nil
    }

    private func persistVoyageLogs() {
        let payload = voyageLogs.map(PersistedVoyageLog.init)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: Self.voyageLogsFileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to persist voyage logs:", error)
            #endif
        }
    }

    private func loadVoyageLogsFromDisk() {
        let url = Self.voyageLogsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([PersistedVoyageLog].self, from: data)
            voyageLogs = decoded.map(\.model).sorted { $0.startTime > $1.startTime }
            recalculateGrowthWidgets()
        } catch {
            #if DEBUG
            print("Failed to load voyage logs:", error)
            #endif
        }
    }

    private static var voyageLogsFileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent(voyageLogsFileName)
    }

    private func recalculateGrowthWidgets() {
        weeklyMission = computeWeeklyMission()
        todayRideSuggestion = computeTodayRideSuggestion()
    }

    private func computeWeeklyMission() -> WeeklyMissionProgress {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let currentKm = voyageLogs
            .filter { $0.startTime >= startOfWeek && $0.startTime <= now }
            .reduce(0) { $0 + $1.distance }
        return WeeklyMissionProgress(
            title: "今週40km",
            targetKm: 40,
            currentKm: currentKm
        )
    }

    private func computeTodayRideSuggestion() -> TodayRideSuggestion? {
        guard !harbors.isEmpty else { return nil }
        let targetRange = 10.0...50.0
        let riskPenalty = weatherSnapshot.warning == .warning ? 8.0 : (weatherSnapshot.warning == .advisory ? 4.0 : 0.0)
        let targetDistance: Double = {
            if weatherSnapshot.precipitationStartMinutes != nil { return 12 }
            if weatherSnapshot.windSpeed >= 9 { return 14 }
            return 18
        }()
        let candidatePool = harbors.filter { targetRange.contains($0.distance) }
        guard !candidatePool.isEmpty else { return nil }

        let candidate = candidatePool.min { lhs, rhs in
            suggestionScore(for: lhs, targetDistance: targetDistance, riskPenalty: riskPenalty)
                < suggestionScore(for: rhs, targetDistance: targetDistance, riskPenalty: riskPenalty)
        }

        guard let harbor = candidate else { return nil }
        let subtitle = "約\(String(format: "%.1f", harbor.distance))km・ETA\(harbor.etaMinutes)分 / \(weatherSnapshot.condition)"
        return TodayRideSuggestion(
            harbor: harbor,
            title: "今日の1本: \(harbor.name)",
            subtitle: subtitle
        )
    }

    private func suggestionScore(
        for harbor: Harbor,
        targetDistance: Double,
        riskPenalty: Double
    ) -> Double {
        let distanceScore = abs(harbor.distance - targetDistance)
        let restrictionScore = Double(harbor.restrictions.count) * 0.6
        return distanceScore + restrictionScore + riskPenalty
    }

    private func buildRideCompletionReward(
        newLog: VoyageLog,
        previousBestDistance: Double
    ) -> RideCompletionReward {
        var badges: [String] = []
        if newLog.distance >= 30 {
            badges.append("ロングライド")
        } else if newLog.distance >= 15 {
            badges.append("ミドルライド")
        } else {
            badges.append("ショートライド")
        }
        if newLog.distance > previousBestDistance {
            badges.append("自己最長更新")
        }
        let remaining = max(weeklyMission.targetKm - (weeklyMission.currentKm + newLog.distance), 0)
        if remaining <= 0 {
            badges.append("週次ミッション達成")
        } else {
            badges.append("目標まで\(String(format: "%.1f", remaining))km")
        }
        return RideCompletionReward(
            title: "ライド完了おつかれさま",
            subtitle: String(format: "%.1fkm / 平均%.1fkm/h", newLog.distance, newLog.averageSpeed),
            badges: badges
        )
    }
}

enum RouteGeometry {
    static func distanceFromRoute(
        _ point: CLLocationCoordinate2D,
        route: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard route.count > 1 else {
            guard let only = route.first else { return .greatestFiniteMagnitude }
            return point.distance(to: only)
        }

        let pointMap = MKMapPoint(point)
        var best = CLLocationDistance.greatestFiniteMagnitude

        for index in 1..<route.count {
            let a = MKMapPoint(route[index - 1])
            let b = MKMapPoint(route[index])
            let distance = distanceFromPointToSegment(point: pointMap, a: a, b: b)
            if distance < best {
                best = distance
            }
        }
        return best
    }

    private static func distanceFromPointToSegment(
        point: MKMapPoint,
        a: MKMapPoint,
        b: MKMapPoint
    ) -> CLLocationDistance {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = (dx * dx) + (dy * dy)

        guard lengthSquared > 0 else {
            return point.distance(to: a)
        }

        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let projection = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
        return point.distance(to: projection)
    }
}

private struct PersistedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var model: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct PersistedVoyageLog: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let routePoints: [PersistedCoordinate]
    let distance: Double
    let averageSpeed: Double
    let weatherSummary: String

    init(_ model: VoyageLog) {
        id = model.id
        startTime = model.startTime
        endTime = model.endTime
        routePoints = model.routePoints.map(PersistedCoordinate.init)
        distance = model.distance
        averageSpeed = model.averageSpeed
        weatherSummary = model.weatherSummary
    }

    var model: VoyageLog {
        VoyageLog(
            id: id,
            startTime: startTime,
            endTime: endTime,
            routePoints: routePoints.map(\.model),
            distance: distance,
            averageSpeed: averageSpeed,
            weatherSummary: weatherSummary
        )
    }
}

struct RoadRouteResult {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let primaryInstruction: String
    let secondaryInstruction: String
    let nextDistanceMeters: Double
}

struct RoadRouteComputation {
    let route: RoadRouteResult?
    let failureReason: String
    let usedSnappedDestination: Bool
}

final class MapKitRoadRoutePlanner {
    private let roadSnapper = DestinationRoadSnapper()

        // NOTE: MKDirections does not currently expose a dedicated cycling transport type.
        // For bicycle routing, prioritize road-like routes (automobile) and use walking only as fallback.
    func calculateRoute(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        routeMode: CyclingRouteMode
    ) async -> RoadRouteComputation {
        let snapped = await roadSnapper.snap(destination)
        let transportCandidates: [MKDirectionsTransportType] = {
            switch routeMode {
            case .flat:
                return [.automobile, .walking]
            case .hillClimb:
                return [.walking, .automobile]
            }
        }()
        let destinationCandidates = [snapped.coordinate] + offsetCandidates(from: snapped.coordinate)
        let startCandidates = [start] + offsetCandidates(from: start, distances: [20, 40])
        var failureNotes: [String] = []

        for transport in transportCandidates {
            for end in destinationCandidates {
                let attempt = await calculate(
                    from: start,
                    to: end,
                    destinationName: destinationName,
                    transportType: transport,
                    routeMode: routeMode
                )
                if let route = attempt.route {
                    return RoadRouteComputation(
                        route: route,
                        failureReason: "",
                        usedSnappedDestination: snapped.didSnap
                    )
                }
                if let failure = attempt.failureReason {
                    failureNotes.append(failure)
                }
            }
        }

        for transport in transportCandidates {
            for begin in startCandidates {
                let attempt = await calculate(
                    from: begin,
                    to: snapped.coordinate,
                    destinationName: destinationName,
                    transportType: transport,
                    routeMode: routeMode
                )
                if let route = attempt.route {
                    return RoadRouteComputation(
                        route: route,
                        failureReason: "",
                        usedSnappedDestination: snapped.didSnap
                    )
                }
                if let failure = attempt.failureReason {
                    failureNotes.append(failure)
                }
            }
        }

        let reason = failureNotes.last ?? "経路候補なし"
        let suffix = snapped.didSnap ? "（目的地道路補正済み）" : ""
        return RoadRouteComputation(route: nil, failureReason: reason + suffix, usedSnappedDestination: snapped.didSnap)
    }

    private func calculate(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        transportType: MKDirectionsTransportType,
        routeMode: CyclingRouteMode
    ) async -> (route: RoadRouteResult?, failureReason: String?) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = transportType
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            guard !response.routes.isEmpty else {
                return (nil, "\(transportLabel(transportType)): ルート候補なし")
            }

            let validRoutes = response.routes.filter { route in
                !(transportType == .walking && containsStairs(route.steps))
            }

            guard !validRoutes.isEmpty else {
                return (nil, "\(transportLabel(transportType)): 階段を含むため除外")
            }

            let route = selectBestRoute(validRoutes, transportType: transportType, mode: routeMode)
            let rawCoords = route.polyline.coordinatePoints
            let coords = smoothRouteCoordinates(rawCoords)
            guard coords.count > 1 else {
                return (nil, "\(transportLabel(transportType)): ポリライン不足")
            }

            let firstStep = route.steps.first {
                !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let primary = firstStep?.instructions.isEmpty == false ? firstStep!.instructions : "推奨ルートを進む"
            let nextDistance = firstStep?.distance ?? min(route.distance, 300)

            return (
                RoadRouteResult(
                    coordinates: coords,
                    distanceMeters: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    primaryInstruction: primary,
                    secondaryInstruction: destinationName,
                    nextDistanceMeters: nextDistance
                ),
                nil
            )
        } catch {
            return (nil, "\(transportLabel(transportType)): \(routingErrorDescription(error))")
        }
    }

    private func selectBestRoute(
        _ routes: [MKRoute],
        transportType: MKDirectionsTransportType,
        mode: CyclingRouteMode
    ) -> MKRoute {
        switch mode {
        case .flat:
            // Flat mode prioritizes shorter routes and road-like segments.
            return routes.min {
                scoreForFlat($0, transportType: transportType) < scoreForFlat($1, transportType: transportType)
            } ?? routes[0]
        case .hillClimb:
            // Hill-climb mode prioritizes walking-compatible and longer routes.
            return routes.min {
                scoreForHillClimb($0, transportType: transportType) < scoreForHillClimb($1, transportType: transportType)
            } ?? routes[0]
        }
    }

    private func scoreForFlat(_ route: MKRoute, transportType: MKDirectionsTransportType) -> Double {
        let transportPenalty = transportType == .automobile ? 0.0 : 5_000.0
        return route.distance + transportPenalty
    }

    private func scoreForHillClimb(_ route: MKRoute, transportType: MKDirectionsTransportType) -> Double {
        let transportPenalty = transportType == .walking ? 0.0 : 1_000_000.0
        return transportPenalty - route.distance
    }

    private func transportLabel(_ type: MKDirectionsTransportType) -> String {
        switch type {
        case .walking:
            return "徒歩"
        case .automobile:
            return "自動車"
        default:
            return "その他"
        }
    }

    private func containsStairs(_ steps: [MKRoute.Step]) -> Bool {
        let stairKeywords = ["階段", "stairs", "stairway", "steps", "段差"]
        for step in steps {
            let text = step.instructions.lowercased()
            if stairKeywords.contains(where: { text.contains($0) }) {
                return true
            }
        }
        return false
    }

    private func routingErrorDescription(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "オフライン"
            case .timedOut:
                return "タイムアウト"
            default:
                return "通信エラー"
            }
        }

        let ns = error as NSError
        if ns.domain == MKError.errorDomain {
            switch MKError.Code(rawValue: UInt(ns.code)) {
            case .directionsNotFound:
                return "方向案内対象外"
            case .serverFailure:
                return "地図サーバ障害"
            case .loadingThrottled:
                return "地図API制限"
            default:
                return "MapKitエラー"
            }
        }

        return "不明なエラー"
    }

    private func smoothRouteCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let thinned = thinCoordinates(coordinates, minimumDistanceMeters: 8)
        let smoothed = movingAverageCoordinates(thinned, windowRadius: 1)
        guard smoothed.count > 1 else { return thinned }

        var stabilized = smoothed
        stabilized[0] = thinned[0]
        stabilized[stabilized.count - 1] = thinned[thinned.count - 1]
        return stabilized
    }

    private func thinCoordinates(_ coordinates: [CLLocationCoordinate2D], minimumDistanceMeters: Double) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }

        var output: [CLLocationCoordinate2D] = [coordinates[0]]
        for index in 1..<(coordinates.count - 1) {
            if output[output.count - 1].distance(to: coordinates[index]) >= minimumDistanceMeters {
                output.append(coordinates[index])
            }
        }
        output.append(coordinates[coordinates.count - 1])
        return output
    }

    private func movingAverageCoordinates(_ coordinates: [CLLocationCoordinate2D], windowRadius: Int) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2, windowRadius > 0 else { return coordinates }

        var output = coordinates
        let maxIndex = coordinates.count - 1

        for index in 1..<maxIndex {
            let lower = max(0, index - windowRadius)
            let upper = min(maxIndex, index + windowRadius)
            let slice = coordinates[lower...upper]
            let lat = slice.map(\.latitude).reduce(0, +) / Double(slice.count)
            let lon = slice.map(\.longitude).reduce(0, +) / Double(slice.count)
            output[index] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return output
    }

    private func offsetCandidates(
        from base: CLLocationCoordinate2D,
        distances: [Double] = [20, 40, 80]
    ) -> [CLLocationCoordinate2D] {
        let bearings: [Double] = [0, 90, 180, 270]
        return distances.flatMap { distance in
            bearings.map { bearing in
                base.offset(meters: distance, bearingDegrees: bearing)
            }
        }
    }
}

struct SnappedDestination {
    let coordinate: CLLocationCoordinate2D
    let didSnap: Bool
}

final class DestinationRoadSnapper {
    func snap(_ coordinate: CLLocationCoordinate2D) async -> SnappedDestination {
        let radiusCandidates: [CLLocationDistance] = [120, 220]

        for radius in radiusCandidates {
            if let snapped = await nearestAddressCoordinate(around: coordinate, radiusMeters: radius) {
                return SnappedDestination(coordinate: snapped, didSnap: true)
            }
        }

        return SnappedDestination(coordinate: coordinate, didSnap: false)
    }

    private func nearestAddressCoordinate(
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async -> CLLocationCoordinate2D? {
        let queries = ["道路", "road", "street", "address"]
        var nearest: CLLocationCoordinate2D?
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: origin,
                latitudinalMeters: radiusMeters * 2,
                longitudinalMeters: radiusMeters * 2
            )
            request.resultTypes = [.address]

            do {
                let response = try await MKLocalSearch(request: request).start()
                for item in response.mapItems {
                    let candidate = item.placemark.coordinate
                    let distance = origin.distance(to: candidate)
                    if distance < nearestDistance {
                        nearestDistance = distance
                        nearest = candidate
                    }
                }
            } catch {
                continue
            }
        }

        guard let nearest else { return nil }
        return nearestDistance <= radiusMeters ? nearest : nil
    }
}

private extension CLLocationCoordinate2D {
    func offset(meters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let radians = bearingDegrees * .pi / 180.0
        let latDelta = (meters * cos(radians)) / 111_320.0
        let lonScale = max(cos(latitude * .pi / 180.0), 0.01)
        let lonDelta = (meters * sin(radians)) / (111_320.0 * lonScale)
        return CLLocationCoordinate2D(latitude: latitude + latDelta, longitude: longitude + lonDelta)
    }
}
