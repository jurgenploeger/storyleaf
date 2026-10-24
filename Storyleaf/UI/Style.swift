import SpriteKit
import SwiftUI

extension Color {
    /// A colour that follows the phone's look: `light` normally, `dark` in Dark Mode. SwiftUI
    /// picks the one for wherever it's drawn, and switches when the phone does.
    /// Nonisolated, with both resolved up front: UIKit may ask for the colour off the main thread.
    nonisolated static func adaptive(light: Color, dark: Color) -> Color {
        let light = UIColor(light), dark = UIColor(dark)
        return Color(uiColor: UIColor { @Sendable traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

/// Fairyland Online's look: glossy light-blue bevelled frames, deep-blue glass windows,
/// tan info plates, yellow outlined names and orange close buttons. In Dark Mode the light
/// surfaces (frames, title bars, plates, buttons) dim and the glass goes deeper, like the same
/// windows at night; the lettering on them stays as it is.
enum HUDStyle {
    static let cream = Color(red: 1, green: 0.97, blue: 0.88)
    static let gold = Color(red: 1, green: 0.84, blue: 0.28)
    /// Coins on the tan plates, where `gold` all but disappears.
    static let coin = Color(red: 0.93, green: 0.6, blue: 0.08)
    static let nameYellow = Color(red: 1, green: 0.95, blue: 0.35)
    static let hp = Color(red: 0.93, green: 0.22, blue: 0.2)
    static let mp = Color(red: 0.24, green: 0.52, blue: 0.95)
    static let exp = Color(red: 0.55, green: 0.88, blue: 0.3)
    static let green = Color(red: 0.6, green: 0.97, blue: 0.62)
    static let dim = Color(red: 0.86, green: 0.92, blue: 1).opacity(0.7)
    /// Deep navy: window glass and dark text on light buttons.
    static let ink = Color(red: 0.06, green: 0.15, blue: 0.3)
    static let orange = Color(red: 0.98, green: 0.52, blue: 0.16)
    /// The close button's lit top and shaded foot, either side of `orange`.
    static let closeLight = Color(red: 1, green: 0.75, blue: 0.4)
    static let closeDeep = Color(red: 0.75, green: 0.3, blue: 0.05)
    /// The dark track under a bar's fill (at 85%).
    static let barTrack = Color(red: 0.05, green: 0.1, blue: 0.2)

    static let frameLight = Color.adaptive(light: Color(red: 0.86, green: 0.96, blue: 1), dark: Color(red: 0.42, green: 0.56, blue: 0.72))
    static let frameMid = Color.adaptive(light: Color(red: 0.5, green: 0.77, blue: 0.95), dark: Color(red: 0.24, green: 0.4, blue: 0.6))
    static let frameDark = Color.adaptive(light: Color(red: 0.15, green: 0.35, blue: 0.62), dark: Color(red: 0.08, green: 0.18, blue: 0.36))
    static let plate = Color.adaptive(light: Color(red: 0.97, green: 0.88, blue: 0.64), dark: Color(red: 0.78, green: 0.68, blue: 0.48))
    static let plateDark = Color.adaptive(light: Color(red: 0.55, green: 0.41, blue: 0.18), dark: Color(red: 0.34, green: 0.24, blue: 0.09))
    /// A plate's lit top edge and its shaded foot.
    static let plateLight = Color.adaptive(light: Color(red: 1, green: 0.95, blue: 0.78), dark: Color(red: 0.86, green: 0.77, blue: 0.58))
    static let plateShade = Color.adaptive(light: Color(red: 0.86, green: 0.72, blue: 0.44), dark: Color(red: 0.64, green: 0.52, blue: 0.32))

    /// The light buttons' face (`PixelButtonStyle`, the title's round buttons) and the shine along
    /// their top: cream and white, a softer parchment in Dark Mode so they don't glare.
    static let buttonFace = Color.adaptive(light: cream, dark: Color(red: 0.84, green: 0.8, blue: 0.7))
    static let buttonShine = Color.adaptive(light: .white, dark: Color(red: 0.93, green: 0.9, blue: 0.83))

    /// Behind a face in a portrait circle: cream, fading to sky blue at the rim. Dimmer in Dark
    /// Mode, still light enough for the face's dark outline.
    static let portrait = Color.adaptive(light: Color(red: 0.98, green: 0.95, blue: 0.85), dark: Color(red: 0.76, green: 0.73, blue: 0.66))
    static let portraitRim = Color.adaptive(light: Color(red: 0.75, green: 0.88, blue: 0.98), dark: Color(red: 0.5, green: 0.6, blue: 0.72))

    /// The toolbar buttons' glossy blue, top to bottom (`FLIconButton`).
    static let tile = [
        Color.adaptive(light: Color(red: 0.6, green: 0.85, blue: 1), dark: Color(red: 0.3, green: 0.46, blue: 0.66)),
        Color.adaptive(light: Color(red: 0.25, green: 0.55, blue: 0.9), dark: Color(red: 0.14, green: 0.3, blue: 0.54)),
        Color.adaptive(light: Color(red: 0.12, green: 0.33, blue: 0.66), dark: Color(red: 0.07, green: 0.17, blue: 0.36)),
    ]

    static func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Fairyland Online's chat/name lettering.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// An amount in a few characters: in full below 10,000, then in thousands (12.3K, 457K),
    /// millions (1.45M) and billions (B), to three figures and rounded down, so it never shows
    /// more than you have. Numbers in `locale`'s way, like the HUD's others.
    static func short(_ amount: Int, locale: Locale = .autoupdatingCurrent) -> String {
        guard amount >= 10_000 else { return amount.formatted(.number.locale(locale)) }
        let (unit, suffix) = amount >= 1_000_000_000 ? (1_000_000_000, "B") : amount >= 1_000_000 ? (1_000_000, "M") : (1_000, "K")
        let whole = amount / unit
        let decimals = whole < 10 ? 2 : whole < 100 ? 1 : 0
        let scale = decimals == 2 ? 100 : decimals == 1 ? 10 : 1
        // Whole steps of the last figure shown, counted in integers (no rounding up in floating point).
        let value = Double(amount / (unit / scale)) / Double(scale)
        return value.formatted(.number.precision(.fractionLength(0...decimals)).locale(locale)) + suffix
    }

    static let bevel = LinearGradient(colors: [frameLight, frameMid, frameDark], startPoint: .top, endPoint: .bottom)

    /// A title bar's gloss (and the menu's row of tabs): a light sheen over the top half, then the
    /// frame's mid blue, a clear step lighter than the window's glass below it.
    static let titleGloss = LinearGradient(stops: [.init(color: frameLight, location: 0), .init(color: frameMid, location: 0.5),
                                                   .init(color: frameMid, location: 1)],
                                           startPoint: .top, endPoint: .bottom)

    /// The hard edge along a title bar's foot, so the bar and the window under it don't run together.
    static var titleEdge: some View {
        ink.opacity(0.9).frame(height: 1.5)
    }

    /// The deep-blue glass of the windows (deeper still, nearly midnight, in Dark Mode).
    static let glass = LinearGradient(
        colors: [Color.adaptive(light: Color(red: 0.13, green: 0.32, blue: 0.56).opacity(0.93), dark: Color(red: 0.07, green: 0.15, blue: 0.28).opacity(0.95)),
                 Color.adaptive(light: Color(red: 0.05, green: 0.17, blue: 0.35).opacity(0.95), dark: Color(red: 0.03, green: 0.07, blue: 0.16).opacity(0.96))],
        startPoint: .top, endPoint: .bottom
    )

    /// Every window's corners.
    static let windowRadius: CGFloat = 10

    /// A deep-blue glass window with a glossy light-blue bevel, as a background. A window with a
    /// title bar or tabs along its top uses `gameWindow()` instead, so the frame goes over them.
    static var panel: some View {
        panel(shape: RoundedRectangle(cornerRadius: windowRadius))
    }

    /// The same window in another shape (a speech bubble's), its bevel running all the way round.
    static func panel(shape: some InsettableShape) -> some View {
        shape
            .fill(glass)
            .overlay(frame(shape))
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
    }

    /// A window's frame, the same on every window and dialog: the glossy light-blue bevel with a
    /// dark inner edge, which sets it off from a light title bar, and a faint white line inside
    /// that catches the light on the glass. 4 pt in all, like the frame before it.
    static func frame(_ shape: some InsettableShape) -> some View {
        ZStack {
            shape.strokeBorder(bevel, lineWidth: 3)
            shape.inset(by: 2).strokeBorder(frameDark.opacity(0.85), lineWidth: 1)
            shape.inset(by: 3).strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// Tan info plate (like Fairyland Online's calendar and coordinates boxes).
    static var plateBackground: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: [plateLight, plate, plateShade], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(plateDark, lineWidth: 1.5))
    }
}

/// A toast: one short message, cream on a dark rounded plate, two lines at most. The battle's line of
/// what just happened (`BattleView`) and the map's (`WorldHUD`'s GameToasts) are the same, so every
/// message the game pops up looks alike (playtesting 2026-10-24: black pills down the right on the map).
struct ToastLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HUDStyle.font(12))
            .foregroundStyle(HUDStyle.cream)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HUDStyle.ink.opacity(0.78)))
    }
}

/// Glossy Fairyland Online-style bar: coloured fill with a white shine, dark inset track.
struct StatBar: View {
    let label: String
    let value: Int
    let maximum: Int
    let color: Color
    var labelWidth: CGFloat = 28
    var height: CGFloat = 11
    var showsNumbers = true
    /// The label's and the numbers' sizes (bigger on the Character screen).
    var labelSize: CGFloat = 10
    var numberSize: CGFloat = 8

    private var fraction: CGFloat {
        maximum > 0 ? min(1, max(0, CGFloat(value) / CGFloat(maximum))) : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .frame(width: labelWidth, alignment: .leading)
            }
            GlossyBar(fraction: fraction, color: color, height: height)
                .overlay {
                    if showsNumbers {
                        Text("\(value)/\(maximum)")
                            .font(HUDStyle.mono(numberSize))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 0, x: 1, y: 1)
                    }
                }
        }
        .font(HUDStyle.font(labelSize))
        .foregroundStyle(HUDStyle.cream)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

struct GlossyBar: View {
    let fraction: CGFloat
    let color: Color
    var height: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HUDStyle.barTrack.opacity(0.85))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color, color.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(height, proxy.size.width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.45)).frame(height: height * 0.35).padding(.horizontal, 3).padding(.top, 1)
                    }
            }
        }
        .frame(height: height)
        .overlay(Capsule().strokeBorder(HUDStyle.frameDark.opacity(0.9), lineWidth: 1))
    }
}

/// A window title bar with an orange close button, like Fairyland Online's panels.
struct FLTitleBar: View {
    let title: String
    var icon: GameIcon?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let icon { IconImage(icon, size: 16) }
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            OrangeCloseButton(action: onClose)
        }
        .font(HUDStyle.font(14))
        .foregroundStyle(.white)
        .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 8)
                .fill(HUDStyle.titleGloss)
                .overlay(alignment: .bottom) { HUDStyle.titleEdge }
        )
    }
}

struct OrangeCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconImage(.close, size: 13)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(RadialGradient(colors: [HUDStyle.closeLight, HUDStyle.orange, HUDStyle.closeDeep], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 16))
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                )
        }
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
        .accessibilityLabel(L("Close"))
    }
}

extension View {
    /// The orange close button in a window's top-right corner, just where a title bar puts it,
    /// for windows without one: every window closes the same way. Keep the window's own top line
    /// clear of the corner.
    func windowCloseButton(_ action: @escaping () -> Void) -> some View {
        overlay(alignment: .topTrailing) {
            OrangeCloseButton(action: action)
                .padding(.top, 5)
                .padding(.trailing, 6)
        }
    }
}

/// Glossy square toolbar button (Fairyland Online's top-right / hotbar icons), optionally captioned.
struct FLIconButton: View {
    let icon: GameIcon
    let label: String
    var size: CGFloat = 46
    var badge: Bool = false
    /// Writes the label under the button, so it's clear what it opens.
    var showsLabel = false
    let action: () -> Void

    var body: some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            action()
        } label: {
            VStack(spacing: 2) {
                tile
                if showsLabel {
                    Text(label)
                        .font(HUDStyle.font(10))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: size + 8)
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private var tile: some View {
        IconImage(icon, size: size * 0.5)
            .foregroundStyle(.white)
            .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: HUDStyle.tile, startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(HUDStyle.bevel, lineWidth: 2.5))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.35)).frame(height: size * 0.3).padding(4)
                    }
            )
            .overlay(alignment: .topTrailing) {
                if badge {
                    Circle().fill(HUDStyle.gold).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 2)
    }
}

/// The game's on/off switch: gold when on; off, a well a shade darker than the panel, so the switch
/// still reads as one. VoiceOver hears a standard switch.
struct PixelSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 0)
            Capsule()
                .fill(configuration.isOn ? HUDStyle.gold : Color.black.opacity(0.32))
                .overlay(Capsule().strokeBorder(.white.opacity(configuration.isOn ? 0 : 0.14), lineWidth: 1))
                .frame(width: 51, height: 31)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 27, height: 27)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1)
                        .padding(2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityRepresentation {
            // The system switch, so this style doesn't draw itself again inside its own stand-in.
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Pixel art from ArtLibrary, scaled up with crisp square pixels.
/// A walking sprite on the spot: one step cycle, then a turn to face the next way (down, right, up,
/// left), so you see the whole outfit in motion.
struct WalkingSprite: View {
    let art: String
    var size: CGFloat = 156
    /// A weapon in hand, held as on the map (the hero's, in the Character tab).
    var weapon: ItemDef?
    private static let frameTime = 0.125
    private static let order: [Direction] = [.down, .right, .up, .left]

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.frameTime)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.frameTime)
            let facing = Self.order[(tick / 4) % Self.order.count]
            let frames = ArtLibrary.shared.walkCycle(art).frames(facing)
            ZStack {
                if frames.isEmpty {
                    SpriteImage(art: art, size: size)
                } else {
                    Image(uiImage: UIImage(cgImage: frames[tick % frames.count].cgImage()))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                }
                if let weapon, let held = GearArt.heldImage(weapon, facing: facing) {
                    let hand = frames.isEmpty ? nil : GearArt.hand(in: frames[tick % frames.count], facing: facing)
                    HeldWeapon(image: held.image, grip: held.grip, scale: held.scale, facing: facing, size: size, hand: hand)
                        // In front of the body where the hand holding it is nearer you, behind it where
                        // it's farther, as on the map (GearArt.pose).
                        .zIndex(facing == .down || facing == .right ? 1 : -1)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// A weapon in a walking sprite's hand, posed for the way they face like `GearArt.pose` does on
/// the map: at the hand in the frame showing (`hand`, a unit point, y up), or where it usually is.
private struct HeldWeapon: View {
    let image: UIImage
    /// The grip as a unit point, y up (an anchor point).
    let grip: CGPoint
    let scale: CGFloat
    let facing: Direction
    let size: CGFloat
    let hand: CGPoint?

    var body: some View {
        let side = size * scale
        let mirrored = facing == .up || facing == .left
        let spot = hand ?? CGPoint(x: facing == .left ? 0.42 : facing == .right ? 0.56 : facing == .up ? 0.33 : 0.6, y: 0.4)
        let point = CGPoint(x: size * spot.x, y: size * (1 - spot.y))
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .frame(width: side, height: side)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .position(x: point.x + (mirrored ? -1 : 1) * (0.5 - grip.x) * side, y: point.y + (grip.y - 0.5) * side)
    }
}

struct SpriteImage: View {
    let art: String
    var size: CGFloat = 64

    var body: some View {
        Image(uiImage: ArtLibrary.shared.image(art))
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Glossy pill button (light, with dark text).
extension HUDStyle {
    /// Name colour for friends travelling in your party.
    static let partyGreen = UIColor(red: 0.55, green: 1, blue: 0.55, alpha: 1)
}

extension PlayerBadge {
    /// Its pill's colour: slate for BOT.
    var uiColor: UIColor {
        switch self {
        case .bot: UIColor(red: 0.42, green: 0.5, blue: 0.64, alpha: 1)
        }
    }
}

/// BOT in a little pill after someone's name, as on their name tag over their head.
struct NameBadge: View {
    let badge: PlayerBadge

    var body: some View {
        Text(badge.title)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color(uiColor: badge.uiColor)))
            .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
            .accessibilityLabel(L("bot"))
    }
}

struct PixelButtonStyle: ButtonStyle {
    var tint: Color = HUDStyle.buttonFace
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HUDStyle.font(compact ? 11 : 13))
            .foregroundStyle(HUDStyle.ink)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 9)
            .background(
                // Only the face casts the shadow, under the button. The outline goes on after it: a
                // shadow on both draws the outline's again inside the face, 3 pt below its top edge.
                Capsule()
                    .fill(LinearGradient(colors: [HUDStyle.buttonShine, tint, tint.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: configuration.isPressed ? 0 : 3)
                    .overlay(Capsule().strokeBorder(HUDStyle.frameDark.opacity(0.7), lineWidth: 1.5))
            )
            .offset(y: configuration.isPressed ? 2 : 0)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundEffects.shared.play(.tap, volume: 0.7) }
            }
    }
}

/// HStack in landscape, VStack in portrait.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        if verticalSizeClass == .compact {
            HStack(alignment: .top, spacing: spacing, content: content)
        } else {
            VStack(alignment: .leading, spacing: spacing, content: content)
        }
    }
}

/// As tall as its content would like, like `.fixedSize(horizontal: false, vertical: true)`, but
/// never taller than the room on offer: on a short screen (a phone on its side) a window's
/// scrolling part gives way, instead of the window running off the top and bottom.
struct FitHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        return view.sizeThatFits(fitted(proposal, view))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(bounds.size))
    }

    /// The width on offer, and the content's own height if there's room for it.
    private func fitted(_ proposal: ProposedViewSize, _ view: LayoutSubview) -> ProposedViewSize {
        let ideal = view.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height
        return ProposedViewSize(width: proposal.width, height: min(ideal, proposal.height ?? ideal))
    }
}

extension View {
    /// As tall as it would like, but no taller than the room on offer (see `FitHeight`).
    func fitHeight() -> some View {
        FitHeight { self }
    }
}

/// Its content as tall as it needs, or, on a screen too short for all of it (a phone on its
/// side), the same content scrolling in the room there is.
struct FitOrScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content()
            ScrollView { content() }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

extension Stats {
    /// "ATK +4 · DEF +2" for item descriptions.
    var bonusSummary: String {
        [(L("HP"), hp), (L("MP"), mp), (L("ATK"), attack), (L("DEF"), defense), (L("MAG"), magic), (L("SPD"), speed)]
            .filter { $0.1 != 0 }
            .map { "\($0.0) +\($0.1)" }
            .joined(separator: " · ")
    }
}

/// A friendly "nothing here yet" line, centred in the space it's given. Use "\n" to pick
/// where it breaks so it wraps into even lines.
struct EmptyNote: View {
    let text: String
    var size: CGFloat = 12

    init(_ text: String, size: CGFloat = 12) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(HUDStyle.font(size))
            .foregroundStyle(HUDStyle.dim)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }
}

/// Opening like a drawer, for what a tap shows under a row (a quest's reward, a finished quest's
/// story): the part unrolls down from its top edge, clipped as it grows, and the rows below slide
/// along with it, rather than just fading in. Use it with a spring, `Reveal.animation`.
extension AnyTransition {
    static var reveal: AnyTransition {
        .modifier(active: Reveal(shown: false), identity: Reveal(shown: true))
    }
}

struct Reveal: ViewModifier {
    let shown: Bool

    /// Quick to open, settling without a wobble.
    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.86)

    // `Self.Content`: plain `Content` is the game's data store.
    func body(content: Self.Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: shown ? nil : 0, alignment: .top)
            .clipped()
            .opacity(shown ? 1 : 0)
    }
}

extension View {
    /// The game's window around this content: deep-blue glass behind it, the content clipped to the
    /// window's shape, and the frame drawn over it all the way round, so a title bar or tabs along
    /// the top sit inside the frame instead of covering it. Every modal and dialog uses it.
    func gameWindow(_ shape: some InsettableShape) -> some View {
        clipShape(shape)
            .background(shape.fill(HUDStyle.glass).shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2))
            .overlay(HUDStyle.frame(shape))
    }

    func gameWindow() -> some View {
        gameWindow(RoundedRectangle(cornerRadius: HUDStyle.windowRadius))
    }
}

/// A modal window popping in: from a touch smaller to full size. Only the window scales; the
/// modal's dimmed backdrop just fades (present the modal with `.transition(.opacity)`), so the
/// backdrop covers the whole screen from the first frame instead of shrinking with the window.
private struct PopIn: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Self.Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { shown = true }
            }
    }
}

extension View {
    /// See `PopIn`.
    func popIn() -> some View { modifier(PopIn()) }
}
