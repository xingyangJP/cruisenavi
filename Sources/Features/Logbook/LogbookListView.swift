import SwiftUI

struct LogbookListView: View {
    let logs: [VoyageLog]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("クルーズログ")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                ForEach(logs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.startTime, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Text(log.weatherSummary)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.1f nm", log.distance))
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(String(format: "%.1f kn", log.averageSpeed))
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}
