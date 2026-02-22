import SwiftUI

struct WeatherCardView: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 180, height: 180)
                .blur(radius: 2)
                .offset(x: 170, y: -40)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("天気")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(snapshot.timestamp, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: iconName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.condition)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(rainText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                }

                HStack(spacing: 10) {
                    metricPill("風速", String(format: "%.1f m/s", snapshot.windSpeed), icon: "wind")
                    metricPill("風向", snapshot.windCompass, icon: "location.north.line")
                    metricPill("路面", String(format: "%.1f", snapshot.roadRisk), icon: "exclamationmark.road.lane")
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }

    private var rainText: String {
        if let minutes = snapshot.precipitationStartMinutes {
            if (30...60).contains(minutes) {
                return "雨回避アラート: \(minutes)分後に雨予測"
            }
            return "\(minutes)分後に雨が降る見込み"
        }
        return "当面は降雨予測なし"
    }

    private var iconName: String {
        switch snapshot.condition {
        case let text where text.contains("雨"):
            return "cloud.rain.fill"
        case let text where text.contains("雪"):
            return "cloud.snow.fill"
        case let text where text.contains("霧"):
            return "cloud.fog.fill"
        case let text where text.contains("晴れ時々くもり"):
            return "cloud.sun.fill"
        case let text where text.contains("くもり"):
            return "cloud.fill"
        default:
            return "sun.max.fill"
        }
    }

    private var gradientColors: [Color] {
        switch snapshot.condition {
        case let text where text.contains("雨"):
            return [Color(red: 0.19, green: 0.31, blue: 0.51), Color(red: 0.08, green: 0.11, blue: 0.24)]
        case let text where text.contains("雪"):
            return [Color(red: 0.47, green: 0.65, blue: 0.78), Color(red: 0.22, green: 0.33, blue: 0.46)]
        case let text where text.contains("晴れ時々くもり"):
            return [Color(red: 0.40, green: 0.62, blue: 0.88), Color(red: 0.27, green: 0.42, blue: 0.76)]
        case let text where text.contains("くもり"):
            return [Color(red: 0.42, green: 0.51, blue: 0.63), Color(red: 0.23, green: 0.30, blue: 0.40)]
        default:
            return [Color(red: 0.31, green: 0.66, blue: 0.98), Color(red: 0.23, green: 0.44, blue: 0.88)]
        }
    }

    private func metricPill(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(title) \(value)")
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.18), in: Capsule())
    }
}
