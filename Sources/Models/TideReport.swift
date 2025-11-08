import Foundation

struct TideReport: Identifiable {
    let id = UUID()
    let stationId: String
    let timestamp: Date
    let height: Double
    let state: String
}
