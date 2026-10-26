import SwiftUI

/// Tales of Dorlune's own colours, the logo's and the app icon's exactly (the Figma brand guidelines list
/// them, page 03 Colour): the logo's gold, and midnight (the night sky's navy) for lettering and
/// outlines where dark green was until 0.8.11. The title and loading screens wear them; the game's
/// windows keep Fairyland's look (`HUDStyle`).
enum Brand {
    /// The logo's gold, top to bottom: the loading bar's fill and the travel swirl.
    static let goldLight = Color(red: 1, green: 0.965, blue: 0.745)    // #FFF6BE
    static let gold = Color(red: 1, green: 0.788, blue: 0.235)         // #FFC93C
    static let goldDeep = Color(red: 0.886, green: 0.486, blue: 0.086) // #E27C16
    /// Every outline and the lettering on cream: the name pill's, the bar's rim, the swirl's.
    static let midnight = Color(red: 0.106, green: 0.145, blue: 0.314) // #1B2550
    /// The thicker edge under the name pill.
    static let midnightDeep = Color(red: 0.055, green: 0.082, blue: 0.2) // #0E1533
    /// The name pill, and the loading bar's track.
    static let cream = Color(red: 1, green: 0.969, blue: 0.878)        // #FFF7E0

    /// The icon's sky, top to bottom.
    static let lavender = Color(red: 0.8, green: 0.722, blue: 1)       // #CCB8FF
    static let sky = Color(red: 0.659, green: 0.859, blue: 1)          // #A8DBFF
    static let mint = Color(red: 0.722, green: 0.961, blue: 0.839)     // #B8F5D6

    /// The same sky at night, for Dark Mode (the dark app icon's, `tools/app_icon_art.py`):
    /// deep indigo, navy and teal where the day has lavender, sky blue and mint.
    static let nightTop = Color(red: 0.17, green: 0.12, blue: 0.38)    // #2B1F61
    static let night = Color(red: 0.07, green: 0.13, blue: 0.33)       // #122154
    static let nightBottom = Color(red: 0.04, green: 0.2, blue: 0.25)  // #0A3340
    /// The night's clouds, lit by the moon.
    static let moonCloud = Color(red: 0.3, green: 0.38, blue: 0.52)    // #4D6185

    /// Lettering straight on the sky (not on a window or a button): deep navy by day, cream at night.
    static let skyText = Color.adaptive(light: HUDStyle.ink, dark: HUDStyle.cream)
}

/// Where the sky's soft light sits: the middle of the world's name in the logo (Logo.png, drawn by
/// tools/logo_art.py), or whatever else a screen puts in its middle (the travel card's swirl). Published with `raysAnchor`, read by `talesOfDorluneSky`.
struct RaysAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? { nil }
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

extension Brand {
    /// Where the sky's light sits in the logo image (the middle of DORLUNE, under the smaller TALES OF),
    /// as a share of its size.
    static let raysInLogo = UnitPoint(x: 0.5, y: 0.67)
}

extension View {
    /// Marks this view's `point` (the middle of the world's name, for the logo) as where the sky's light sits.
    func raysAnchor(_ point: UnitPoint = .center) -> some View {
        anchorPreference(key: RaysAnchor.self, value: .unitPoint(point)) { $0 }
    }

    /// The Tales of Dorlune sky behind this screen, its light exactly where `raysAnchor`
    /// marks, wherever that lands on this phone and however the screen moves it (scrolling, a
    /// phone on its side); from `fallback` (a share of the screen) where nothing marks it.
    func talesOfDorluneSky(fallback: UnitPoint) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundPreferenceValue(RaysAnchor.self) { anchor in
                // Full screen, like the sky, so the anchor resolves in the sky's own coordinates.
                GeometryReader { proxy in
                    let center = anchor.map { anchor -> UnitPoint in
                        let point = proxy[anchor]
                        return UnitPoint(x: point.x / max(1, proxy.size.width), y: point.y / max(1, proxy.size.height))
                    }
                    TalesOfDorluneSky(raysFrom: center ?? fallback)
                }
                .ignoresSafeArea()
            }
    }
}

/// The sky behind the title and loading screens: lavender at the top through sky blue to mint, a
/// soft light behind the logo, and clouds along the bottom. No sun rays: fanned out round the
/// logo they looked cheap. In Dark Mode it's the dark icon's night: indigo through navy to teal,
/// the light faint, the clouds moonlit and a scatter of stars.
struct TalesOfDorluneSky: View {
    /// Where the soft light sits, as a share of the screen: behind the logo.
    var raysFrom = UnitPoint(x: 0.5, y: 0.3)
    @Environment(\.colorScheme) private var colorScheme

    /// The night's stars: where, as shares of the screen, and how big, in points. Kept to the
    /// sky's upper part and its edges, clear of the logo and the clouds.
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.08, 0.06, 3), (0.22, 0.14, 2), (0.9, 0.08, 3.5), (0.76, 0.18, 2), (0.06, 0.34, 2.5),
        (0.95, 0.3, 2), (0.14, 0.52, 2), (0.88, 0.5, 3), (0.42, 0.04, 2), (0.6, 0.1, 2.5),
        (0.04, 0.68, 2), (0.97, 0.66, 2.5),
    ]

    /// The clouds along the bottom, a bank in each corner like the icon's: where across the
    /// screen, and how big, as shares of its shorter side.
    private static let puffs: [(x: CGFloat, size: CGFloat)] = [
        (0.02, 0.56), (0.2, 0.4), (0.36, 0.24),
        (0.98, 0.6), (0.8, 0.42), (0.64, 0.26),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let night = colorScheme == .dark
            ZStack {
                LinearGradient(colors: night ? [Brand.nightTop, Brand.night, Brand.nightBottom] : [Brand.lavender, Brand.sky, Brand.mint],
                               startPoint: .top, endPoint: .bottom)

                Rectangle()
                    .fill(RadialGradient(colors: [.white.opacity(night ? 0.08 : 0.28), .white.opacity(0)], center: raysFrom,
                                         startRadius: 0, endRadius: side * 0.6))

                if night {
                    ForEach(Self.stars.indices, id: \.self) { index in
                        let star = Self.stars[index]
                        Circle()
                            .fill(.white.opacity(0.85))
                            .frame(width: star.size, height: star.size)
                            .shadow(color: .white.opacity(0.6), radius: star.size)
                            .position(x: proxy.size.width * star.x, y: proxy.size.height * star.y)
                    }
                }

                ForEach(Self.puffs.indices, id: \.self) { index in
                    let puff = Self.puffs[index]
                    Circle()
                        .fill(night ? Brand.moonCloud.opacity(0.92) : .white.opacity(0.88))
                        .frame(width: side * puff.size, height: side * puff.size)
                        .position(x: proxy.size.width * puff.x, y: proxy.size.height + side * puff.size * 0.12)
                }
                .blur(radius: 1.5)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
