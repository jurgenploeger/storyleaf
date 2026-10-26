import SwiftUI

/// A town blacksmith: pick a weapon line or armour, see what each recipe needs, and forge it. Armour
/// (playtesting 2026-10-25: "I should be able to create armor with metals I have found") is the
/// metal and gem sets, plate, robe and hide: forged from what monsters drop, worn, sold or traded.
struct SmithPanel: View {
    let session: GameSession
    @Binding var reply: String?
    /// Tap a weapon for everything about it (who can use it, how it compares with yours).
    @Binding var info: ItemDef?
    @State private var line: String?

    private struct WeaponLine: Identifiable {
        /// Weapons are drawn in the hero's hand by their icon, so it also names the line; armour's is
        /// `armor`, every kind of it.
        let icon: String
        let name: String
        var id: String { icon }
    }

    private static var lines: [WeaponLine] { [
        WeaponLine(icon: "sword", name: L("Swords")), WeaponLine(icon: "axe", name: L("Axes")),
        WeaponLine(icon: "wand", name: L("Staffs")), WeaponLine(icon: "paw", name: L("Whips")),
        WeaponLine(icon: "armor", name: L("Armor")),
    ] }

    private static func belongs(_ item: ItemDef, to line: String) -> Bool {
        line == "armor" ? item.type == .armor : item.type == .weapon && item.icon == line
    }

    /// Starts on the line the hero's class fights with.
    private var defaultLine: String {
        switch session.data.hero.classID {
        case "mage": "wand"
        case "tamer": "paw"
        default: "sword"
        }
    }

    var body: some View {
        let chosen = line ?? defaultLine
        let level = session.data.hero.level
        // Around the hero's level: a little behind (to catch up) and a little ahead (to aim for).
        let shown = session.recipes.filter { Self.belongs($0, to: chosen) && ($0.level ?? 1) >= level - 15 && ($0.level ?? 1) <= level + 10 }
        VStack(alignment: .leading, spacing: 8) {
            // The weapon lines in a row, each name whole, scrolling sideways when they don't all fit
            // (playtesting 2026-10-26: "If it doesn't fit, there should just be a horizontal scroll").
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.lines) { tab($0, chosen: chosen) }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            if shown.isEmpty {
                EmptyNote(L("Nothing to forge in this line at your level."))
            }
            ForEach(shown) { item in
                SmithRecipeRow(session: session, item: item, reply: $reply, info: $info)
            }
        }
    }

    private func tab(_ option: WeaponLine, chosen: String) -> some View {
        Button { line = option.icon } label: {
            Text(option.name)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PixelButtonStyle(tint: option.icon == chosen ? HUDStyle.gold : HUDStyle.dim, compact: true))
    }
}

private struct SmithRecipeRow: View {
    let session: GameSession
    let item: ItemDef
    @Binding var reply: String?
    @Binding var info: ItemDef?

    var body: some View {
        let ready = session.canCraft(item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                // Tap it for everything about it (who can use it, how it compares with yours).
                Button { info = item } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ItemIcon(item: item, size: 36)
                        details
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Shows what it does and who can use it"))
                forge(ready: ready)
            }
            // Under the name, past the icon.
            Group {
                materials
                if let issue = session.equipIssue(item) {
                    Text(issue).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.orange)
                }
            }
            .padding(.leading, 46)
        }
        .font(HUDStyle.font(12))
    }

    private func forge(ready: Bool) -> some View {
        Button(L("Forge")) {
            if session.craft(item.id) {
                session.post(L("Forged a {item}!", ["item": item.name]), .reward)
                session.save()
                reply = L("Clang, clang… done! One {item}, fresh from the anvil.", ["item": item.name])
            } else {
                reply = L("You're missing some materials. Monsters out in the wilds drop them.")
            }
        }
        .buttonStyle(PixelButtonStyle(tint: ready ? HUDStyle.gold : HUDStyle.dim, compact: true))
        .fixedSize()
    }

    /// Name and level, and its stats.
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("{item}  ·  Lv {level}", ["item": item.name, "level": item.level ?? 1]))
            Text(item.stats?.bonusSummary ?? "").font(HUDStyle.font(10)).foregroundStyle(HUDStyle.green)
        }
    }

    /// The materials it takes and how many you have of each, under the whole row and wrapping onto
    /// more lines as they need: four in a row squeezed each name into a column of letters.
    private var materials: some View {
        WrapRows(spacing: 10) {
            ForEach(session.ingredients(of: item)) { part in
                HStack(spacing: 3) {
                    ItemIcon(item: part.material, size: 16)
                    Text("\(part.material.name) \(part.owned)/\(part.needed)")
                        .lineLimit(1)
                        .foregroundStyle(part.owned >= part.needed ? HUDStyle.green : HUDStyle.dim)
                }
            }
        }
        .font(HUDStyle.font(10))
    }
}
