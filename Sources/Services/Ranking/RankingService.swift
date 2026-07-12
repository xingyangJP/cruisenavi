import Foundation

/// Pure, deterministic personal-ranking aggregation over on-device `VoyageLog`s. No networking.
enum RankingService {
    static func board(
        for metric: RankingMetric,
        logs: [VoyageLog],
        limit: Int = 20
    ) -> PersonalRankingBoard {
        // 1 + 2. Eligibility filter and per-metric value extraction.
        let valued: [(log: VoyageLog, value: Double)] = logs.compactMap { log in
            switch metric {
            case .longestDistance:
                // Legacy logs (isRankingEligible == nil) predate integrity and are included;
                // logs explicitly marked ineligible (false) are excluded.
                if log.isRankingEligible == false { return nil }
                let value = log.effectiveDistance ?? log.distance
                guard value > 0 else { return nil }
                return (log, value)
            case .topSpeed:
                // Sustained speed did not exist for legacy logs, so nil maxSustainedSpeed is excluded;
                // explicitly ineligible logs are excluded too.
                if log.isRankingEligible == false { return nil }
                guard let value = log.maxSustainedSpeed, value > 0 else { return nil }
                return (log, value)
            }
        }

        // 3. Sort descending by value, tie-break by date descending (newer first).
        let sorted = valued.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.log.startTime > rhs.log.startTime
        }

        // 4. Assign 1-based ranks.
        let ranked = sorted.enumerated().map { index, element in
            PersonalRankingEntry(
                id: element.log.id,
                rank: index + 1,
                value: element.value,
                date: element.log.startTime,
                mode: element.log.mode
            )
        }

        // 5 + 6.
        return PersonalRankingBoard(
            metric: metric,
            best: ranked.first,
            entries: Array(ranked.prefix(limit))
        )
    }
}
