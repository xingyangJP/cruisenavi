import SwiftUI

struct PortsListView: View {
    let harbors: [Harbor]
    @State private var isExpanded = false

    private var visibleHarbors: [Harbor] {
        if isExpanded { return harbors }
        return Array(harbors.prefix(10))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("スポット情報")
                    .font(.title3.bold())
                    .foregroundStyle(Color.citrusPrimaryText)

                ForEach(visibleHarbors) { harbor in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(harbor.name)
                            .font(.headline)
                            .foregroundStyle(Color.citrusPrimaryText)
                        Text(L10n.format("カテゴリ: %@", L10n.localizedList(harbor.facilities)))
                            .font(.footnote)
                            .foregroundStyle(Color.citrusSecondaryText)
                        Text(L10n.format("注意事項: %@", L10n.localizedList(harbor.restrictions)))
                            .font(.footnote)
                            .foregroundStyle(Color.citrusOrange.opacity(0.9))
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }

                if harbors.count > 10 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "閉じる" : "もっと見る")
                            .font(.footnote.bold())
                            .foregroundStyle(Color.citrusPrimaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.citrusCard, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.citrusBorder)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        L10n.tr(isExpanded ? "スポット情報を閉じる" : "スポット情報をもっと見る")
                    )
                }
            }
        }
    }
}
