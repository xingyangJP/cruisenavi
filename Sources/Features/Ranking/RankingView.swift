import SwiftUI

struct RankingView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetric: RankingMetric = .longestDistance
    @State private var selectedScope: RankingScope = .personal
    @State private var showingNicknameSheet = false
    @State private var worldBoard: WorldRankingBoard?
    @State private var isLoadingWorld = false

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
                            worldContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                .task(id: worldReloadKey) {
                    if selectedScope == .world {
                        await loadWorldBoard()
                    }
                }
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

    @ViewBuilder
    private var worldContent: some View {
        if viewModel.rankingProfile == nil {
            nicknameOptInCard
        } else {
            worldLeaderboard
        }
    }

    // Opt-in prompt shown until the user registers a nickname. World data is never fetched or
    // submitted before this step (plan §5.4 / §8.1 — explicit opt-in).
    private var nicknameOptInCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.aquaTeal)
                Text("世界ランキングに参加")
                    .font(.headline)
                    .foregroundStyle(Color.citrusPrimaryText)
                Text("ニックネームを登録すると、世界ランキングに参加できます。")
                    .font(.subheadline)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .multilineTextAlignment(.center)

                Button {
                    showingNicknameSheet = true
                } label: {
                    Text("参加する")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.aquaTeal, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $showingNicknameSheet) {
            NicknameRegistrationSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var worldLeaderboard: some View {
        mockDataBanner

        if selectedMetric == .topSpeed {
            Text("安全第一。速度記録は下り区間などを含みます。無理な走行はしないでください。")
                .font(.caption)
                .foregroundStyle(Color.citrusOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }

        if let board = worldBoard {
            worldBoardCard(board)
        } else {
            GlassCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("読み込み中...")
                        .font(.subheadline)
                        .foregroundStyle(Color.citrusSecondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    // Prominent, always-on notice that the leaderboard is synthesized (isMockData) — live ranking
    // is not yet connected (plan §5.5).
    private var mockDataBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption)
                .foregroundStyle(Color.citrusAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("モックデータ / 本番未接続")
                    .font(.caption.bold())
                    .foregroundStyle(Color.citrusAmber)
                Text("これはサンプルデータです。本番の世界ランキングは未接続です。")
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

    @ViewBuilder
    private func worldBoardCard(_ board: WorldRankingBoard) -> some View {
        let topEntries = Array(board.entries.prefix(10))
        let userInTop = topEntries.contains { $0.isCurrentUser }

        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(topEntries) { entry in
                    worldRow(entry)
                    if entry.id != topEntries.last?.id {
                        Divider().overlay(Color.citrusBorder)
                    }
                }

                // Pin the user's own row if they fall outside the visible top entries.
                if !userInTop, let userEntry = board.currentUserEntry {
                    Divider().overlay(Color.citrusBorder)
                    Text("···")
                        .font(.caption.bold())
                        .foregroundStyle(Color.citrusSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                    worldRow(userEntry)
                }
            }
        }
    }

    @ViewBuilder
    private func worldRow(_ entry: WorldRankingEntry) -> some View {
        HStack(spacing: 12) {
            Text(L10n.format("%d位", entry.rank))
                .font(.subheadline.bold())
                .foregroundStyle(Color.citrusPrimaryText)
                .frame(minWidth: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.nickname)
                        .font(.headline)
                        .foregroundStyle(Color.citrusPrimaryText)
                    if entry.isCurrentUser {
                        Text("あなた")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.aquaTeal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.7), in: Capsule())
                    }
                }
                if let region = entry.region, !region.isEmpty {
                    Text(region)
                        .font(.caption)
                        .foregroundStyle(Color.citrusSecondaryText)
                }
            }

            Spacer()

            Text(formattedValue(entry.value))
                .font(.subheadline.bold())
                .foregroundStyle(Color.citrusPrimaryText)
        }
        .padding(.horizontal, entry.isCurrentUser ? 10 : 0)
        .padding(.vertical, entry.isCurrentUser ? 8 : 0)
        .background(
            entry.isCurrentUser
                ? Color.aquaTeal.opacity(0.16)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func loadWorldBoard() async {
        guard viewModel.rankingProfile != nil else { return }
        isLoadingWorld = true
        worldBoard = await viewModel.worldRankingBoard(for: selectedMetric)
        isLoadingWorld = false
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

    /// Distinct value that changes whenever the world board must be refetched: scope, metric, or
    /// whether the user has a profile yet (so the board loads immediately after registration).
    private var worldReloadKey: String {
        "\(selectedScope)-\(selectedMetric)-\(viewModel.rankingProfile != nil)"
    }
}

private enum RankingScope {
    case personal
    case world
}

/// Opt-in nickname registration sheet. Inline validation reuses the pure `NicknameValidator`;
/// error messages come from `NicknameValidationError.message` (localized). No uniqueness check —
/// nicknames are non-unique by design (plan §5.4).
private struct NicknameRegistrationSheet: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.citrusCanvasStart, Color.citrusCanvasEnd],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ニックネーム")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.citrusSecondaryText)

                                TextField("ニックネームを入力してください", text: $nickname)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .font(.headline)
                                    .foregroundStyle(Color.citrusPrimaryText)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                                    .onChange(of: nickname) { _ in
                                        errorMessage = nil
                                    }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(Color.citrusOrange)
                                }

                                Text(L10n.format("%d〜%d文字。英数字・かな・漢字が使えます。", NicknameValidator.minLength, NicknameValidator.maxLength))
                                    .font(.caption)
                                    .foregroundStyle(Color.citrusSecondaryText)
                            }
                        }

                        Button {
                            register()
                        } label: {
                            Text("登録する")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.aquaTeal, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("ニックネームを登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Color.citrusPrimaryText)
                }
            }
        }
    }

    private func register() {
        switch viewModel.registerRankingNickname(nickname) {
        case .success:
            dismiss()
        case .failure(let error):
            errorMessage = error.message
        }
    }
}
