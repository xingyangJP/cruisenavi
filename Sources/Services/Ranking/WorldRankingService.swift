import Foundation

/// One row of a world (global) leaderboard.
struct WorldRankingEntry: Identifiable, Equatable {
    /// The account id that owns this row (`RankingIdentityProviding.accountId` for the current user,
    /// a synthetic id for mock competitors). Doubles as `Identifiable.id`.
    let id: String
    let rank: Int
    let nickname: String
    let value: Double          // km (longestDistance) or km/h (topSpeed)
    let region: String?        // optional locale/region label for disambiguation (§5.4)
    /// True for the row that belongs to the signed-in user, so the UI can pin / highlight it.
    let isCurrentUser: Bool
}

/// A ranked world leaderboard for a single metric.
struct WorldRankingBoard: Equatable {
    let metric: RankingMetric
    let entries: [WorldRankingEntry]
    /// True while the data is synthesized locally (no live backend). The UI must surface this.
    let isMockData: Bool

    /// The current user's own row, if present.
    var currentUserEntry: WorldRankingEntry? {
        entries.first { $0.isCurrentUser }
    }

    /// The current user's global rank, if present.
    var currentUserRank: Int? {
        currentUserEntry?.rank
    }
}

/// Client seam for the world ranking. Phase B ships only `MockWorldRankingService`; the live
/// Firestore-backed implementation (RANKING_MODE_PLAN.md §5.3/§5.5) will conform to this same
/// protocol later. Async so the mock and the future networked impl share one call shape.
protocol WorldRankingService {
    /// Fetch a leaderboard for `metric`, merging in the current user's personal best.
    /// - Parameters:
    ///   - metric: distance or speed board to build.
    ///   - userBest: the user's best value from the on-device personal `RankingService`
    ///     (0 or negative means "no eligible record yet").
    ///   - accountId: stable id from `RankingIdentityProviding`, used to identify/pin the user row.
    ///   - nickname: the user's display name from their `RankingProfile`.
    func fetchLeaderboard(
        metric: RankingMetric,
        userBest: Double,
        accountId: String,
        nickname: String
    ) async -> WorldRankingBoard

    /// Submit the user's personal best (self-best updates only). No-op / logs for the mock.
    func submitBest(
        metric: RankingMetric,
        value: Double,
        accountId: String,
        nickname: String
    ) async
}
