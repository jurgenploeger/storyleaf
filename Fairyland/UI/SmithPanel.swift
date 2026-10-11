import SwiftUI

/// A town blacksmith: pick a weapon line, see what each recipe needs, and forge it.
struct SmithPanel: View {
    let session: GameSession
    @Binding var reply: String?
    /// Tap a weapon for everything about it (who can use it, how it compares with yours).
    @Binding var info: ItemDef?
    @State private var line: String?

    private struct WeaponLine: Identifiable {
        /// Weapons are drawn in the hero's hand by their icon, so it also names the line.
        let icon: String
        let name: String
        var id: String { icon }
    }

    private static var lines: [WeaponLine] { [
        WeaponLine(icon: "sword", name: L("Swords")), WeaponLine(icon: "axe", name: L("Axes")),
        WeaponLine(icon: "wand", name: L("Staffs")), WeaponLine(icon: "paw", name: L("Whips")),
    ] }

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
        let shown = session.recipes.filter { $0.icon == chosen && ($0.level ?? 1) >= level - 15 && ($0.level ?? 1) <= level + 10 }
        VStack(alignment: .leading, spacing: 8) {
            // The weapon lines in a row when they fit, two by two when they don't (a narrow panel, longer
            // names), each name on one line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(Self.lines) { tab($0, chosen: chosen, fill: false) }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(Self.lines) { tab($0, chosen: chosen, fill: true) }
                }
            }
            if shown.isEmpty {
                EmptyNote(L("Nothing to forge in this line at your level."))
            }
            ForEach(shown) { item in
                SmithRecipeRow(session: session, item: item, reply: $reply, info: $info)
            }
        }
    }

    /// `fill`: as wide as its grid column, the name shrunk a little if it must be.
    private func tab(_ option: WeaponLine, chosen: String, fill: Bool) -> some View {
        Button { line = option.icon } label: {
            Text(option.name)
                .lineLimit(1)
                .minimumScaleFactor(fill ? 0.7 : 1)
                .fixedSize(horizontal: !fill, vertical: false)
                .frame(maxWidth: fill ? .infinity : nil)
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
                // Tap the weapon for everything about it (who can use it, how it compares with yours).
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
