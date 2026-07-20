import Foundation

/// Offline, deterministic mock of `WorldRankingService`. It SYNTHESIZES a plausible global
/// leaderboard from a fixed table of fake competitors, merges in the current user's own best value
/// (as computed by the on-device personal `RankingService`), ranks everyone, and marks the user's
/// row so the UI can pin/highlight it.
///
/// There is NO networking of any kind here — this is a placeholder until the real Firestore-backed
/// service is connected (RANKING_MODE_PLAN.md §5.5). `isMockData` is always `true`.
struct MockWorldRankingService: WorldRankingService {
    /// A synthetic competitor. `seed` makes ranks fully deterministic and stable across runs.
    struct MockCompetitor {
        let seed: Int
        let nickname: String
        let value: Double
        let region: String
    }

    private let competitorsByMetric: [RankingMetric: [MockCompetitor]]

    init(competitorsByMetric: [RankingMetric: [MockCompetitor]]? = nil) {
        self.competitorsByMetric = competitorsByMetric ?? Self.defaultCompetitors
    }

    func fetchLeaderboard(
        metric: RankingMetric,
        userBest: Double,
        accountId: String,
        nickname: String
    ) async -> WorldRankingBoard {
        board(metric: metric, userBest: userBest, accountId: accountId, nickname: nickname)
    }

    func submitBest(
        metric: RankingMetric,
        value: Double,
        accountId: String,
        nickname: String,
        rideId: String,
        integrity: RideIntegrityResult,
        achievedAt: Date
    ) async -> Bool {
        // Mock: nothing is transmitted. The live FirestoreWorldRankingService writes the private
        // integrity record + the public entry (RANKING_GOLIVE_CHECKLIST §6).
        return true
    }

    func fetchMoreEntries(
        metric: RankingMetric,
        after last: WorldRankingEntry,
        limit: Int,
        accountId: String
    ) async -> [WorldRankingEntry] {
        // Mock: the synthesized board is returned whole by `fetchLeaderboard`; there is no more.
        return []
    }

    func fetchNeighborhood(
        metric: RankingMetric,
        around own: WorldRankingEntry,
        radius: Int,
        accountId: String
    ) async -> [WorldRankingEntry] {
        // Rebuild the same deterministic board and slice around the own row.
        let entries = board(
            metric: metric,
            userBest: own.value,
            accountId: own.id,
            nickname: own.nickname
        ).entries
        guard let index = entries.firstIndex(where: { $0.isCurrentUser }) else { return [own] }
        let lower = max(index - radius, 0)
        let upper = min(index + radius, entries.count - 1)
        return Array(entries[lower...upper])
    }

    /// Synchronous core so tests can assert without async plumbing. Deterministic.
    func board(
        metric: RankingMetric,
        userBest: Double,
        accountId: String,
        nickname: String
    ) -> WorldRankingBoard {
        let competitors = competitorsByMetric[metric] ?? []

        // Rows to rank: fake competitors + the user's own row (always present so it can be pinned).
        struct Row {
            let id: String
            let nickname: String
            let value: Double
            let region: String?
            let isCurrentUser: Bool
            let seed: Int          // deterministic tie-break key
        }

        var rows: [Row] = competitors.map { competitor in
            Row(
                id: "mock-\(competitor.seed)",
                nickname: competitor.nickname,
                value: competitor.value,
                region: competitor.region,
                isCurrentUser: false,
                // Competitor seeds are shifted so the user (seed 0) wins value ties deterministically.
                seed: competitor.seed + 1
            )
        }

        rows.append(
            Row(
                id: accountId,
                nickname: nickname,
                value: max(userBest, 0),
                region: nil,
                isCurrentUser: true,
                seed: 0
            )
        )

        // Sort by value descending; tie-break by seed ascending (user's seed 0 wins ties).
        let sorted = rows.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.seed < rhs.seed
        }

        let entries = sorted.enumerated().map { index, row in
            WorldRankingEntry(
                id: row.id,
                rank: index + 1,
                nickname: row.nickname,
                value: row.value,
                region: row.region,
                isCurrentUser: row.isCurrentUser
            )
        }

        return WorldRankingBoard(metric: metric, entries: entries, isMockData: true)
    }

    // MARK: - Synthetic data

    /// Fixed, plausible competitor table. Distances in km, speeds in km/h (all under the 90km/h
    /// plausibility cap from §4.2). Obviously synthetic names so it never reads as real data.
    static let defaultCompetitors: [RankingMetric: [MockCompetitor]] = [
        .longestDistance: [
            MockCompetitor(seed: 1, nickname: "Kaito", value: 214.8, region: "JP"),
            MockCompetitor(seed: 2, nickname: "Marta", value: 198.3, region: "ES"),
            MockCompetitor(seed: 3, nickname: "Liang", value: 187.6, region: "CN"),
            MockCompetitor(seed: 4, nickname: "Noah", value: 176.2, region: "US"),
            MockCompetitor(seed: 5, nickname: "Amelie", value: 168.9, region: "FR"),
            MockCompetitor(seed: 6, nickname: "Yuki", value: 152.4, region: "JP"),
            MockCompetitor(seed: 7, nickname: "Oskar", value: 141.7, region: "DE"),
            MockCompetitor(seed: 8, nickname: "Priya", value: 133.5, region: "IN"),
            MockCompetitor(seed: 9, nickname: "Diego", value: 121.0, region: "BR"),
            MockCompetitor(seed: 10, nickname: "Sofia", value: 108.6, region: "IT"),
            MockCompetitor(seed: 11, nickname: "Emma", value: 96.2, region: "GB"),
            MockCompetitor(seed: 12, nickname: "Haru", value: 84.9, region: "JP")
        ],
        .topSpeed: [
            MockCompetitor(seed: 1, nickname: "Kaito", value: 78.4, region: "JP"),
            MockCompetitor(seed: 2, nickname: "Marta", value: 74.1, region: "ES"),
            MockCompetitor(seed: 3, nickname: "Liang", value: 71.9, region: "CN"),
            MockCompetitor(seed: 4, nickname: "Noah", value: 69.3, region: "US"),
            MockCompetitor(seed: 5, nickname: "Amelie", value: 66.8, region: "FR"),
            MockCompetitor(seed: 6, nickname: "Yuki", value: 63.2, region: "JP"),
            MockCompetitor(seed: 7, nickname: "Oskar", value: 60.5, region: "DE"),
            MockCompetitor(seed: 8, nickname: "Priya", value: 57.7, region: "IN"),
            MockCompetitor(seed: 9, nickname: "Diego", value: 54.0, region: "BR"),
            MockCompetitor(seed: 10, nickname: "Sofia", value: 50.6, region: "IT"),
            MockCompetitor(seed: 11, nickname: "Emma", value: 47.1, region: "GB"),
            MockCompetitor(seed: 12, nickname: "Haru", value: 43.8, region: "JP")
        ]
    ]
}
