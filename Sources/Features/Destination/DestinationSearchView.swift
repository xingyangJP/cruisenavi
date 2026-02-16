import SwiftUI

struct DestinationSearchView: View {
    @StateObject private var viewModel: DestinationSearchViewModel
    var onStartNavigation: (Harbor) -> Void

    init(locationService: LocationService, onStartNavigation: @escaping (Harbor) -> Void) {
        _viewModel = StateObject(wrappedValue: DestinationSearchViewModel(locationService: locationService))
        self.onStartNavigation = onStartNavigation
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("目的地を検索（施設名・住所・座標）", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                List {
                    if viewModel.isSearching {
                        ProgressView("検索中...")
                    }
                    if viewModel.results.isEmpty {
                        Text("現在地から100km圏内に候補がありません")
                            .foregroundStyle(.secondary)
                    } else {
                        Section("現在地から100km圏内") {
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
                Text("カテゴリ: \(harbor.facilities.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f km", harbor.distance))
                    .font(.headline)
                Text("ETA \(harbor.etaMinutes)分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
