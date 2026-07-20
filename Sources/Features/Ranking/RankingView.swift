import SwiftUI

struct RankingView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMetric: RankingMetric = .longestDistance
    @State private var selectedScope: RankingScope = .personal
    @State private var showingNicknameSheet = false
    @State private var worldBoard: WorldRankingBoard?
    @State private var worldRows: [WorldRankingEntry] = []
    @State private var pinnedOwnRow: WorldRankingEntry?
    @State private var neighborhoodRows: [WorldRankingEntry] = []
    @State private var hasMoreWorld = false
    @State private var isLoadingMoreWorld = false
    @State private var isLoadingWorld = false
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false

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
                        SegmentedTabs(
                            items: [
                                (RankingMetric.longestDistance, L10n.tr("距離")),
                                (RankingMetric.topSpeed, L10n.tr("速度"))
                            ],
                            selection: $selectedMetric
                        )
                        .accessibilityLabel(Text("ランキング指標"))

                        SegmentedTabs(
                            items: [
                                (RankingScope.personal, L10n.tr("自分")),
                                (RankingScope.world, L10n.tr("世界"))
                            ],
                            selection: $selectedScope
                        )
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
        if viewModel.rankingRequiresSignIn {
            signInOptInCard
        } else if viewModel.rankingProfile == nil {
            nicknameOptInCard
        } else {
            worldLeaderboard
        }
    }

    // Sign in with Apple gate. The live board requires `request.auth != null` (firestore.rules), so
    // identity is established here before any nickname registration, fetch, or submit (plan §5.4).
    private var signInOptInCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.aquaTeal)
                Text("世界ランキングに参加")
                    .font(.headline)
                    .foregroundStyle(Color.citrusPrimaryText)
                Text("Appleでサインインすると、世界ランキングに参加できます。位置情報の走行記録は公開されません。")
                    .font(.subheadline)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .multilineTextAlignment(.center)

                if let signInError {
                    Text(signInError)
                        .font(.caption)
                        .foregroundStyle(Color.citrusOrange)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await signIn() }
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "applelogo")
                        }
                        Text("Appleでサインイン")
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSigningIn)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func signIn() async {
        signInError = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            _ = try await viewModel.signInForWorldRanking()
        } catch {
            signInError = L10n.tr("サインインできませんでした。時間をおいて再度お試しください。")
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
        // Only shown while the board is still synthesized (mock). Live Firestore data hides it.
        if worldBoard?.isMockData == true {
            mockDataBanner
        }

        if selectedMetric == .topSpeed {
            Text("安全第一。速度記録は下り区間などを含みます。無理な走行はしないでください。")
                .font(.caption)
                .foregroundStyle(Color.citrusOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }

        if let board = worldBoard {
            worldBoardCard(board)
            if !board.isMockData {
                Text("記録は自動審査の完了後にランキングへ公開されます。")
                    .font(.caption2)
                    .foregroundStyle(Color.citrusSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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

        accountManagementFooter
    }

    // App Store 5.1.1(v): a signed-in user must be able to delete their account in-app. Deletes the
    // remote leaderboard entries + Firebase user, then clears the local profile.
    private var accountManagementFooter: some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            if isDeleting {
                ProgressView()
            } else {
                Text("ランキングのアカウントを削除")
                    .font(.caption)
            }
        }
        .disabled(isDeleting)
        .padding(.top, 4)
        .confirmationDialog(
            "ランキングのアカウントを削除しますか?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("あなたの記録とアカウント情報が削除されます。この操作は取り消せません。")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await viewModel.deleteWorldRankingAccount()
            worldBoard = nil
            worldRows = []
            pinnedOwnRow = nil
            neighborhoodRows = []
            hasMoreWorld = false
        } catch {
            signInError = L10n.tr("アカウントを削除できませんでした。再度サインインしてお試しください。")
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
        let userInList = worldRows.contains { $0.isCurrentUser }

        GlassCard {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(worldRows) { entry in
                    worldRow(entry)
                        .onAppear {
                            // Infinite scroll: reaching the last loaded row pulls the next page.
                            if entry.id == worldRows.last?.id {
                                Task { await loadMoreWorld() }
                            }
                        }
                    if entry.id != worldRows.last?.id {
                        Divider().overlay(Color.citrusBorder)
                    }
                }

                if isLoadingMoreWorld {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.tr("さらに読み込み中..."))
                            .font(.caption)
                            .foregroundStyle(Color.citrusSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                // Neighborhood block: while the user's real position is not yet scrolled into
                // view, show the rows directly around them (±2 by rank, own row highlighted) so
                // they can see exactly who to beat next. Rows already loaded above are filtered
                // out, so the block shrinks and finally disappears as the scroll catches up.
                if !userInList {
                    let block = neighborhoodBlock(excludingLoadedIn: worldRows)
                    let fallback = pinnedOwnRow.map { [$0] } ?? []
                    let rows = block.isEmpty ? fallback : block
                    if !rows.isEmpty {
                        Divider().overlay(Color.citrusBorder)
                        Text("···")
                            .font(.caption.bold())
                            .foregroundStyle(Color.citrusSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                        ForEach(rows) { entry in
                            worldRow(entry)
                            if entry.id != rows.last?.id {
                                Divider().overlay(Color.citrusBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Neighborhood rows not already loaded above, additionally unique by id within the block
    /// itself — the service seeds the own row from the LOCAL best, so a diverging verified server
    /// value could otherwise surface the same account twice, and duplicate `ForEach` ids are
    /// undefined behavior in SwiftUI.
    private func neighborhoodBlock(excludingLoadedIn loaded: [WorldRankingEntry]) -> [WorldRankingEntry] {
        var seen = Set(loaded.map(\.id))
        return neighborhoodRows.filter { seen.insert($0.id).inserted }
    }

    /// Appends the next verified page after the last loaded row. `hasMoreWorld` turns false when a
    /// page comes back short, so a fully-scrolled board stops issuing queries.
    private func loadMoreWorld() async {
        guard hasMoreWorld, !isLoadingMoreWorld, let last = worldRows.last else { return }
        // Capture the metric this page belongs to: the call runs in an unstructured `Task {}`
        // (from `onAppear`), so switching metric/scope does NOT cancel it. Without the post-await
        // re-check below, a stale page would be appended to the NEW metric's rows.
        let metric = selectedMetric
        isLoadingMoreWorld = true
        defer { isLoadingMoreWorld = false }
        let pageSize = 50
        let more = await viewModel.fetchMoreWorldEntries(metric: metric, after: last, limit: pageSize)
        guard metric == selectedMetric, selectedScope == .world, !Task.isCancelled else { return }
        // Defensive de-dup: a cursor page can re-include ids if the board shifted between pages.
        let known = Set(worldRows.map(\.id))
        worldRows.append(contentsOf: more.filter { !known.contains($0.id) })
        hasMoreWorld = more.count == pageSize
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
        // Capture the metric this load is for. `.task(id:)` cancels a superseded run, but the
        // Firestore fetches are not cancellation-aware and complete anyway — without the post-await
        // guards a stale run resuming late would clobber the new metric's board with old rows.
        let metric = selectedMetric
        isLoadingWorld = true
        // Publish the current personal best (idempotent) so an already-opted-in user's existing best
        // is submitted even without a new PR ride, then read the board back.
        await viewModel.submitCurrentPersonalBests()
        let board = await viewModel.worldRankingBoard(for: metric)
        guard metric == selectedMetric, selectedScope == .world, !Task.isCancelled else { return }
        worldBoard = board

        // Split the fetched page into the in-order list and the appended out-of-order own row
        // (`fetchLeaderboard` pins the user's row at the END, with its real rank, when they are
        // not inside the page — detectable as rank != position).
        var rows = board.entries
        if let lastRow = rows.last, lastRow.isCurrentUser, lastRow.rank != rows.count {
            pinnedOwnRow = lastRow
            rows.removeLast()
        } else {
            pinnedOwnRow = board.currentUserEntry
        }
        worldRows = rows
        // The live first page is `topN` (100) rows — a full page means more may follow. The mock
        // returns everything at once, so it never paginates.
        hasMoreWorld = !board.isMockData && rows.count >= 100
        isLoadingMoreWorld = false
        isLoadingWorld = false

        // Load the ±2 neighborhood around the user's own rank for the pinned block. Only needed
        // when the user is outside the loaded page; degrades to the bare own row on failure.
        if let own = pinnedOwnRow, !rows.contains(where: { $0.isCurrentUser }) {
            let neighborhood = await viewModel.fetchWorldNeighborhood(metric: metric, around: own)
            guard metric == selectedMetric, selectedScope == .world, !Task.isCancelled else { return }
            neighborhoodRows = neighborhood
        } else {
            neighborhoodRows = []
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

/// High-contrast replacement for the system segmented `Picker`, whose selected state was hard to
/// tell apart on the app's light gradient canvas: the selected segment gets a filled teal capsule
/// with white bold text, unselected segments stay muted.
private struct SegmentedTabs<Value: Hashable>: View {
    let items: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { value, label in
                let isSelected = selection == value
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = value
                    }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .white : Color.citrusSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.aquaTeal : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.citrusBorder))
    }
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
