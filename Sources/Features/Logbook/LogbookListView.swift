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
                return "直近24時間"
            case .week:
                return "直近7日"
            case .month:
                return "直近30日"
            }
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
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Text(scope.title)
                    .font(.caption)
                    .foregroundStyle(Color.citrusSecondaryText)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "ライド回数", value: "\(filteredLogs.count) 回")
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
            return "\(hours)時間\(minutes)分"
        }
        return "\(minutes)分"
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(log.startTime.formatted(date: .complete, time: .shortened))
                        .font(.headline)

                    HStack(spacing: 16) {
                        miniStat(title: "距離", value: String(format: "%.1f km", log.distance))
                        miniStat(title: "平均時速", value: String(format: "%.1f km/h", log.averageSpeed))
                    }

                    HStack(spacing: 16) {
                        miniStat(title: "時間", value: durationString(log.duration))
                        miniStat(title: "ルート点", value: "\(log.routePoints.count)")
                    }

                    if let status = healthStatus {
                        Text("Health: \(status.text)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

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
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("ライド詳細")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
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
            return "\(hours)時間\(minutes)分"
        }
        return "\(minutes)分"
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
