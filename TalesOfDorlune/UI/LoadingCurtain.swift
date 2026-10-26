import SwiftUI

/// Shown while a map is being built: the logo over the title's sky, and a gold bar filling up.
struct LoadingCurtain: View {
    /// 0...1: how far the map build has got.
    var progress: Double = 0
    @State private var spin = false

    var body: some View {
        ZStack {
            // The bar keeps a little apart from the logo, and narrower than it.
            VStack(spacing: 30) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .raysAnchor(Brand.raysInLogo)
                    .frame(maxWidth: 300)
                    .scaleEffect(spin ? 1.03 : 0.97)
                LoadingBar.talesOfDorlune(progress: progress, label: L("Loading"))
            }
            .padding(.horizontal, 40)
        }
        // The sky's soft light sits behind the logo.
        .talesOfDorluneSky(fallback: UnitPoint(x: 0.5, y: 0.44))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { spin = true }
        }
    }
}

/// Shown briefly when travelling to another map, in the brand's colours like the game's own
/// loading: the title's sky, a gold swirl turning, the destination's name on a cream pill
/// outlined like the logo's tagline, and the same bar.
struct MapLoadingCard: View {
    let mapName: String
    var progress: Double = 0
    @State private var spin = false

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                ZStack {
                    // Outlined like the logo's letters: midnight under, the logo's gold on top.
                    SwirlShape().stroke(Brand.midnight, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    SwirlShape().stroke(LinearGradient(colors: [Brand.goldLight, Brand.gold, Brand.goldDeep], startPoint: .top, endPoint: .bottom),
                                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 70, height: 70)
                // The sky's soft light sits behind the swirl (its centre stays put as it turns).
                .raysAnchor()
                .rotationEffect(.degrees(spin ? 360 : 0))
                Text(mapName)
                    .font(HUDStyle.font(24))
                    .foregroundStyle(Brand.midnight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Brand.cream))
                    .overlay(Capsule().strokeBorder(Brand.midnight, lineWidth: 3))
                    // The thicker edge under it, like the logo's pill.
                    .background(Capsule().fill(Brand.midnightDeep).offset(y: 3))
                LoadingBar.talesOfDorlune(progress: progress, label: L("Travelling"))
            }
            .padding(.horizontal, 40)
        }
        .talesOfDorluneSky(fallback: UnitPoint(x: 0.5, y: 0.42))
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

/// A bar that fills as loading goes (blue, unless told otherwise), with the percentage beside the label.
struct LoadingBar: View {
    let progress: Double
    let label: String
    let textColor: Color
    /// The fill, top to bottom, the empty part, and the rim round it.
    var fill: [Color] = [Color(red: 0.45, green: 0.78, blue: 1), Color(red: 0.13, green: 0.47, blue: 0.95)]
    var track: Color = HUDStyle.ink.opacity(0.35)
    var rim: Color = .white.opacity(0.8)
    /// How wide the bar grows at most.
    var width: CGFloat = 280

    /// The brand's own loading bar, the same on every loading screen: the logo's gold, outlined in
    /// midnight, on its cream.
    static func talesOfDorlune(progress: Double, label: String) -> LoadingBar {
        LoadingBar(progress: progress, label: label, textColor: Brand.skyText,
                   fill: [Brand.goldLight, Brand.gold, Brand.goldDeep], track: Brand.cream, rim: Brand.midnight,
                   width: 200)
    }

    private var percent: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(track)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .top) {
                                Capsule().fill(.white.opacity(0.35)).frame(height: 4).padding(.horizontal, 6).padding(.top, 2)
                            }
                            .frame(width: max(14, proxy.size.width * min(max(progress, 0), 1)))
                    }
                }
                .overlay(Capsule().strokeBorder(rim, lineWidth: 2))
                .frame(maxWidth: width)
                .frame(height: 16)
                // No animation: the map build holds the screen between steps, so an animated bar
                // would lag behind its own number.
            Text("\(label)… \(percent)%")
                .font(HUDStyle.font(14))
                .monospacedDigit()
                .foregroundStyle(textColor.opacity(0.85))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(L("{percent} percent", ["percent": percent]))
    }
}

/// An Archimedean spiral, like Fairyland Online's swirl.
nonisolated struct SwirlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let turns = 2.6
        let steps = 90
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = t * turns * 2 * .pi
            let radius = t * min(rect.width, rect.height) / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
