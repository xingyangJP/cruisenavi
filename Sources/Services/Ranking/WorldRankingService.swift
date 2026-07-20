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
    ///
    /// The live Firestore implementation writes TWO documents (RANKING_GOLIVE_CHECKLIST §6 +
    /// functions/src/index.ts): first the private on-device integrity record at
    /// `rankingSubmissions/{uid}/rides/{rideId}` (so the §4.4 Cloud Function can cross-check the
    /// public value), then the public entry at `leaderboards/{metricId}/entries/{uid}`. The entry
    /// stays invisible on the public board until the Function stamps `verified == true`.
    /// - Parameters:
    ///   - rideId: a stable, single-segment id for this submission (no "/"). Must match the id of
    ///     the integrity record written for the SAME metric.
    ///   - integrity: the on-device anti-cheat summary the server validates the value against.
    ///   - achievedAt: when the ride happened (bounded to a sane window by rules + the Function).
    /// - Returns: true when the submission was handed to the backend (both writes succeeded for the
    ///   live implementation; trivially true for the mock). Callers that need at-least-once
    ///   semantics (e.g. the one-time legacy backfill) key their "done" flag off this.
    @discardableResult
    func submitBest(
        metric: RankingMetric,
        value: Double,
        accountId: String,
        nickname: String,
        rideId: String,
        integrity: RideIntegrityResult,
        achievedAt: Date
    ) async -> Bool

    /// Fetch the next page of verified rows strictly after `last` (cursor = value + entry id),
    /// ordered by value descending — the infinite-scroll continuation of `fetchLeaderboard`.
    /// Returned ranks continue from `last.rank`. An empty array means the board is exhausted
    /// (the mock always returns [] — its board is fully synthesized in the first page).
    func fetchMoreEntries(
        metric: RankingMetric,
        after last: WorldRankingEntry,
        limit: Int,
        accountId: String
    ) async -> [WorldRankingEntry]

    /// The rows immediately around the user's own entry (±`radius` by rank, own row included),
    /// sorted by rank — the "neighborhood block" shown when the user sits far below the visible
    /// top of the board, so they can see who is directly above/below them.
    func fetchNeighborhood(
        metric: RankingMetric,
        around own: WorldRankingEntry,
        radius: Int,
        accountId: String
    ) async -> [WorldRankingEntry]
}
