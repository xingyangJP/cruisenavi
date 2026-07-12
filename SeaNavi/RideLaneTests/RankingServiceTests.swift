import XCTest
@testable import RideLane

final class RankingServiceTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func log(
        distance: Double,
        maxSustainedSpeed: Double? = nil,
        effectiveDistance: Double? = nil,
        isRankingEligible: Bool? = true,
        daysAgo: Double = 0,
        mode: VoyageLogMode = .freeRide
    ) -> VoyageLog {
        let start = base.addingTimeInterval(-daysAgo * 86_400)
        return VoyageLog(
            id: UUID(),
            startTime: start,
            endTime: start.addingTimeInterval(3600),
            routePoints: [],
            distance: distance,
            averageSpeed: 20,
            weatherSummary: "",
            mode: mode,
            maxSustainedSpeed: maxSustainedSpeed,
            effectiveDistance: effectiveDistance,
            validSampleRatio: isRankingEligible == true ? 1.0 : 0.2,
            isRankingEligible: isRankingEligible,
            activityBreakdown: nil
        )
    }

    func testDistanceSortingAndRanking() {
        let logs = [
            log(distance: 10, effectiveDistance: 10, daysAgo: 1),
            log(distance: 30, effectiveDistance: 30, daysAgo: 2),
            log(distance: 20, effectiveDistance: 20, daysAgo: 3)
        ]
        let board = RankingService.board(for: .longestDistance, logs: logs)
        XCTAssertEqual(board.entries.map(\.value), [30, 20, 10])
        XCTAssertEqual(board.entries.map(\.rank), [1, 2, 3])
        XCTAssertEqual(board.best?.value, 30)
    }

    func testBestEqualsMaxValue() {
        let logs = [
            log(distance: 5, effectiveDistance: 5),
            log(distance: 42, effectiveDistance: 42, daysAgo: 1)
        ]
        let board = RankingService.board(for: .longestDistance, logs: logs)
        XCTAssertEqual(board.best?.value, 42)
    }

    func testTopSpeedExcludesIneligibleAndLegacy() {
        let eligible = log(distance: 12, maxSustainedSpeed: 35, effectiveDistance: 12, isRankingEligible: true)
        let ineligible = log(distance: 12, maxSustainedSpeed: 80, effectiveDistance: 12, isRankingEligible: false, daysAgo: 1)
        let legacy = log(distance: 25, maxSustainedSpeed: nil, effectiveDistance: nil, isRankingEligible: nil, daysAgo: 2)
        let board = RankingService.board(for: .topSpeed, logs: [eligible, ineligible, legacy])
        XCTAssertEqual(board.entries.count, 1)
        XCTAssertEqual(board.entries.first?.value, 35)
    }

    func testLegacyIncludedInDistanceUsingRawDistance() {
        let legacy = log(distance: 25, maxSustainedSpeed: nil, effectiveDistance: nil, isRankingEligible: nil)
        let board = RankingService.board(for: .longestDistance, logs: [legacy])
        XCTAssertEqual(board.entries.count, 1)
        XCTAssertEqual(board.entries.first?.value, 25)
    }

    func testEffectiveDistancePreferredOverRaw() {
        // Raw distance 40 but effective (anti-cheat) distance 18 => value uses 18.
        let log = log(distance: 40, effectiveDistance: 18, isRankingEligible: true)
        let board = RankingService.board(for: .longestDistance, logs: [log])
        XCTAssertEqual(board.entries.first?.value, 18)
    }

    func testLimitCapsEntriesButRanksAreGlobal() {
        let logs = [
            log(distance: 10, effectiveDistance: 10, daysAgo: 1),
            log(distance: 30, effectiveDistance: 30, daysAgo: 2),
            log(distance: 20, effectiveDistance: 20, daysAgo: 3)
        ]
        let board = RankingService.board(for: .longestDistance, logs: logs, limit: 2)
        XCTAssertEqual(board.entries.count, 2)
        XCTAssertEqual(board.entries.map(\.rank), [1, 2])
        XCTAssertEqual(board.entries.map(\.value), [30, 20])
    }

    func testTieBreakNewerDateFirst() {
        let older = log(distance: 20, effectiveDistance: 20, daysAgo: 5)
        let newer = log(distance: 20, effectiveDistance: 20, daysAgo: 1)
        let board = RankingService.board(for: .longestDistance, logs: [older, newer])
        XCTAssertEqual(board.entries.first?.id, newer.id)
        XCTAssertEqual(board.entries.map(\.rank), [1, 2])
    }
}
