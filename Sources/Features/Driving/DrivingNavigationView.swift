import SwiftUI
import MapKit

struct DrivingNavigationView: View {
    let destination: Harbor
    let routeSummary: RouteSummary
    let onExit: () -> Void
    let onChangeDestination: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()
                if let coordinates = routeSummary.routeCoordinates, coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.aquaTeal, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            VStack(spacing: 16) {
                DrivingInstructionCard(route: routeSummary, destination: destination, onChange: onChangeDestination)
                    .padding(.horizontal, 16)

                Spacer()

                HStack(spacing: 12) {
                    ControlButton(icon: "xmark.circle.fill", title: "終了", color: .red.opacity(0.9), action: onExit)
                    ControlButton(icon: "ellipsis.circle", title: "メニュー", color: .white.opacity(0.4), action: onChangeDestination)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraPosition = .region(routeSummary.mapRegion)
        }
    }
}

private struct DrivingInstructionCard: View {
    let route: RouteSummary
    let destination: Harbor
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(route.primaryInstruction)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Spacer()
                Text(String(format: "%.1f km", route.nextDistance))
                    .font(.title3.bold())
            }
            Text(route.secondaryInstruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Label("\(route.totalDistance, specifier: "%.1f") nm", systemImage: "location.north.circle")
                Spacer()
                Label("ETA \(route.etaString)", systemImage: "clock")
                Spacer()
                Button("目的地再設定", action: onChange)
                    .font(.footnote.bold())
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .shadow(radius: 25, y: 16)
    }
}

private struct ControlButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(color, in: Capsule())
            .foregroundStyle(color == .red.opacity(0.9) ? .white : .black)
        }
    }
}

extension RouteSummary {
    static let sample = RouteSummary(
        totalDistance: 12.4,
        etaMinutes: 42,
        primaryInstruction: "800m 先、右へ",
        secondaryInstruction: "横浜ベイサイドマリーナ方面",
        nextDistance: 0.8,
        routeCoordinates: MockRouteProvider.tokyoBayRoute
    )
}
