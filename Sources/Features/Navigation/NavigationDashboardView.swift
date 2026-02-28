import SwiftUI
import Combine
import WebKit

struct NavigationDashboardView: View {
    @ObservedObject var viewModel: NavigationDashboardViewModel
    @State private var showDestinationSheet = false
    @State private var showDrivingMode = false
    @State private var showRoutePreview = false
    @State private var showWalkthrough = false
    @State private var walkthroughIndex = 0
    @State private var selectedLegalDocument: LegalDocumentPage?
    @AppStorage("onboarding.walkthrough.completed") private var walkthroughCompleted = false

    private let walkthroughSteps: [OnboardingWalkthroughStep] = [
        .init(
            id: 0,
            icon: "location.fill",
            title: "現在地を有効化",
            description: "現在地から安全な自転車ルートを案内するため、位置情報を有効化してください。",
            primaryActionTitle: "位置情報を有効化",
            secondaryActionTitle: "次へ",
            highlights: ["位置情報ONで現在地に追従", "ルート精度が向上"]
        ),
        .init(
            id: 1,
            icon: "sparkles",
            title: "ホームの見方",
            description: "上から、現在地地図・ナビ開始・天気・ライドログの順で確認できます。",
            primaryActionTitle: "次へ",
            secondaryActionTitle: nil,
            highlights: ["今日の1本を1タップで開始", "天気と風を確認して出発"]
        ),
        .init(
            id: 2,
            icon: "figure.outdoor.cycle",
            title: "まず1本走ってみる",
            description: "「目的地を設定してナビ開始」からスポットを選ぶと、すぐにルートを作成できます。",
            primaryActionTitle: "次へ",
            secondaryActionTitle: "目的地を開く",
            highlights: ["平坦優先/ヒルクライムを選択", "プレビュー後すぐナビ開始"]
        ),
        .init(
            id: 3,
            icon: "target",
            title: "週次ミッション",
            description: "今週40kmの進捗を毎日起動して確認できます。達成を目標に継続しましょう。",
            primaryActionTitle: "次へ",
            secondaryActionTitle: nil,
            highlights: ["進捗バーで残り距離を可視化", "毎日開く理由を固定"]
        ),
        .init(
            id: 4,
            icon: "gift.fill",
            title: "ライド完了リワード",
            description: "終了時にハイライトカードを表示。自己最長更新やミッション達成を確認できます。",
            primaryActionTitle: "はじめる",
            secondaryActionTitle: nil,
            highlights: ["距離・平均速度を即確認", "次のライドへ自然に接続"]
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.citrusCanvasStart,
                    Color.citrusCanvasEnd
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    SeaMapView(locationService: viewModel.locationService)
                        .frame(maxWidth: .infinity)
                        .frame(height: 340)
                        .ignoresSafeArea(edges: .top)

                    LazyVStack(spacing: 24) {
                        if let suggestion = viewModel.todayRideSuggestion {
                            TodayRideSuggestionCard(suggestion: suggestion) {
                                viewModel.startNavigation(to: suggestion.harbor, mode: .flat)
                                showRoutePreview = true
                            }
                        }

                        WeeklyMissionCard(mission: viewModel.weeklyMission)

                        Button {
                            showDestinationSheet = true
                        } label: {
                            Label("目的地を設定してナビ開始", systemImage: "bicycle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.citrusAmber, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))

                        WeatherCardView(
                            snapshot: viewModel.weatherSnapshot
                        )

                        LogbookListView(
                            logs: viewModel.voyageLogs,
                            healthStatuses: viewModel.rideLogHealthStatuses
                        )

                        VStack(spacing: 2) {
                            Text(appVersionLabel)
                                .font(.caption2)
                                .foregroundStyle(Color.citrusSecondaryText)
                            Text("XerographiX Inc.")
                                .font(.caption2)
                                .foregroundStyle(Color.citrusSecondaryText.opacity(0.9))
                            HStack(spacing: 6) {
                                Button("利用規約") {
                                    selectedLegalDocument = .terms
                                }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(Color.citrusPrimaryText)

                                Text("｜")
                                    .font(.caption2)
                                    .foregroundStyle(Color.citrusSecondaryText.opacity(0.6))

                                Button("プライバシーポリシー") {
                                    selectedLegalDocument = .privacy
                                }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(Color.citrusPrimaryText)
                            }
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
                .safeAreaPadding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                Image("splash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 720, height: 192)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }

            if showWalkthrough {
                OnboardingWalkthroughView(
                    steps: walkthroughSteps,
                    index: walkthroughIndex,
                    onPrimaryAction: { handleWalkthroughPrimaryAction() },
                    onSecondaryAction: { handleWalkthroughSecondaryAction() },
                    onSkip: { finishWalkthrough() }
                )
                .zIndex(5)
            }
        }
        .sheet(isPresented: $showDestinationSheet) {
            DestinationSearchView(locationService: viewModel.locationService) { harbor, routeMode in
                viewModel.startNavigation(to: harbor, mode: routeMode)
                showDestinationSheet = false
                showRoutePreview = true
            }
        }
        .fullScreenCover(isPresented: $showRoutePreview) {
            if let destination = viewModel.activeDestination,
               let preview = viewModel.pendingRoute {
                RoutePreviewView(
                    destination: destination,
                    routeSummary: preview,
                    rainAvoidanceAlert: viewModel.rainAvoidanceAlert,
                    onApplyRainAvoidance: {
                        viewModel.applyRainAvoidanceReroute()
                    },
                    onCancel: {
                        viewModel.cancelRoutePreview()
                        showRoutePreview = false
                    },
                    onStart: {
                        viewModel.beginDrivingNavigation()
                        showRoutePreview = false
                        showDrivingMode = true
                    }
                )
            } else {
                RoutePreviewLoadingView()
            }
        }
        .fullScreenCover(isPresented: $showDrivingMode) {
            if let destination = viewModel.activeDestination,
               let route = viewModel.routeSummary {
                DrivingNavigationView(
                    destination: destination,
                    routeSummary: route,
                    rainAvoidanceAlert: viewModel.rainAvoidanceAlert,
                    onExit: {
                        viewModel.endNavigation()
                        showDrivingMode = false
                    },
                    onChangeDestination: {
                        showDrivingMode = false
                        showDestinationSheet = true
                    },
                    onRerouteRequest: { location, routeCoordinates in
                        viewModel.requestRerouteIfOffRoute(
                            currentLocation: location,
                            referenceRoute: routeCoordinates
                        )
                    },
                    onApplyRainAvoidance: {
                        viewModel.applyRainAvoidanceReroute()
                    },
                    locationService: viewModel.locationService
                )
            } else {
                ProgressView().task {
                    showDrivingMode = false
                }
            }
        }
        .sheet(item: $viewModel.latestRideReward, onDismiss: {
            viewModel.consumeLatestRideReward()
        }) { reward in
            RideCompletionRewardSheet(reward: reward)
        }
        .sheet(item: $selectedLegalDocument) { document in
            LegalDocumentSheet(document: document)
        }
        .onChange(of: viewModel.pendingRoute != nil) { hasPreview in
            if hasPreview {
                showDestinationSheet = false
            }
        }
        .onChange(of: viewModel.routeSummary != nil) { hasRoute in
            showDrivingMode = hasRoute
        }
        .onAppear {
            viewModel.locationService.requestAuthorization()
            viewModel.locationService.startTracking()
            if shouldForceWalkthroughOnSimulator || !walkthroughCompleted {
                showWalkthrough = true
                walkthroughIndex = 0
            }
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.78"
        return "ver\(version)"
    }

    private var shouldForceWalkthroughOnSimulator: Bool {
#if targetEnvironment(simulator)
        true
#else
        false
#endif
    }

    private func handleWalkthroughPrimaryAction() {
        switch walkthroughIndex {
        case 0:
            viewModel.locationService.requestAuthorization()
            advanceWalkthrough()
        case 1, 2, 3:
            advanceWalkthrough()
        default:
            finishWalkthrough()
        }
    }

    private func handleWalkthroughSecondaryAction() {
        switch walkthroughIndex {
        case 0, 1, 3:
            advanceWalkthrough()
        case 2:
            showDestinationSheet = true
        default:
            break
        }
    }

    private func advanceWalkthrough() {
        if walkthroughIndex < walkthroughSteps.count - 1 {
            walkthroughIndex += 1
        } else {
            finishWalkthrough()
        }
    }

    private func finishWalkthrough() {
        walkthroughCompleted = true
        showWalkthrough = false
    }
}

private struct TodayRideSuggestionCard: View {
    let suggestion: TodayRideSuggestion
    let onStart: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("今日の1本", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(Color.citrusSecondaryText)
                Text(suggestion.title)
                    .font(.headline)
                    .foregroundStyle(Color.citrusPrimaryText)
                Text(suggestion.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.citrusSecondaryText)
                Button("このルートで開始") {
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.citrusAmber)
                .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))
            }
        }
    }
}

private struct WeeklyMissionCard: View {
    let mission: WeeklyMissionProgress

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("週次ミッション", systemImage: "target")
                    .font(.caption.bold())
                    .foregroundStyle(Color.citrusSecondaryText)
                Text(mission.title)
                    .font(.headline)
                    .foregroundStyle(Color.citrusPrimaryText)
                ProgressView(value: mission.progress)
                    .tint(mission.isCompleted ? .green : .citrusAmber)
                Text(
                    mission.isCompleted
                    ? "達成済み \(String(format: "%.1f", mission.currentKm))km"
                    : "残り \(String(format: "%.1f", mission.remainingKm))km"
                )
                .font(.subheadline)
                .foregroundStyle(Color.citrusSecondaryText)
            }
        }
    }
}

private struct RideCompletionRewardSheet: View {
    let reward: RideCompletionReward
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(reward.title)
                    .font(.title2.bold())
                    .foregroundStyle(Color.citrusPrimaryText)
                Text(reward.subtitle)
                    .font(.headline)
                    .foregroundStyle(Color.citrusSecondaryText)
                ForEach(reward.badges, id: \.self) { badge in
                    Label(badge, systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.citrusPrimaryText)
                }
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.citrusAmber)
                .foregroundStyle(Color(red: 0.36, green: 0.26, blue: 0))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .navigationTitle("ライドハイライト")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.citrusCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.citrusBorder)
                )

            content
                .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}

private enum LegalDocumentPage: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return "利用規約"
        case .privacy: return "プライバシーポリシー"
        }
    }

    var url: URL {
        switch self {
        case .terms:
            return URL(string: "https://lp.xerographix.co.jp/ridelane/terms.html")!
        case .privacy:
            return URL(string: "https://lp.xerographix.co.jp/ridelane/privacy.html")!
        }
    }

    var cacheFileName: String {
        "\(rawValue).html"
    }
}

@MainActor
private final class LegalDocumentViewModel: ObservableObject {
    @Published var cachedHTML: String?
    @Published var statusMessage: String?

    private let document: LegalDocumentPage
    private let cacheStore = LegalDocumentCacheStore()
    private var didLoad = false

    init(document: LegalDocumentPage) {
        self.document = document
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        cachedHTML = cacheStore.loadCachedHTML(for: document)
        statusMessage = cachedHTML == nil ? "読み込み中..." : "最新情報を読み込み中（オフライン対応あり）"
    }

    func handleRemoteLoaded(html: String) {
        cacheStore.saveCachedHTML(html, for: document)
        cachedHTML = html
        statusMessage = "最新情報を更新済み"
    }

    func handleFallbackShown() {
        statusMessage = "ネットワーク未接続のためキャッシュを表示中"
    }

    func fallbackHTML() -> String {
        cachedHTML ?? cacheStore.errorHTML(
            title: document.title,
            message: "ネットワーク接続がないため表示できません。オンライン時に一度開くと、次回以降オフラインでも表示できます。"
        )
    }
}

private struct LegalDocumentSheet: View {
    let document: LegalDocumentPage
    @StateObject private var viewModel: LegalDocumentViewModel
    @Environment(\.dismiss) private var dismiss

    init(document: LegalDocumentPage) {
        self.document = document
        _viewModel = StateObject(wrappedValue: LegalDocumentViewModel(document: document))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                LegalDocumentWebView(
                    url: document.url,
                    fallbackHTML: viewModel.fallbackHTML(),
                    onRemoteLoaded: { html in
                        viewModel.handleRemoteLoaded(html: html)
                    },
                    onFallbackShown: {
                        viewModel.handleFallbackShown()
                    }
                )

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(Color.citrusSecondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

private struct LegalDocumentWebView: UIViewRepresentable {
    let url: URL
    let fallbackHTML: String
    let onRemoteLoaded: (String) -> Void
    let onFallbackShown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            url: url,
            fallbackHTML: fallbackHTML,
            onRemoteLoaded: onRemoteLoaded,
            onFallbackShown: onFallbackShown
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.footerHidingScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.fallbackHTML = fallbackHTML
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            context.coordinator.usedFallback = false
            webView.load(URLRequest(url: url))
        }
    }

    private static let footerHidingScript = """
    (function() {
      function hideRideLaneTopButton() {
        var targets = document.querySelectorAll("a,button,[role='button']");
        for (var i = 0; i < targets.length; i++) {
          var node = targets[i];
          var text = (node.textContent || "").replace(/\\s+/g, " ").trim();
          if (text.indexOf("RideLane トップへ戻る") !== -1) {
            node.style.display = "none";
            if (node.classList && node.classList.contains("back")) {
              node.style.display = "none";
            }
          }
        }
      }
      window.__ridelaneHideTopButton = hideRideLaneTopButton;
      hideRideLaneTopButton();
      var observer = new MutationObserver(hideRideLaneTopButton);
      observer.observe(document.documentElement, { childList: true, subtree: true });
      setTimeout(hideRideLaneTopButton, 600);
      setTimeout(hideRideLaneTopButton, 1500);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var usedFallback = false
        var fallbackHTML: String
        private let url: URL
        private let onRemoteLoaded: (String) -> Void
        private let onFallbackShown: () -> Void

        init(
            url: URL,
            fallbackHTML: String,
            onRemoteLoaded: @escaping (String) -> Void,
            onFallbackShown: @escaping () -> Void
        ) {
            self.url = url
            self.fallbackHTML = fallbackHTML
            self.onRemoteLoaded = onRemoteLoaded
            self.onFallbackShown = onFallbackShown
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.__ridelaneHideTopButton && window.__ridelaneHideTopButton();")
            guard !usedFallback else { return }
            webView.evaluateJavaScript("document.documentElement.outerHTML") { value, _ in
                guard let html = value as? String, !html.isEmpty else { return }
                self.onRemoteLoaded(html)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showFallbackIfNeeded(webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            showFallbackIfNeeded(webView)
        }

        private func showFallbackIfNeeded(_ webView: WKWebView) {
            guard !usedFallback else { return }
            usedFallback = true
            onFallbackShown()
            webView.loadHTMLString(fallbackHTML, baseURL: url.deletingLastPathComponent())
        }
    }
}

private struct LegalDocumentCacheStore {
    private let fileManager = FileManager.default

    private var directoryURL: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = appSupport.appendingPathComponent("LegalCache", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    func loadCachedHTML(for document: LegalDocumentPage) -> String? {
        guard let fileURL = directoryURL?.appendingPathComponent(document.cacheFileName) else { return nil }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func saveCachedHTML(_ html: String, for document: LegalDocumentPage) {
        if let fileURL = directoryURL?.appendingPathComponent(document.cacheFileName) {
            try? html.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func errorHTML(title: String, message: String) -> String {
        """
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(title)</title>
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; color: #243238; }
              h1 { font-size: 22px; margin-bottom: 12px; }
              p { font-size: 15px; line-height: 1.6; }
            </style>
          </head>
          <body>
            <h1>\(title)</h1>
            <p>\(message)</p>
          </body>
        </html>
        """
    }
}
