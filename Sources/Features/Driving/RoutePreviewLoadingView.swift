import SwiftUI

struct RoutePreviewLoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.citrusCanvasStart, .citrusCanvasEnd],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.citrusPrimaryText)
                Text("ルートを生成しています…")
                    .font(.headline)
                    .foregroundStyle(Color.citrusPrimaryText)
            }
        }
    }
}
