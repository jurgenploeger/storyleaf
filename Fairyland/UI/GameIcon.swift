import SwiftUI
import UIKit

/// The game's UI icons: Iconaut's solid set (MIT, iconaut.design), vendored into
/// Assets.xcassets/Icons by tools/icons.py, plus a few of our own (art/icons: the flame). The ones
/// on buttons are also drawn as pixel art in the items' style (art/sprites/ui_<name>.png,
/// tools/ui_icon_art.py), which `IconImage` shows at button sizes.
/// Keep the cases in sync with the script's lists.
enum GameIcon: String, CaseIterable {
    case sword, sparkles, backpack, shield, wind, heart, heartPlus = "heart-plus", more, close
    case check, checkCircle = "check-circle", badgeCheck = "badge-check", plus
    case user, users, paw, book, talk, sun, moon, music, musicOff = "music-off", settings, volume
    case chevronUp = "chevron-up", chevronDown = "chevron-down"
    case arrowUp = "arrow-up", arrowDown = "arrow-down", arrowLeft = "arrow-left", arrowRight = "arrow-right"
    case play, dice, map, tap, palette, star, starOutline = "star-outline", gift, coins, egg, edit, lock, globe
    /// Finding things in a list (the Bag, the gear for a slot): search it, sort it.
    case search, sort
    /// Capture in a fight: the Seal Stone you throw.
    case sealStone = "seal-stone"
    // Items (content/items.json `icon`)
    case potion, flask, axe, wand, diamond, gem, ring, clover
    case shieldCheck = "shield-check", shieldPlus = "shield-plus", shieldStar = "shield-star", shieldHeart = "shield-heart"
    // Skills (content/skills.json `icon`)
    case hammer, firstAid = "first-aid", tornado, flame, mountain, leaf, droplet, pineTree = "pine-tree", tooth, bounce
    // Elements (with flame, droplet, leaf, mountain, sun and moon above)
    case magnet, circleDashed = "circle-dashed"

    /// Iconaut draws a simplified version for 16px and below, so small icons stay readable.
    func assetName(for size: CGFloat) -> String {
        size <= 17 ? "icon-\(rawValue)-16" : "icon-\(rawValue)"
    }
}

/// An Iconaut icon at a fixed point size, tinted by the foreground style like text.
struct IconImage: View {
    let icon: GameIcon
    var size: CGFloat = 16

    init(_ icon: GameIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        // At button size, the game's own pixel art where there is some (full colour: a tint doesn't
        // touch it); small inline glyphs stay Iconaut's.
        if size >= 18, let art = icon.pixelArt {
            Image(uiImage: art)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(icon.assetName(for: size))
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

extension GameIcon {
    /// The icon drawn as pixel art in the items' style (art/sprites/ui_<name>.png, tools/ui_icon_art.py),
    /// or nil where there isn't one.
    var pixelArt: UIImage? {
        if let known = Self.pixelArtCache[self] { return known }
        let art = ArtLibrary.shared.artImage("ui_" + rawValue)
        Self.pixelArtCache[self] = .some(art)
        return art
    }

    private static var pixelArtCache: [GameIcon: UIImage?] = [:]
}

extension Element {
    /// The element's shape, so it reads without its colour: a flame with three tongues (a teardrop
    /// flame read as water's droplet), a droplet, a leaf, a mountain, a magnet for metal, the sun,
    /// the moon, and a dashed ring for none.
    var icon: GameIcon {
        switch self {
        case .fire: .flame
        case .water: .droplet
        case .wood: .leaf
        case .earth: .mountain
        case .metal: .magnet
        case .light: .sun
        case .dark: .moon
        case .neutral: .circleDashed
        }
    }
}

extension Label where Title == Text, Icon == IconImage {
    /// `Label("Saved", icon: .checkCircle)`: like `systemImage:`, with an Iconaut icon.
    init(_ title: String, icon: GameIcon, size: CGFloat = 15) {
        self.init { Text(title) } icon: { IconImage(icon, size: size) }
    }
}
