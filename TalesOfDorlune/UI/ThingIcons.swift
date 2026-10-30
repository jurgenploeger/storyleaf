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
                // Glossy top, like Fairyland Online's inventory icons.
                Capsule().fill(.white.opacity(0.28)).frame(height: size * 0.22).padding(.horizontal, size * 0.14).padding(.top, size * 0.08)
            }
            .overlay {
                if let picture {
                    // Pixel art stays crisp; the skills' icons, drawn as light at 128 pixels, smooth.
                    Image(uiImage: picture)
                        .interpolation(picture.size.width > 64 ? .high : .none)
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
        // A quest treasure (`Content.questGiving`) has a gold frame, and a sparkle once there's room.
        let treasure = Content.shared.isTreasure(item.id)
        IconTile(icon: item.icon.flatMap(GameIcon.init) ?? .gift, tint: tint, size: size,
                 picture: item.art.flatMap(ArtLibrary.shared.artImage))
            .overlay {
                if treasure {
                    RoundedRectangle(cornerRadius: size * 0.26)
                        .strokeBorder(LinearGradient(colors: [HUDStyle.gold, Color(red: 1, green: 0.6, blue: 0.85), HUDStyle.gold],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: max(1.5, size * 0.07))
                        .shadow(color: HUDStyle.gold.opacity(0.6), radius: size * 0.08)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if treasure && size >= 28 { TreasureBadge(size: min(17, size * 0.36)).offset(x: -4, y: 4) }
            }
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
        case .cape: Color(red: 0.78, green: 0.36, blue: 0.62)
        case .head: Color(red: 0.92, green: 0.5, blue: 0.28)
        case .material: Color(red: 0.55, green: 0.6, blue: 0.4)
        }
    }
}

/// The coins you carry, in their slot of the bag as RuneScape's pack shows them (playtesting
/// 2026-10-25): a pile that grows with the amount (`item_coins_1` to `_4`, tools/coin_art.py), the amount
/// in its top-left corner, yellow under 100,000, white under 10 million, green from there.
struct CoinsTile: View {
    let amount: Int
    var size: CGFloat = 32

    /// The pile for an amount: one coin, a few, a stack, a heap.
    static func art(for amount: Int) -> String {
        "item_coins_" + (amount < 5 ? "1" : amount < 100 ? "2" : amount < 10_000 ? "3" : "4")
    }

    var body: some View {
        IconTile(icon: .coins, tint: Color(red: 0.62, green: 0.48, blue: 0.24), size: size,
                 picture: ArtLibrary.shared.artImage(Self.art(for: amount)))
            .overlay(alignment: .topLeading) {
                Text(HUDStyle.short(amount))
                    .font(HUDStyle.mono(max(9, size * 0.2)))
                    .foregroundStyle(amount < 100_000 ? Color(red: 1, green: 0.95, blue: 0.2) : amount < 10_000_000 ? .white : Color(red: 0.3, green: 1, blue: 0.45))
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .padding(.leading, size * 0.08)
                    .padding(.top, size * 0.04)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("{gold} gold", ["gold": amount]))
    }
}

/// An amount of gold as Pixel Heroes shows it (playtesting 2026-10-26: "just a coin with numbers in a
/// pill"): the bag's coin (`item_coins_1`) over the left end of a dark pill, the amount in it in light
/// figures, the same on any backdrop. `size` is the figures' point size; `short` puts a big amount in
/// a few characters (`HUDStyle.short`), and `sign` goes before it ("+" for gold just won).
struct GoldPill: View {
    let amount: Int
    var size: CGFloat = 13
    var short = false
    var sign = ""

    var body: some View {
        let coin = (size * 1.75).rounded()
        Text(sign + (short ? HUDStyle.short(amount) : amount.formatted()))
            .font(HUDStyle.mono(size))
            .monospacedDigit()
            .foregroundStyle(HUDStyle.cream)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, coin * 0.62)
            .padding(.trailing, size * 0.75)
            .frame(height: (size * 1.6).rounded())
            // No outline (playtesting 2026-10-30: the gold rim can go).
            .background(Capsule().fill(Color.black.opacity(0.55)))
            // The coin hangs over the pill's left end, its middle on the end's.
            .padding(.leading, coin * 0.38)
            .overlay(alignment: .leading) {
                Group {
                    if let picture = ArtLibrary.shared.artImage(CoinsTile.art(for: 1)) {
                        Image(uiImage: picture).resizable().interpolation(.none)
                    } else {
                        IconImage(.coins, size: coin * 0.8).foregroundStyle(HUDStyle.gold)
                    }
                }
                .frame(width: coin, height: coin)
                .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("{gold} gold", ["gold": amount]))
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

/// A quest treasure (`Content.questGiving`): sparkles on a rose badge, like `UpgradeBadge`.
struct TreasureBadge: View {
    var size: CGFloat = 17

    var body: some View {
        IconImage(.sparkles, size: size * 0.62)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 0.86, green: 0.36, blue: 0.62)))
            .overlay(Circle().strokeBorder(HUDStyle.gold, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .accessibilityLabel(L("Quest treasure"))
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
