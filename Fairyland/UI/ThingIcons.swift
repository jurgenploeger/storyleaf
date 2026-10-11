import SwiftUI

/// A little square badge with an icon on a tinted tile, like an inventory slot.
struct IconTile: View {
    let icon: GameIcon
    let tint: Color
    var size: CGFloat = 32
    /// Pixel art shown instead of the icon when there is some.
    var picture: UIImage? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26)
            .fill(tint)
            .overlay(RoundedRectangle(cornerRadius: size * 0.26)
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.22)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            .overlay(alignment: .top) {
                // Glossy top, like Fairyland's inventory icons.
                Capsule().fill(.white.opacity(0.28)).frame(height: size * 0.22).padding(.horizontal, size * 0.14).padding(.top, size * 0.08)
            }
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.84, height: size * 0.84)
                } else {
                    IconImage(icon, size: size * 0.6)
                        .foregroundStyle(.white)
                        .shadow(color: HUDStyle.ink.opacity(0.7), radius: 0, x: 0, y: 1)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ItemIcon: View {
    let item: ItemDef
    var size: CGFloat = 32
    /// How many there are: from two up, a blue badge in the top-right corner says so.
    var count = 1
    /// Better than what the hero has on in its slot (`GameSession.isUpgrade`): the gold arrow in the
    /// top-left corner.
    var upgrade = false

    var body: some View {
        IconTile(icon: item.icon.flatMap(GameIcon.init) ?? .gift, tint: tint, size: size,
                 picture: item.art.flatMap(ArtLibrary.shared.artImage))
            .overlay(alignment: .topTrailing) {
                if count > 1 { CountBadge(count: count).offset(x: 5, y: -5) }
            }
            .overlay(alignment: .topLeading) {
                if upgrade { UpgradeBadge().offset(x: -5, y: -5) }
            }
    }

    private var tint: Color {
        switch item.type {
        case .consumable: item.mp != nil ? Color(red: 0.3, green: 0.55, blue: 0.95) : item.hatches != nil ? Color(red: 0.95, green: 0.7, blue: 0.3) : Color(red: 0.92, green: 0.35, blue: 0.45)
        case .weapon: Color(red: 0.5, green: 0.56, blue: 0.68)
        case .armor: Color(red: 0.62, green: 0.45, blue: 0.3)
        case .gloves: Color(red: 0.78, green: 0.5, blue: 0.32)
        case .necklace: Color(red: 0.85, green: 0.62, blue: 0.3)
        case .boots: Color(red: 0.4, green: 0.6, blue: 0.85)
        case .accessory: Color(red: 0.62, green: 0.4, blue: 0.85)
        case .material: Color(red: 0.55, green: 0.6, blue: 0.4)
        }
    }
}

/// Something better to wear: a gold arrow pointing up, on a badge like `CountBadge`.
struct UpgradeBadge: View {
    var size: CGFloat = 17

    var body: some View {
        IconImage(.arrowUp, size: size * 0.62)
            .foregroundStyle(HUDStyle.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(HUDStyle.gold))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .accessibilityLabel(L("Better than yours"))
    }
}

/// How many of an item there are, as a small blue badge with a white rim, like an app's badge.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(HUDStyle.font(10))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(Capsule().fill(Color(red: 0.16, green: 0.47, blue: 0.95)))
            .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .fixedSize()
    }
}

struct SkillIcon: View {
    let skill: SkillDef
    var size: CGFloat = 32

    var body: some View {
        IconTile(icon: skill.icon.flatMap(GameIcon.init) ?? .sparkles, tint: tint, size: size,
                 picture: skill.art.flatMap(ArtLibrary.shared.artImage))
    }

    private var tint: Color { Color(uiColor: skill.tileColor) }
}

extension SkillDef {
    /// The colour behind a skill's icon: its element's, else its kind's.
    var tileColor: UIColor {
        if let element { return element.color }
        return switch kind {
        case .heal, .revive: UIColor(red: 0.3, green: 0.72, blue: 0.45, alpha: 1)
        case .buff: UIColor(red: 0.3, green: 0.55, blue: 0.85, alpha: 1)
        case .curse: UIColor(red: 0.45, green: 0.28, blue: 0.62, alpha: 1)
        case .field: UIColor(red: 0.85, green: 0.65, blue: 0.25, alpha: 1)
        case .magic: UIColor(red: 0.55, green: 0.42, blue: 0.9, alpha: 1)
        case .physical: UIColor(red: 0.85, green: 0.42, blue: 0.32, alpha: 1)
        }
    }
}
