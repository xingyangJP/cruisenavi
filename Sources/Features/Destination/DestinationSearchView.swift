import SwiftUI

struct DestinationSearchView: View {
    @StateObject private var viewModel: DestinationSearchViewModel
    @StateObject private var favoriteStore = FavoriteDestinationStore.shared
    @State private var selectedRouteMode: CyclingRouteMode = .flat
    var onStartNavigation: (Harbor, CyclingRouteMode) -> Void

    init(locationService: LocationService, onStartNavigation: @escaping (Harbor, CyclingRouteMode) -> Void) {
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

                Picker("ルートモード", selection: $selectedRouteMode) {
                    ForEach(CyclingRouteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Text(selectedRouteMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                List {
                    if viewModel.isSearching {
                        ProgressView("検索中...")
                    }
                    let favoriteHarbors = favoriteStore.harborList(origin: viewModel.origin)
                    if !favoriteHarbors.isEmpty {
                        Section("お気に入り") {
                            ForEach(favoriteHarbors) { harbor in
                                DestinationRow(
                                    harbor: harbor,
                                    isFavorite: true,
                                    onSelect: {
                                        favoriteStore.markUsed(harbor)
                                        viewModel.select(harbor)
                                        onStartNavigation(harbor, selectedRouteMode)
                                    },
                                    onToggleFavorite: {
                                        favoriteStore.toggle(harbor)
                                    }
                                )
                            }
                        }
                    }
                    if viewModel.results.isEmpty {
                        Text(viewModel.emptyStateMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        Section(viewModel.resultSectionTitle) {
                            ForEach(viewModel.results) { harbor in
                                DestinationRow(
                                    harbor: harbor,
                                    isFavorite: favoriteStore.isFavorite(harbor),
                                    onSelect: {
                                        if favoriteStore.isFavorite(harbor) {
                                            favoriteStore.markUsed(harbor)
                                        }
                                        viewModel.select(harbor)
                                        onStartNavigation(harbor, selectedRouteMode)
                                    },
                                    onToggleFavorite: {
                                        favoriteStore.toggle(harbor)
                                    }
                                )
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
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(harbor.name)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Text("カテゴリ: \(harbor.facilities.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f km", harbor.distance))
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        Text("ETA \(harbor.etaMinutes)分")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
    }
}
