import SwiftUI

struct PortsListView: View {
    let harbors: [Harbor]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("港湾情報")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                ForEach(harbors) { harbor in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(harbor.name)
                            .font(.headline)
                        Text("設備: \(harbor.facilities.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("制限: \(harbor.restrictions.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.pink.opacity(0.8))
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
