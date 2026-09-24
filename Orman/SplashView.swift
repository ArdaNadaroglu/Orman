import SwiftUI

// A brief branded splash shown on launch — separate from the system launch
// screen (which can't be held on screen by the app itself), this is an
// ordinary SwiftUI view faded out after a couple of seconds.
struct SplashView: View {
    // 0 = fully hidden, 1 = fully revealed. Drives a left-to-right mask so
    // the wordmark reads as if it's being written on, rather than fading
    // or popping in all at once.
    @State private var textReveal: CGFloat = 0

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.97, blue: 0.93).ignoresSafeArea()
            VStack(spacing: 18) {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 145, height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                // Apple's own system font (San Francisco), not the app's
                // serif branding font used elsewhere.
                Text("Silva Todo")
                    .font(.system(size: 31.5, weight: .semibold, design: .default))
                    .foregroundStyle(Color(red: 0.16, green: 0.34, blue: 0.26))
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * textReveal)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            // A slow, gradual reveal that plays out over most of the
            // splash's (now longer) time on screen, rather than a quick pop.
            withAnimation(.easeInOut(duration: 2.6).delay(0.4)) {
                textReveal = 1
            }
        }
    }
}
