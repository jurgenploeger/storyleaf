import SwiftUI

/// Shown while a map is being built: the logo over the title's sky, and a blue bar filling up.
/// Opening a game from the title, the logo comes from where it stood there (`RootView` moves one
/// logo between the two, `logoSpot`), and once the game is ready the clouds come up over everything
/// (`landing`), then rise on past you, thinning, the game showing through them (`clearing`): as if
/// you came down through them to the ground.
struct LoadingCurtain: View {
    /// 0...1: how far the map build has got.
    var progress: Double = 0
    /// Where its logo stands, published for RootView's logo to move to.
    var logoSpot: LogoSpot? = nil
    /// Its own logo hidden while RootView's is on its way here.
    var logoHidden = false
    /// The game is ready: the clouds rise over the screen, the logo sinking into them.
    var landing = false
    /// The clouds part: they rise on up and thin out, the game under them coming through.
    var clearing = false
    @State private var spin = false
    /// The bar fades in once the logo has come from the title.
    @State private var barShown = false

    /// The logo's width, here and on the title screen.
    static let logoWidth: CGFloat = 300
    /// How long the logo takes to move here from the title.
    static let handOff = 0.6
    /// How long the clouds take to cover the screen.
    static let landingTime = 1.3
    /// How long the clouds take to rise off the game, and the frosted haze under them to clear.
    static let clearingTime = 1.4

    var body: some View {
        ZStack {
            CloudHaze(clearing: clearing)
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
            // The sky's soft light sits behind the logo.
            .talesOfDorluneSky(fallback: UnitPoint(x: 0.5, y: 0.44))
            // Under the nearest clouds by then: gone at once, so the game is what shows as they part.
            .opacity(clearing ? 0 : 1)
            .animation(nil, value: clearing)
            CloudCover(risen: landing, through: clearing)
        }
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

/// Frosted glass over the game, under a loading screen's sky till the clouds part, then clearing
/// with them: the game comes into focus as you come down through the clouds, not sharp at once
/// behind them (playtesting 2026-10-31: "you can see the layers, there should be a bg blur that
/// fades out").
struct CloudHaze: View {
    let clearing: Bool

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .opacity(clearing ? 0 : 1)
            .animation(.easeInOut(duration: LoadingCurtain.clearingTime), value: clearing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The clouds that come up over the loading screen once the game is ready: banks of them rising
/// from under the sky's own, faster as they come, the far ones paler and slower, till the nearest
/// covers the screen, as if the logo fell through them to the ground. Each bank is a row of puffs
/// on a body of cloud.
struct CloudCover: View {
    let risen: Bool
    /// Coming down through them: every bank rises on past the top, the nearest fastest, growing as it
    /// passes and thinning to nothing (playtesting 2026-10-30: "so it looks like you're moving through
    /// the clouds down to earth").
    var through = false
    @Environment(\.colorScheme) private var colorScheme

    private struct Bank {
        /// Its puffs along the top: where across, as a share of the screen's width, and how big, as
        /// a share of its shorter side (the sky's own puffs are 0.24 to 0.6).
        let puffs: [(x: CGFloat, size: CGFloat)]
        /// Where its top comes up to, as a share of the screen's height (below 0: past the top).
        let reach: CGFloat
        let opacity: Double
        /// How long after the first it sets off; every bank arrives together.
        let delay: Double
    }

    /// Far to near.
    private static let banks: [Bank] = [
        Bank(puffs: [(0.08, 0.5), (0.34, 0.36), (0.6, 0.46), (0.9, 0.42)], reach: 0.32, opacity: 0.5, delay: 0),
        Bank(puffs: [(0, 0.56), (0.24, 0.4), (0.5, 0.5), (0.76, 0.38), (1, 0.58)], reach: 0.1, opacity: 0.75, delay: 0.15),
        Bank(puffs: [(0.04, 0.6), (0.3, 0.46), (0.56, 0.56), (0.82, 0.44), (1.02, 0.6)], reach: -0.3, opacity: 1, delay: 0.3),
    ]

    /// A bank's puffs along its bottom: one between each two of its top's, as big as the two between,
    /// and one past the last.
    private static func underside(of puffs: [(x: CGFloat, size: CGFloat)]) -> [(x: CGFloat, size: CGFloat)] {
        var under: [(x: CGFloat, size: CGFloat)] = []
        for (index, puff) in puffs.enumerated() {
            if index + 1 < puffs.count {
                let next = puffs[index + 1]
                under.append((x: (puff.x + next.x) / 2, size: (puff.size + next.size) / 2))
            } else {
                under.append((x: puff.x + 0.12, size: puff.size))
            }
        }
        if let first = puffs.first { under.insert((x: first.x - 0.12, size: first.size), at: 0) }
        return under
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let side = min(size.width, size.height)
            let night = colorScheme == .dark
            ZStack {
                ForEach(Self.banks.indices, id: \.self) { index in
                    let bank = Self.banks[index]
                    ZStack {
                        ForEach(bank.puffs.indices, id: \.self) { puffIndex in
                            let puff = bank.puffs[puffIndex]
                            Circle()
                                .frame(width: side * puff.size, height: side * puff.size)
                                .position(x: size.width * puff.x, y: 0)
                        }
                        Rectangle()
                            .frame(width: size.width, height: size.height * 1.5)
                            .position(x: size.width / 2, y: size.height * 0.75)
                        // Puffs along its bottom too, half a puff along from the top's: rising on past
                        // the top it showed a straight edge (playtesting 2026-10-31: "can the bottom of
                        // the cloud animation also have the cloud shape instead of a rectangle?").
                        let under = Self.underside(of: bank.puffs)
                        ForEach(under.indices, id: \.self) { puffIndex in
                            let puff = under[puffIndex]
                            Circle()
                                .frame(width: side * puff.size, height: side * puff.size)
                                .position(x: size.width * puff.x, y: size.height * 1.5)
                        }
                    }
                    .foregroundStyle(night ? Brand.moonCloud : .white)
                    // One sheet of cloud, not puffs see-through where they overlap.
                    .compositingGroup()
                    .opacity(through ? 0 : bank.opacity)
                    .scaleEffect(through ? 1.15 + 0.15 * CGFloat(index) : 1, anchor: .top)
                    // Down out of sight under the screen, then up to its reach; then on up past the top.
                    .offset(y: through ? size.height * (bank.reach - 0.8 - 0.4 * CGFloat(index))
                                : risen ? size.height * bank.reach : size.height + side * 0.4)
                    .animation(.easeIn(duration: LoadingCurtain.landingTime - bank.delay).delay(bank.delay), value: risen)
                    .animation(.easeOut(duration: LoadingCurtain.clearingTime), value: through)
                }
            }
            // Softening as they rise past, so the banks melt into one another and the haze instead of
            // showing as sheets with hard edges: one blur over them all, not one a bank (three
            // screen-sized blurs a frame made the parting choppy on a phone).
            .blur(radius: through ? side * 0.08 : 0)
            .animation(.easeOut(duration: LoadingCurtain.clearingTime), value: through)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shown briefly when travelling to another map, in the brand's colours like the game's own
/// loading: the title's sky, a gold swirl turning, the destination's name on a cream pill
/// outlined like the logo's tagline, and the same bar.
///
/// Once the land's ready the clouds come up over it and part onto the game, as they do when the
/// game opens (`landing`, `clearing`; playtesting 2026-10-31: "when teleporting or any other
/// loading screen during the game, it should have the same animation with the clouds").
struct MapLoadingCard: View {
    let mapName: String
    var progress: Double = 0
    /// The land's ready: the clouds rise over the card.
    var landing = false
    /// The clouds part: they rise on up and thin out, the game coming through.
    var clearing = false
    @State private var spin = false

    var body: some View {
        ZStack {
            CloudHaze(clearing: clearing)
            card
                // Under the nearest clouds by then: gone at once, so the game is what shows as they part.
                .opacity(clearing ? 0 : 1)
                .animation(nil, value: clearing)
            CloudCover(risen: landing, through: clearing)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    private var card: some View {
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
                    .opacity(landing ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: landing)
            }
            .padding(.horizontal, 40)
        }
        .talesOfDorluneSky(fallback: UnitPoint(x: 0.5, y: 0.42))
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

    /// The brand's own loading bar, the same on every loading screen: the brand's deep blue, darker
    /// toward its foot (the sky's own pale blue was lost against the sky: playtesting 2026-10-31, "The
    /// loading bar should also use the darker blue, so it's not the same color as the sky bg"),
    /// outlined in midnight, on cream.
    static func talesOfDorlune(progress: Double, label: String) -> LoadingBar {
        LoadingBar(progress: progress, label: label, textColor: Brand.skyText,
                   fill: [Brand.skyDeep, Self.deepBlue], track: Brand.cream, rim: Brand.midnight,
                   width: 200)
    }

    /// The foot of the brand bar's fill: its deep blue a shade darker, toward midnight (#2E61C7).
    static let deepBlue = Color(red: 0.18, green: 0.38, blue: 0.78)

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
