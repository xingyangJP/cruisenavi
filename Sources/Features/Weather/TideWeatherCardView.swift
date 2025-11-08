import SwiftUI

struct TideWeatherCardView: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("潮汐・気象")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 20) {
                    TideGauge(height: snapshot.tideHeight, state: snapshot.tideState)
                    Divider().frame(height: 80).overlay(Color.white.opacity(0.3))
                    WeatherStack(snapshot: snapshot)
                }
            }
        }
    }
}

private struct TideGauge: View {
    let height: Double
    let state: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "%.1f m", height))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan)
            Text(state)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct WeatherStack: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(format: "風速 %.1f kt", snapshot.windSpeed), systemImage: "wind")
            Label("風向 \(snapshot.windCompass)", systemImage: "location.north.line")
            Label(String(format: "波高 %.1f m", snapshot.waveHeight), systemImage: "water.waves")
        }
        .font(.subheadline)
        .foregroundStyle(.white)
    }
}
