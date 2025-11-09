import SwiftUI

struct DestinationSearchView: View {
    @ObservedObject var viewModel: DestinationSearchViewModel
    var onStartNavigation: (Harbor) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("目的地を検索（マリーナ・港・座標）", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                List {
                    Section("おすすめルート") {
                        ForEach(viewModel.results) { harbor in
                            Button {
                                viewModel.select(harbor)
                                onStartNavigation(harbor)
                            } label: {
                                DestinationRow(harbor: harbor)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("目的地設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DestinationRow: View {
    let harbor: Harbor

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(harbor.name)
                    .font(.headline)
                Text("設備: \(harbor.facilities.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f nm", harbor.distance))
                    .font(.headline)
                Text("ETA \(harbor.etaMinutes)分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
