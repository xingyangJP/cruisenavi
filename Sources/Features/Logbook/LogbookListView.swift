import SwiftUI
import MapKit

struct LogbookListView: View {
    enum PeriodScope: String, CaseIterable, Identifiable {
        case day = "日"
        case week = "週"
        case month = "月"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day:
                return L10n.tr("直近24時間")
            case .week:
                return L10n.tr("直近7日")
            case .month:
                return L10n.tr("直近30日")
            }
        }

        var shortLabel: String {
            L10n.tr(rawValue)
        }
    }

    let logs: [VoyageLog]
    let healthStatuses: [UUID: NavigationDashboardViewModel.RideLogHealthStatus]

    @State private var scope: PeriodScope = .week
    @State private var selectedLog: VoyageLog?

    private var filteredLogs: [VoyageLog] {
        let now = Date()
        let threshold: Date
        switch scope {
        case .day:
            threshold = now.addingTimeInterval(-24 * 60 * 60)
        case .week:
            threshold = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month:
            threshold = now.addingTimeInterval(-30 * 24 * 60 * 60)
        }
        return logs.filter { log in
            log.startTime >= threshold && log.startTime <= now
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private var totalDistance: Double {
        filteredLogs.reduce(0) { $0 + $1.distance }
    }

    private var totalDuration: TimeInterval {
        filteredLogs.reduce(0) { $0 + $1.duration }
    }

    private var averageSpeed: Double {
        guard totalDuration > 0 else { return 0 }
        let distanceMeters = totalDistance * 1000.0
        return (distanceMeters / totalDuration) * 3.6
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("ライドログ")
                        .font(.title3.bold())
                        .foregroundStyle(Color.citrusPrimaryText)
                    Spacer()
                    Picker("期間", selection: $scope) {
                        ForEach(PeriodScope.allCases) { option in
                            Text(option.shortLabel).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Text(scope.title)
                    .font(.caption)
                    .foregroundStyle(Color.citrusSecondaryText)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "ライド回数", value: L10n.format("%d 回", filteredLogs.count))
                    StatTile(title: "総距離", value: String(format: "%.1f km", totalDistance))
                    StatTile(title: "総時間", value: durationString(totalDuration))
                    StatTile(title: "平均時速", value: String(format: "%.1f km/h", averageSpeed))
                }

                if filteredLogs.isEmpty {
                    Text("この期間のライドログはありません")
                        .font(.footnote)
                        .foregroundStyle(Color.citrusSecondaryText)
                } else {
                    ForEach(filteredLogs.prefix(6)) { log in
                        Button {
                            selectedLog = log
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline)
                                        .foregroundStyle(Color.citrusPrimaryText)
                                    Text(log.mode.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(log.mode == .freeRide ? Color.aquaTeal : Color.citrusOrange)
                                    Text(log.weatherSummary)
                                        .font(.footnote)
                                        .foregroundStyle(Color.citrusSecondaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(String(format: "%.1f km", log.distance))
                                        .font(.headline)
                                        .foregroundStyle(Color.citrusPrimaryText)
                                    Text(String(format: "%.1f km/h", log.averageSpeed))
                                        .font(.footnote)
                                        .foregroundStyle(Color.citrusSecondaryText)
                                    if let status = healthStatuses[log.id] {
                                        Text(status.text)
                                            .font(.caption2)
                                            .foregroundStyle(statusColor(status))
                                    }
                                    if log.isRankingEligible == false {
                                        Text(L10n.tr("ランキング対象外"))
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.citrusSecondaryText)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedLog) { log in
            LogbookDetailSheet(log: log, healthStatus: healthStatuses[log.id])
        }
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return L10n.format("%d時間%d分", hours, minutes)
        }
        return L10n.format("%d分", minutes)
    }

    private func statusColor(_ status: NavigationDashboardViewModel.RideLogHealthStatus) -> Color {
        switch status {
        case .syncing:
            return .citrusSecondaryText
        case .synced:
            return .green
        case .skipped:
            return .orange
        case .failed:
            return .red
        }
    }
}

private struct LogbookDetailSheet: View {
    struct RideStory {
        let title: String
        let subtitle: String
        let highlights: [String]
        let shareText: String
    }

    let log: VoyageLog
    let healthStatus: NavigationDashboardViewModel.RideLogHealthStatus?

    private var mapRegion: MKCoordinateRegion {
        let points = log.routePoints
        guard points.count > 1 else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        let minLat = points.map(\.latitude).min() ?? 0
        let maxLat = points.map(\.latitude).max() ?? 0
        let minLon = points.map(\.longitude).min() ?? 0
        let maxLon = points.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var rideStory: RideStory {
        let rideType: String = {
            switch log.distance {
            case ..<10:
                return L10n.tr("ショート")
            case ..<30:
                return L10n.tr("ミドル")
            default:
                return L10n.tr("ロング")
            }
        }()

        let title = L10n.tr("今日のライドストーリー")
        let subtitle = L10n.format("%@ / %@ライド %.1fkm・平均%.1fkm/h", log.mode.title, rideType, log.distance, log.averageSpeed)
        let highlights = [
            L10n.format("モード %@", log.mode.title),
            L10n.format("走行時間 %@", durationString(log.duration)),
            L10n.format("天候 %@", log.weatherSummary),
            L10n.format("ルート点 %d", log.routePoints.count)
        ]
        let shareText = [
            L10n.tr("RideLane ライドストーリー"),
            log.startTime.formatted(date: .abbreviated, time: .shortened),
            subtitle,
            L10n.format("天候: %@", log.weatherSummary)
        ].joined(separator: "\n")
        return RideStory(title: title, subtitle: subtitle, highlights: highlights, shareText: shareText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(log.startTime.formatted(date: .complete, time: .shortened))
                        .font(.headline)
                        .foregroundStyle(Color.citrusPrimaryText)

                    Text(log.mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(log.mode == .freeRide ? Color.aquaTeal : Color.citrusOrange)

                    HStack(spacing: 16) {
                        miniStat(title: "距離", value: String(format: "%.1f km", log.distance))
                        miniStat(title: "平均時速", value: String(format: "%.1f km/h", log.averageSpeed))
                    }

                    HStack(spacing: 16) {
                        miniStat(title: "時間", value: durationString(log.duration))
                        miniStat(title: "ルート点", value: "\(log.routePoints.count)")
                    }

                    if let status = healthStatus {
                        Text(L10n.format("Health: %@", status.text))
                            .font(.footnote)
                            .foregroundStyle(Color.citrusSecondaryText)
                    }

                    rankingEligibilityLine

                    rideStoryCard(rideStory)

                    if log.routePoints.count > 1 {
                        Map(initialPosition: .region(mapRegion)) {
                            MapPolyline(coordinates: log.routePoints)
                                .stroke(Color.aquaTeal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Text("ルート詳細データがありません")
                            .font(.footnote)
                            .foregroundStyle(Color.citrusSecondaryText)
                    }
                }
                .padding()
            }
            .navigationTitle("ライド詳細")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Ranking-eligibility verdict for this ride. Rides analyzed before the integrity feature
    /// (all fields nil) show as "not evaluated" so exclusion is never implied without evidence.
    @ViewBuilder
    private var rankingEligibilityLine: some View {
        switch log.isRankingEligible {
        case .some(true):
            Text(L10n.tr("ランキング判定: 対象"))
                .font(.footnote)
                .foregroundStyle(.green)
        case .some(false):
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("ランキング判定: 対象外（乗り物移動を検知）"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
                if let ratio = log.validSampleRatio {
                    Text(L10n.format("有効サンプル率 %d%%", Int(ratio * 100)))
                        .font(.caption2)
                        .foregroundStyle(Color.citrusSecondaryText)
                }
                if let automotive = log.activityBreakdown?[RideActivityKind.automotive.rawValue],
                   automotive > 0 {
                    Text(L10n.format("乗り物と判定された区間 %d%%", Int(automotive * 100)))
                        .font(.caption2)
                        .foregroundStyle(Color.citrusSecondaryText)
                }
            }
        case .none:
            Text(L10n.tr("ランキング判定: 未判定"))
                .font(.footnote)
                .foregroundStyle(Color.citrusSecondaryText)
        }
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.citrusSecondaryText)
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.citrusPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.citrusBorder)
        )
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return L10n.format("%d時間%d分", hours, minutes)
        }
        return L10n.format("%d分", minutes)
    }

    @ViewBuilder
    private func rideStoryCard(_ story: RideStory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("ライドストーリー", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                ShareLink(item: story.shareText) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                        .foregroundStyle(Color(red: 0.09, green: 0.3, blue: 0.47))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.85), in: Capsule())
                }
            }

            Text(story.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(story.subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))

            ForEach(story.highlights, id: \.self) { highlight in
                Text("• \(highlight)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.5, blue: 0.88),
                    Color(red: 0.12, green: 0.34, blue: 0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.citrusSecondaryText)
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.citrusPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.citrusBorder)
        )
    }
}
