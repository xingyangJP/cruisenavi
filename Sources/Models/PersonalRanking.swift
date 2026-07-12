import Foundation

enum RankingMetric: CaseIterable {
    case longestDistance
    case topSpeed
}

struct PersonalRankingEntry: Identifiable, Equatable {
    let id: UUID          // VoyageLog.id
    let rank: Int
    let value: Double     // km or km/h
    let date: Date
    let mode: VoyageLogMode
}

struct PersonalRankingBoard {
    let metric: RankingMetric
    let best: PersonalRankingEntry?
    let entries: [PersonalRankingEntry]
}
