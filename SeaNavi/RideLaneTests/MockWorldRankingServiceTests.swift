import XCTest
@testable import RideLane

final class MockWorldRankingServiceTests: XCTestCase {
    private let service = MockWorldRankingService()
    private let accountId = "test-account-123"
    private let nickname = "Tester"

    func testEntriesAreRankedDescendingWithSequentialRanks() {
        let board = service.board(metric: .longestDistance, userBest: 100, accountId: accountId, nickname: nickname)
        let values = board.entries.map(\.value)
        XCTAssertEqual(values, values.sorted(by: >))
        XCTAssertEqual(board.entries.map(\.rank), Array(1...board.entries.count))
        XCTAssertTrue(board.isMockData)
    }

    func testUserBestIsMergedAndPinned() throws {
        let board = service.board(metric: .longestDistance, userBest: 100, accountId: accountId, nickname: nickname)
        let userRows = board.entries.filter { $0.isCurrentUser }
        XCTAssertEqual(userRows.count, 1)
        let user = try XCTUnwrap(board.currentUserEntry)
        XCTAssertEqual(user.id, accountId)
        XCTAssertEqual(user.nickname, nickname)
        XCTAssertEqual(user.value, 100)
    }

    func testUserRankReflectsInsertionPosition() {
        // Default distance competitors bracket 108.6 (rank position) and 96.2.
        // A userBest of 100 places the user between them.
        let board = service.board(metric: .longestDistance, userBest: 100, accountId: accountId, nickname: nickname)
        let above = board.entries.first { $0.value == 108.6 }
        let below = board.entries.first { $0.value == 96.2 }
        let user = board.currentUserEntry
        XCTAssertNotNil(user)
        XCTAssertNotNil(above)
        XCTAssertNotNil(below)
        XCTAssertEqual(user!.rank, above!.rank + 1)
        XCTAssertEqual(below!.rank, user!.rank + 1)
    }

    func testUserTopBestRanksFirst() {
        let board = service.board(metric: .topSpeed, userBest: 999, accountId: accountId, nickname: nickname)
        XCTAssertEqual(board.currentUserRank, 1)
        XCTAssertEqual(board.entries.first?.isCurrentUser, true)
    }

    func testZeroUserBestPinnedLast() {
        let board = service.board(metric: .topSpeed, userBest: 0, accountId: accountId, nickname: nickname)
        XCTAssertEqual(board.currentUserRank, board.entries.count)
        XCTAssertEqual(board.entries.last?.isCurrentUser, true)
    }

    func testValueTieUserWinsDeterministically() {
        // userBest equals a competitor value (63.2 exists in topSpeed defaults).
        let board = service.board(metric: .topSpeed, userBest: 63.2, accountId: accountId, nickname: nickname)
        let tied = board.entries.filter { $0.value == 63.2 }.sorted { $0.rank < $1.rank }
        XCTAssertEqual(tied.count, 2)
        XCTAssertTrue(tied.first!.isCurrentUser, "User should win value ties deterministically")
    }

    func testDeterministicAcrossCalls() {
        let a = service.board(metric: .longestDistance, userBest: 130, accountId: accountId, nickname: nickname)
        let b = service.board(metric: .longestDistance, userBest: 130, accountId: accountId, nickname: nickname)
        XCTAssertEqual(a.entries, b.entries)
    }

    func testCompetitorCountPlusUser() {
        let board = service.board(metric: .longestDistance, userBest: 50, accountId: accountId, nickname: nickname)
        let competitors = MockWorldRankingService.defaultCompetitors[.longestDistance]!
        XCTAssertEqual(board.entries.count, competitors.count + 1)
    }
}
