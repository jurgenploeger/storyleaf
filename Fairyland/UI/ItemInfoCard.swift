import SwiftUI

/// Everything about an item, shown when you tap it in a trade or a shop: what it is and does, who
/// can use it from what level, how it compares with what you're wearing, what it's for (materials)
/// and what it's worth.
struct ItemInfoCard: View {
    let session: GameSession
    let item: ItemDef
    let onClose: () -> Void
    /// Choosing gear (Character → Change): Cancel and Equip under the details, or Unequip for
    /// what you're wearing. Nil in shops and trades, where the card only tells.
    var onEquip: (() -> Void)? = nil
    var onUnequip: (() -> Void)? = nil
    /// From the Bag: what you can do with it there (Use, Give, Hatch), under the details.
    var action: Action? = nil
    /// From the Bag, when there's nothing to do with it there: why (only in battle, no companions).
    var note: String? = nil

    struct Action {
        let title: String
        var icon: GameIcon?
        var enabled = true
        let run: () -> Void
    }

    private var choosing: Bool { onEquip != nil || onUnequip != nil || action != nil || note != nil }

    private var isGear: Bool { ItemType.equipmentSlots.contains(item.type) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                // Scrolls only when it can't all fit (a phone on its side).
                FitOrScroll {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        if let text = item.description, !text.isEmpty {
                            Text(text)
                                .font(HUDStyle.font(12))
                                .foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if isGear {
                            requirements
                            if let stats = item.stats, !Self.parts(of: stats).isEmpty {
                                section(L("Stats")) { chips(Self.parts(of: stats)) }
                            }
                            comparison
                        }
                        effects
                        if item.type == .material {
                            materialUse
                        }
                        footer
                    }
                    .padding(16)
                }
                // Cancel and Equip stay in view under the details, even when those scroll.
                if choosing {
                    actions
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .gameWindow()
            // In the corner, so it stays put when the details scroll.
            .windowCloseButton(onClose)
            .padding(24)
            .popIn()
            .accessibilityElement(children: .contain)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(HUDStyle.font(17))
                    .foregroundStyle(HUDStyle.gold)
                Text(kind)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.dim)
            }
            Spacer(minLength: 0)
        }
        // Clear of the close button in the corner.
        .padding(.trailing, 24)
    }

    /// Cancel, and Equip (faded, with why, when you can't) or Unequip.
    private var actions: some View {
        let issue = onUnequip == nil ? session.equipIssue(item) : nil
        return VStack(alignment: .trailing, spacing: 6) {
            if let issue {
                Text(issue).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.orange)
            }
            if let note {
                Text(note).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(action == nil && onEquip == nil && onUnequip == nil ? L("Close") : L("Cancel"), action: onClose)
                    .buttonStyle(PixelButtonStyle())
                if let action {
                    Button(action: action.run) {
                        if let icon = action.icon {
                            Label(action.title, icon: icon)
                        } else {
                            Text(action.title)
                        }
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .disabled(!action.enabled)
                    .opacity(action.enabled ? 1 : 0.5)
                } else if let onUnequip {
                    Button(L("Unequip"), action: onUnequip)
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                } else if let onEquip {
                    Button(L("Equip"), action: onEquip)
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                        .disabled(issue != nil)
                        .opacity(issue == nil ? 1 : 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }

    /// "Weapon", "Material · Metal", "Egg"…
    private var kind: String {
        if item.hatches != nil { return L("Egg") }
        if item.toy == true { return L("Toy") }
        if item.type == .material, let material = item.material {
            let name: String = switch material {
            case "gem": L("Gem")
            case "hide": L("Hide")
            case "metal": L("Metal")
            case "wood": L("Wood")
            default: material.capitalized
            }
            return L("Material · {material}", ["material": name])
        }
        return item.type.displayName
    }

    // MARK: - Gear

    /// From what level, and which classes; ticked when you qualify.
    private var requirements: some View {
        let hero = session.data.hero
        return section(L("Who can use it")) {
            VStack(alignment: .leading, spacing: 5) {
                if let level = item.level {
                    requirement(hero.level >= level, hero.level >= level ? L("Level {level}", ["level": level]) : L("Level {level} (you're {heroLevel})", ["level": level, "heroLevel": hero.level]))
                }
                if let classes = item.classes {
                    let names = classes.map { session.content.classDef($0).name }.joined(separator: ", ")
                    requirement(classes.contains(hero.classID), L("{classes} only", ["classes": names]))
                }
                if item.level == nil && item.classes == nil {
                    requirement(true, L("Anyone"))
                }
            }
        }
    }

    private func requirement(_ met: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            IconImage(met ? .checkCircle : .lock, size: 14)
                .foregroundStyle(met ? HUDStyle.green : HUDStyle.orange)
            Text(text)
                .font(HUDStyle.font(12))
                .foregroundStyle(met ? HUDStyle.cream : HUDStyle.orange)
        }
    }

    /// Against what you wear in that slot: each stat it would raise or lower.
    @ViewBuilder
    private var comparison: some View {
        let worn = session.equipped(item.type)
        if worn?.id == item.id {
            Text(L("You're wearing one.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
        } else if let worn {
            let gained: Stats = item.stats ?? Stats.zero
            let lost: Stats = worn.stats ?? Stats.zero
            let change = Self.parts(of: gained + lost * -1)
            section(L("Instead of your {item}", ["item": worn.name])) {
                if change.isEmpty {
                    Text(L("The same stats.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                } else {
                    chips(change)
                }
            }
        } else {
            Text(L("You have no {type} on.", ["type": item.type.displayName.midSentence])).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
        }
    }

    // MARK: - Potions, eggs, materials

    @ViewBuilder
    private var effects: some View {
        let both: [(label: String, value: Int)] = [(L("HP"), item.heal ?? 0), (L("MP"), item.mp ?? 0)]
        let restores = both.filter { $0.value > 0 }
        if !restores.isEmpty {
            section(L("Restores")) { chips(restores) }
        }
        if let species = item.hatches, !species.isEmpty {
            let names = species.compactMap { session.content.monster($0)?.name }.joined(separator: ", ")
            section(L("Hatches")) {
                Text(names).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.cream)
            }
        }
        if item.toy == true, let raise = item.stats, !Self.parts(of: raise).isEmpty {
            section(L("Raises a companion's stats for good")) { chips(Self.parts(of: raise)) }
            Text(L("Up to {count} toys a companion. Give it from your Bag.", ["count": GameSession.toysPerCompanion]))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
        }
    }

    /// Where it drops and what the smith makes of it.
    private var materialUse: some View {
        let uses = session.recipes.filter { $0.recipe?[item.id] != nil }.map(\.name)
        let shown = uses.count > 4 ? L("{items} and {count} more", ["items": uses.prefix(4).joined(separator: ", "), "count": uses.count - 4]) : uses.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 10) {
            if let level = item.level {
                section(L("Found on")) {
                    Text(L("Monsters of level {level} and up", ["level": level])).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.cream)
                }
            }
            section(L("A smith forges it into")) {
                Text(uses.isEmpty ? L("Nothing yet.") : shown)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// How many you have, and what shops ask and pay.
    private var footer: some View {
        let owned = session.count(of: item.id)
        let worn = isGear && session.equipped(item.type)?.id == item.id
        var lines: [String] = []
        if owned > 0 || worn {
            lines.append(worn ? L("You have {count} in your bag, and one on", ["count": owned]) : L("You have {count}", ["count": owned]))
        }
        if item.price > 0 {
            lines.append(L("Shops sell it for {price}g and pay {gold}g", ["price": item.price, "gold": GameSession.sellPrice(of: item)]))
        }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            content()
        }
    }

    /// "ATK +12" pills, green for a gain and orange for a loss.
    private func chips(_ values: [(label: String, value: Int)]) -> some View {
        WrapRows(spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, part in
                chip(part.label, part.value)
            }
        }
    }

    private func chip(_ label: String, _ value: Int) -> some View {
        let sign: String = value >= 0 ? "+\(value)" : "−\(-value)"
        let amount: Text = Text(sign).foregroundStyle(value >= 0 ? HUDStyle.green : HUDStyle.orange)
        let text: Text = Text(label + " ").foregroundStyle(HUDStyle.cream) + amount
        return text
            .font(HUDStyle.font(11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.08)))
    }

    /// The stats that aren't zero, in the Character tab's order.
    private static func parts(of stats: Stats) -> [(label: String, value: Int)] {
        let all: [(label: String, value: Int)] = [
            (L("HP"), stats.hp), (L("MP"), stats.mp), (L("ATK"), stats.attack),
            (L("DEF"), stats.defense), (L("MAG"), stats.magic), (L("SPD"), stats.speed),
        ]
        return all.filter { $0.value != 0 }
    }
}

/// Lays its views out like words: left to right, onto a new row when one is full (an item's stats,
/// the titles you've earned).
struct WrapRows: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
