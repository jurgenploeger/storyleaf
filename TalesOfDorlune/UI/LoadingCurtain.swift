import SwiftUI

/// Shown while a map is being built: the logo over the title's sky, and a blue bar filling up.
/// Opening a game from the title, the logo comes from where it stood there (`RootView` moves one
/// logo between the two, `logoSpot`), and once the game is ready the clouds come up over everything
/// (`landing`) before clearing off it.
struct LoadingCurtain: View {
    /// 0...1: how far the map build has got.
    var progress: Double = 0
    /// Where its logo stands, published for RootView's logo to move to.
    var logoSpot: LogoSpot? = nil
    /// Its own logo hidden while RootView's is on its way here.
    var logoHidden = false
    /// The game is ready: the clouds rise over the screen, the logo sinking into them.
    var landing = false
    @State private var spin = false
    /// The bar fades in once the logo has come from the title.
    @State private var barShown = false

    /// The logo's width, here and on the title screen.
    static let logoWidth: CGFloat = 300
    /// How long the logo takes to move here from the title.
    static let handOff = 0.6
    /// How long the clouds take to cover the screen.
    static let landingTime = 1.6

    var body: some View {
        ZStack {
            // The bar keeps a little apart from the logo, and narrower than it.
            VStack(spacing: 30) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .logoSpot(logoSpot)
                    .opacity(logoHidden ? 0 : 1)
                    .raysAnchor(Brand.raysInLogo)
                    .frame(maxWidth: Self.logoWidth)
                    // Breathing out from the title's size, so it doesn't jump as it arrives.
                    .scaleEffect(spin ? 1.04 : 1)
                    // Falling, faster and faster, as the clouds rush up past it.
                    .offset(y: landing ? 70 : 0)
                    .animation(.easeIn(duration: Self.landingTime), value: landing)
                LoadingBar.talesOfDorlune(progress: progress, label: L("Loading"))
                    .opacity(landing || (logoSpot != nil && !barShown) ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: landing)
            }
            .padding(.horizontal, 40)
            CloudCover(risen: landing)
        }
        // The sky's soft light sits behind the logo.
        .talesOfDorluneSky(fallback: UnitPoint(x: 0.5, y: 0.44))
        .onAppear {
            if logoSpot != nil {
                withAnimation(.easeOut(duration: 0.35).delay(Self.handOff * 0.6)) { barShown = true }
            }
            if !logoHidden { breathe() }
        }
        // Not till its own logo shows: begun while hidden, it would show at another size than the
        // one that came.
        .onChange(of: logoHidden) { _, hidden in
            if !hidden { breathe() }
        }
    }

    private func breathe() {
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { spin = true }
    }
}

/// Where the logo stands on the title and on the loading screen: RootView draws one logo over both
/// and moves it from the one to the other, so it's the same logo all the way.
enum LogoSpot: Hashable {
    case title, loading
}

struct LogoSpots: PreferenceKey {
    static var defaultValue: [LogoSpot: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [LogoSpot: Anchor<CGRect>], nextValue: () -> [LogoSpot: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Publishes this view's bounds as the logo's place (`spot`), where there's one to publish.
    @ViewBuilder
    func logoSpot(_ spot: LogoSpot?) -> some View {
        if let spot {
            anchorPreference(key: LogoSpots.self, value: .bounds) { [spot: $0] }
        } else {
            self
        }
    }
}

/// The clouds that come up over the loading screen once the game is ready, as if the logo fell
/// through them to the ground: five banks of cumulus, one behind the other, rising from under the
/// sky's own and faster as they come. The far ones are smaller, paler and bluer (the haze between),
/// stop lower and set off first; the nearest is the biggest and covers the screen. Each is lit from
/// above, its puffs bright on top and its body shaded lower down, and casts a soft shadow up onto
/// the one behind; they drift a little sideways each their own way as they rise.
struct CloudCover: View {
    let risen: Bool
    @Environment(\.colorScheme) private var colorScheme

    private struct Bank {
        /// Its puffs along the top: where across, as a share of the screen's width; how big, as a
        /// share of its shorter side (the sky's own are 0.24 to 0.6); and how far below the bank's
        /// top their middle sits, as a share of their size, so the top is lumpy.
        let puffs: [(x: CGFloat, size: CGFloat, drop: CGFloat)]
        /// Where its top comes up to, as a share of the screen's height (below 0: past the top).
        let reach: CGFloat
        /// How long after the first it sets off; every bank arrives together.
        let delay: Double
        /// How far it drifts sideways as it comes, as a share of the width.
        let drift: CGFloat
        /// 0 the farthest, 1 the nearest.
        let near: Double
    }

    /// Far to near.
    private static let banks: [Bank] = [
        Bank(puffs: [(-0.02, 0.4, 0.1), (0.16, 0.28, 0.2), (0.33, 0.38, 0.05), (0.52, 0.26, 0.25), (0.7, 0.4, 0.1), (0.9, 0.3, 0.2), (1.04, 0.38, 0.05)],
             reach: 0.52, delay: 0, drift: 0.04, near: 0),
        Bank(puffs: [(0.06, 0.46, 0.1), (0.27, 0.32, 0.25), (0.45, 0.44, 0.05), (0.66, 0.3, 0.2), (0.85, 0.46, 0.08), (1.06, 0.34, 0.2)],
             reach: 0.36, delay: 0.1, drift: -0.05, near: 0.25),
        Bank(puffs: [(-0.04, 0.54, 0.05), (0.2, 0.38, 0.2), (0.4, 0.5, 0), (0.62, 0.36, 0.22), (0.83, 0.52, 0.06), (1.04, 0.4, 0.2)],
             reach: 0.2, delay: 0.2, drift: 0.06, near: 0.5),
        Bank(puffs: [(0.04, 0.6, 0.06), (0.3, 0.44, 0.2), (0.52, 0.58, 0), (0.76, 0.42, 0.24), (0.98, 0.62, 0.05)],
             reach: 0.03, delay: 0.3, drift: -0.04, near: 0.75),
        Bank(puffs: [(-0.06, 0.7, 0.05), (0.22, 0.52, 0.2), (0.48, 0.68, 0), (0.74, 0.5, 0.22), (1.02, 0.72, 0.04)],
             reach: -0.4, delay: 0.4, drift: 0.03, near: 1),
    ]

    /// A cloud's colours, from its lit top to its shaded body: by day the far banks hazy blue, the
    /// near ones white; at night all moonlit.
    private struct Shades {
        let light: Color
        let base: Color
        let shade: Color
    }

    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func mix(_ far: RGB, _ near: RGB, _ amount: Double) -> Color {
        Color(red: far.r + (near.r - far.r) * amount, green: far.g + (near.g - far.g) * amount,
              blue: far.b + (near.b - far.b) * amount)
    }

    private func shades(_ near: Double, night: Bool) -> Shades {
        if night {
            return Shades(light: Self.mix((0.3, 0.37, 0.52), (0.55, 0.63, 0.78), near),
                          base: Self.mix((0.21, 0.27, 0.42), (0.37, 0.45, 0.61), near),
                          shade: Self.mix((0.14, 0.19, 0.33), (0.25, 0.32, 0.47), near))
        }
        return Shades(light: Self.mix((0.92, 0.96, 1), (1, 1, 1), near),
                      base: Self.mix((0.82, 0.9, 0.99), (0.96, 0.98, 1), near),
                      shade: Self.mix((0.68, 0.8, 0.94), (0.83, 0.89, 0.97), near))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let side = min(size.width, size.height)
            let night = colorScheme == .dark
            ZStack {
                ForEach(Self.banks.indices, id: \.self) { index in
                    let bank = Self.banks[index]
                    let tone = shades(bank.near, night: night)
                    ZStack {
                        // The body under the puffs, shaded deeper down.
                        Rectangle()
                            .fill(LinearGradient(stops: [
                                .init(color: tone.base, location: 0),
                                .init(color: tone.shade, location: 0.35),
                            ], startPoint: .top, endPoint: .bottom))
                            .frame(width: size.width, height: size.height * 1.6)
                            .position(x: size.width / 2, y: size.height * 0.8)
                        // The puffs, each lit from above on the left and shading into the body.
                        ForEach(bank.puffs.indices, id: \.self) { puffIndex in
                            let puff = bank.puffs[puffIndex]
                            let diameter = side * puff.size
                            Circle()
                                .fill(RadialGradient(colors: [tone.light, tone.base, tone.shade],
                                                     center: UnitPoint(x: 0.42, y: 0.28),
                                                     startRadius: 0, endRadius: diameter * 0.75))
                                .frame(width: diameter, height: diameter)
                                .position(x: size.width * puff.x, y: diameter * puff.drop)
                        }
                    }
                    // One mass of cloud, its soft shadow cast up onto the bank behind.
                    .compositingGroup()
                    .shadow(color: night ? .black.opacity(0.35) : Color(red: 0.42, green: 0.58, blue: 0.84).opacity(0.3),
                            radius: side * 0.035, y: -side * 0.012)
                    // Down out of sight under the screen, then up to its reach, drifting as it comes.
                    .offset(x: risen ? size.width * bank.drift : 0,
                            y: risen ? size.height * bank.reach : size.height + side * 0.45)
                    .animation(.easeIn(duration: LoadingCurtain.landingTime - bank.delay).delay(bank.delay), value: risen)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    /// The brand's own loading bar, the same on every loading screen: the brand blue (the sky's),
    /// outlined in midnight, on cream.
    static func talesOfDorlune(progress: Double, label: String) -> LoadingBar {
        LoadingBar(progress: progress, label: label, textColor: Brand.skyText,
                   fill: [Brand.skyLight, Brand.sky, Brand.skyDeep], track: Brand.cream, rim: Brand.midnight,
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
