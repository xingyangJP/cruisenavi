import Foundation
import FirebaseCore
import FirebaseFirestore

/// Stable Firestore path segment per metric. These strings are COLLECTION IDS in Firestore and
/// MUST match `isAllowedMetric()` in the deployed firestore.rules and `ALLOWED_METRICS` in
/// functions/src/index.ts (`longestDistance` / `topSpeed`). Never change them after go-live.
///
/// NOTE: RANKING_GOLIVE_CHECKLIST §3.0's template mapped `.longestDistance -> "distance"`, which is
/// STALE and contradicts the deployed rules/Function — the deployed ids win.
extension RankingMetric {
    var firestoreMetricId: String {
        switch self {
        case .longestDistance: return "longestDistance"
        case .topSpeed:        return "topSpeed"
        }
    }
}

/// Live Firestore-backed world ranking. Conforms to the SAME `WorldRankingService` protocol the
/// mock uses, so it drops into `NavigationDashboardViewModel` unchanged.
///
/// Data model (RANKING_MODE_PLAN.md §5.3, firestore.rules, functions/src/index.ts):
///   - public entry:     leaderboards/{metricId}/entries/{uid}
///   - private integrity: rankingSubmissions/{uid}/rides/{rideId}
///
/// Anti-cheat contract baked in here:
///   * READS query ONLY `verified == true` rows (rules reject any unfiltered list), so until the
///     §4.4 Cloud Function stamps a row it is invisible — the board can legitimately be EMPTY.
///   * WRITES never set `verified` / `region` / `country` (server-only). We write the integrity
///     record FIRST so the Function finds it when the entry write fires the trigger.
///   * Every call degrades gracefully (logs in DEBUG, never crashes) on network/permission error.
struct FirestoreWorldRankingService: WorldRankingService {
    private let explicitDB: Firestore?
    private let topN: Int

    /// `db` is resolved LAZILY (not in init) so constructing this service at app launch never calls
    /// `Firestore.firestore()` before `FirebaseApp.configure()` — if the backend isn't provisioned
    /// (no GoogleService-Info.plist / configure skipped), `db` is nil and every call degrades to a
    /// safe no-op / own-row-only board instead of crashing (graceful-degradation contract).
    init(db: Firestore? = nil, topN: Int = 100) {
        self.explicitDB = db
        self.topN = topN
    }

    private var db: Firestore? {
        if let explicitDB { return explicitDB }
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    private func entries(for metric: RankingMetric, in db: Firestore) -> CollectionReference {
        db.collection("leaderboards")
            .document(metric.firestoreMetricId)
            .collection("entries")
    }

    // MARK: - Read

    func fetchLeaderboard(
        metric: RankingMetric,
        userBest: Double,
        accountId: String,
        nickname: String
    ) async -> WorldRankingBoard {
        guard let db else { return degradedBoard(metric: metric, userBest: userBest, accountId: accountId, nickname: nickname) }
        let col = entries(for: metric, in: db)
        do {
            // Top-N VERIFIED rows, ordered by value desc. The `verified == true` filter is MANDATORY:
            // rules reject a list query that is not constrained to it. Served by the composite index
            // (verified ASC, value DESC) in firestore.indexes.json.
            let snap = try await col
                .whereField("verified", isEqualTo: true)
                .order(by: "value", descending: true)
                .limit(to: topN)
                .getDocuments()

            var rows: [WorldRankingEntry] = snap.documents.enumerated().map { index, doc in
                let d = doc.data()
                return WorldRankingEntry(
                    id: doc.documentID,
                    rank: index + 1,
                    nickname: d["displayName"] as? String ?? "",
                    value: d["value"] as? Double ?? 0,
                    region: d["region"] as? String,
                    isCurrentUser: doc.documentID == accountId
                )
            }

            // Ensure the user's own row is present/pinned even when outside Top-N (or still pending
            // verification, so not yet in the verified list). Owner may read their own doc via rules.
            if !rows.contains(where: { $0.isCurrentUser }), !accountId.isEmpty {
                let ownRank = try? await rankOfVerified(greaterThan: userBest, in: col)
                rows.append(
                    WorldRankingEntry(
                        id: accountId,
                        rank: ownRank ?? (rows.count + 1),
                        nickname: nickname,
                        value: max(userBest, 0),
                        region: nil,
                        isCurrentUser: true
                    )
                )
            }

            return WorldRankingBoard(metric: metric, entries: rows, isMockData: false)
        } catch {
            #if DEBUG
            print("FirestoreWorldRankingService.fetch failed: \(error)")
            #endif
            return degradedBoard(metric: metric, userBest: userBest, accountId: accountId, nickname: nickname)
        }
    }

    /// Degrade gracefully: show only the user's own local best, never crash the screen. Used when
    /// Firebase isn't configured or the network/permission read failed.
    private func degradedBoard(metric: RankingMetric, userBest: Double, accountId: String, nickname: String) -> WorldRankingBoard {
        let ownRow = WorldRankingEntry(
            id: accountId, rank: 1, nickname: nickname,
            value: max(userBest, 0), region: nil, isCurrentUser: true
        )
        return WorldRankingBoard(
            metric: metric,
            entries: accountId.isEmpty ? [] : [ownRow],
            isMockData: false
        )
    }

    /// Infinite-scroll continuation: verified rows strictly after (`last.value`, `last.id`),
    /// value descending. The explicit `documentID` (descending) order matches the implicit
    /// `__name__` direction of the (verified ASC, value DESC) composite index, so this reuses the
    /// same index and satisfies the same `verified == true` list rule as the first page. The id
    /// component makes the cursor exact across value ties (a bare value cursor would skip them).
    func fetchMoreEntries(
        metric: RankingMetric,
        after last: WorldRankingEntry,
        limit: Int,
        accountId: String
    ) async -> [WorldRankingEntry] {
        guard let db, limit > 0 else { return [] }
        do {
            let snap = try await entries(for: metric, in: db)
                .whereField("verified", isEqualTo: true)
                .order(by: "value", descending: true)
                .order(by: FieldPath.documentID(), descending: true)
                .start(after: [last.value, last.id])
                .limit(to: limit)
                .getDocuments()
            return snap.documents.enumerated().map { index, doc in
                let d = doc.data()
                return WorldRankingEntry(
                    id: doc.documentID,
                    rank: last.rank + index + 1,
                    nickname: d["displayName"] as? String ?? "",
                    value: d["value"] as? Double ?? 0,
                    region: d["region"] as? String,
                    isCurrentUser: doc.documentID == accountId
                )
            }
        } catch {
            #if DEBUG
            print("FirestoreWorldRankingService.fetchMore failed: \(error)")
            #endif
            return []
        }
    }

    /// Neighborhood block: the rows ranked just above own (next-larger values — fetched with the
    /// exact REVERSE ordering of the page query, which Firestore serves from the same composite
    /// index) plus the rows just below (reuses `fetchMoreEntries`). Ranks are derived from
    /// `own.rank` by offset. Either half failing degrades to the other half + the own row.
    func fetchNeighborhood(
        metric: RankingMetric,
        around own: WorldRankingEntry,
        radius: Int,
        accountId: String
    ) async -> [WorldRankingEntry] {
        guard let db, radius > 0 else { return [own] }
        var rows: [WorldRankingEntry] = [own]
        do {
            let above = try await entries(for: metric, in: db)
                .whereField("verified", isEqualTo: true)
                .order(by: "value")
                .order(by: FieldPath.documentID())
                .start(after: [own.value, own.id])
                .limit(to: radius)
                .getDocuments()
            // Skip the user's own SERVER document: `own` is seeded from the LOCAL best, so when the
            // verified server value differs (e.g. a backfilled ride excluded from the local best)
            // the query would re-include the same account id and duplicate the row.
            for (index, doc) in above.documents.filter({ $0.documentID != own.id }).enumerated() {
                let d = doc.data()
                rows.append(WorldRankingEntry(
                    id: doc.documentID,
                    rank: max(own.rank - index - 1, 1),
                    nickname: d["displayName"] as? String ?? "",
                    value: d["value"] as? Double ?? 0,
                    region: d["region"] as? String,
                    isCurrentUser: doc.documentID == accountId
                ))
            }
        } catch {
            #if DEBUG
            print("FirestoreWorldRankingService.fetchNeighborhood(above) failed: \(error)")
            #endif
        }
        rows.append(contentsOf: await fetchMoreEntries(
            metric: metric,
            after: own,
            limit: radius,
            accountId: accountId
        ).filter { $0.id != own.id })
        return rows.sorted { $0.rank < $1.rank }
    }

    /// "1 + number of VERIFIED entries strictly greater than value". One count aggregation query,
    /// constrained to `verified == true` so it satisfies the list rules (and reuses the same index).
    private func rankOfVerified(greaterThan value: Double, in col: CollectionReference) async throws -> Int {
        let greater = try await col
            .whereField("verified", isEqualTo: true)
            .whereField("value", isGreaterThan: value)
            .count
            .getAggregation(source: .server)
        return greater.count.intValue + 1
    }

    // MARK: - Write — self-best updates only (cost minimization, §5.3)

    @discardableResult
    func submitBest(
        metric: RankingMetric,
        value: Double,
        accountId: String,
        nickname: String,
        rideId: String,
        integrity: RideIntegrityResult,
        achievedAt: Date
    ) async -> Bool {
        guard let db else { return false }
        guard !accountId.isEmpty, value > 0, !rideId.isEmpty, !rideId.contains("/") else { return false }

        let achievedTimestamp = Timestamp(date: achievedAt)

        // 1. Private integrity record FIRST. The §4.4 Function requires this doc to exist under the
        //    same uid/rideId (and matching metric) or it rejects the entry. Path ownership carries
        //    the uid; the client cannot read others' records (rules). `verified` is NOT here — it is
        //    stamped only on the public entry.
        let integrityRef = db.collection("rankingSubmissions")
            .document(accountId)
            .collection("rides")
            .document(rideId)
        let integrityPayload: [String: Any] = [
            "metric": metric.firestoreMetricId,
            "value": value,
            "effectiveDistance": integrity.effectiveDistance,
            "maxSustainedSpeed": integrity.maxSustainedSpeed,
            "validSampleRatio": integrity.validSampleRatio,
            "isRankingEligible": integrity.isRankingEligible,
            "activityBreakdown": integrity.activityBreakdown,
            "achievedAt": achievedTimestamp
        ]
        do {
            try await integrityRef.setData(integrityPayload, merge: true)
        } catch {
            #if DEBUG
            print("FirestoreWorldRankingService.submit integrity write failed: \(error)")
            #endif
            return false // without the integrity record the entry can never verify — don't write it.
        }

        // 2. Public entry. EXACTLY the 5 client-writable keys (rules enforce hasOnly). merge:true so
        //    a repeat best never clobbers the Function-set verified/region/country on the existing doc.
        let entryRef = entries(for: metric, in: db).document(accountId) // doc id == uid (owner-only write)
        let entryPayload: [String: Any] = [
            "userId": accountId,
            "displayName": nickname,
            "value": value,
            "achievedAt": achievedTimestamp,
            "rideId": rideId
        ]
        do {
            try await entryRef.setData(entryPayload, merge: true)
        } catch {
            #if DEBUG
            print("FirestoreWorldRankingService.submit entry write failed: \(error)")
            #endif
            return false
        }
        return true
    }
}
