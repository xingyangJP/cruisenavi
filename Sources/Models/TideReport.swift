import Foundation

struct TideReport: Identifiable {
    let id = UUID()
    let timestamp: Date
    let height: Double
    let state: String
    let source: String
}
