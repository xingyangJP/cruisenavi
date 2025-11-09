import SwiftUI

struct SplashView: View {
    @State private var opacity: Double = 1.0
    @State private var blurRadius: CGFloat = 30
    @State private var scale: CGFloat = 0.92

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Image("splash")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 200, height: 200)
                .opacity(opacity)
                .blur(radius: blurRadius)
                .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                blurRadius = 0
                scale = 1.0
            }
        }
    }
}
