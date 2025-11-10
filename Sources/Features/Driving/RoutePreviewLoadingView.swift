import SwiftUI

struct RoutePreviewLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("航路を生成しています…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }
}
