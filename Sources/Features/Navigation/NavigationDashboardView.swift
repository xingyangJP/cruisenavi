import SwiftUI

struct NavigationDashboardView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("航行マップ")
                            .font(.title2.bold())
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.6), .cyan.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 220)
                            .overlay(alignment: .topTrailing) {
                                Text("デモマップ")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                    }
                }

                NavigationHUDView(
                    eta: viewModel.etaText,
                    distance: viewModel.distance,
                    speed: viewModel.speed,
                    heading: viewModel.heading,
                    warning: viewModel.warningMessage
                )

                TideWeatherCardView(snapshot: viewModel.weatherSnapshot)

                LogbookListView(logs: viewModel.voyageLogs)

                PortsListView(harbors: viewModel.harbors)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .background(Color.deepSeaBlue.opacity(0.95))
    }
}

struct NavigationHUDView: View {
    let eta: String
    let distance: Double
    let speed: Double
    let heading: String
    let warning: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Label("ETA \(eta)", systemImage: "clock")
                    Label(String(format: "%.1f nm", distance), systemImage: "arrow.triangle.turn.up.right.diamond")
                    Label(String(format: "%.1f kn", speed), systemImage: "speedometer")
                    Label(heading, systemImage: "safari")
                }
                .font(.headline)
                .foregroundStyle(.white)

                if let warning {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("警告 \(warning)")
                }
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.15))
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
            .overlay(alignment: .topLeading) {
                content
                    .padding(24)
            }
    }
}

private extension Color {
    static let deepSeaBlue = Color(red: 0.0, green: 0.2, blue: 0.31)
}
