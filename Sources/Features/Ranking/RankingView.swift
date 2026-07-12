import SwiftUI

struct RankingView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetric: RankingMetric = .longestDistance
    @State private var selectedScope: RankingScope = .personal

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.citrusCanvasStart,
                        Color.citrusCanvasEnd
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Picker("", selection: $selectedMetric) {
                            Text("距離").tag(RankingMetric.longestDistance)
                            Text("速度").tag(RankingMetric.topSpeed)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(Text("ランキング指標"))

                        Picker("", selection: $selectedScope) {
                            Text("自分").tag(RankingScope.personal)
                            Text("世界").tag(RankingScope.world)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(Text("表示範囲"))

                        switch selectedScope {
                        case .personal:
                            personalContent
                        case .world:
                            worldPlaceholder
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("ランキング")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Color.citrusPrimaryText)
                }
            }
        }
    }

    // MARK: - Personal scope

    @ViewBuilder
    private var personalContent: some View {
        let board = viewModel.personalRankingBoard(for: selectedMetric)

        if let excludedNote = vehicleExclusionNote {
            excludedBanner(excludedNote)
        }

        heroCard(board)

        if selectedMetric == .topSpeed {
            Text("安全第一。速度記録は下り区間などを含みます。無理な走行はしないでください。")
                .font(.caption)
                .foregroundStyle(Color.citrusOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }

        if !board.entries.isEmpty {
            historyCard(board)
        }
    }

    @ViewBuilder
    private func heroCard(_ board: PersonalRankingBoard) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(heroEyebrow, systemImage: "trophy.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color.citrusSecondaryText)

                if let best = board.best {
                    Text(formattedValue(best.value))
                        .font(.title2.bold())
                        .foregroundStyle(Color.citrusPrimaryText)
                    Text(best.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(Color.citrusSecondaryText)
                    modeBadge(best.mode)
                } else {
                    Text("まだ記録がありません")
                        .font(.subheadline)
                        .foregroundStyle(Color.citrusSecondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func historyCard(_ board: PersonalRankingBoard) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(board.entries) { entry in
                    HStack(spacing: 12) {
                        Text(L10n.format("%d位", entry.rank))
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.citrusPrimaryText)
                            .frame(minWidth: 44, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(formattedValue(entry.value))
                                .font(.headline)
                                .foregroundStyle(Color.citrusPrimaryText)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Color.citrusSecondaryText)
                        }

                        Spacer()

                        modeBadge(entry.mode)
                    }

                    if entry.id != board.entries.last?.id {
                        Divider()
                            .overlay(Color.citrusBorder)
                    }
                }
            }
        }
    }

    private func modeBadge(_ mode: VoyageLogMode) -> some View {
        Text(mode.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(mode == .freeRide ? Color.aquaTeal : Color.citrusOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.55), in: Capsule())
    }

    @ViewBuilder
    private func excludedBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Color.citrusOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("記録対象外")
                    .font(.caption.bold())
                    .foregroundStyle(Color.citrusOrange)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.citrusSecondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.citrusBorder)
        )
    }

    // MARK: - World scope

    private var worldPlaceholder: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.aquaTeal)
                Text("準備中")
                    .font(.headline)
                    .foregroundStyle(Color.citrusPrimaryText)
                Text("世界ランキングは今後のアップデートで対応予定です。")
                    .font(.subheadline)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers

    private var heroEyebrow: String {
        switch selectedMetric {
        case .longestDistance:
            return L10n.tr("自己ベスト")
        case .topSpeed:
            return L10n.tr("自己最速")
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch selectedMetric {
        case .longestDistance:
            return L10n.format("%.1fkm", value)
        case .topSpeed:
            return L10n.format("%.1fkm/h", value)
        }
    }

    /// Surfaces the transparency note when a recent ride was excluded from ranking because
    /// vehicle travel (or too much invalid data) was detected. Kept subtle per plan §7.
    private var vehicleExclusionNote: String? {
        let hasExcludedRide = viewModel.voyageLogs.contains { $0.isRankingEligible == false }
        return hasExcludedRide ? L10n.tr("乗り物移動を検知したため一部を記録対象外にしました") : nil
    }
}

private enum RankingScope {
    case personal
    case world
}
