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
    /// From the Bag (playtesting 2026-10-26: "there should be three buttons: Drop, Trade and Use"):
    /// Drop and Trade, each opening a window over the card for how many and at what price
    /// (`ItemDropWindow`, `ItemTradeWindow`), and the item's own action (`action`, or Equip for gear)
    /// as the main one. The corner button closes the card.
    var fromBag = false
    /// From the bank, on the side it was tapped on: how many to put in, take out or delete
    /// (`BankControls`), in place of Close.
    var banking: BankSide? = nil

    /// Drop's or Trade's window, over the card. Debug `itemwindow=drop` or `trade` opens one.
    @State private var window: ItemCardWindow? = DebugLaunch.itemWindow.flatMap(ItemCardWindow.init(rawValue:))
    /// Gear: the Compare row opened into each stat against what you wear. Debug `compare` opens it.
    @State private var comparing = DebugLaunch.opensComparison

    struct Action {
        let title: String
        var icon: GameIcon?
        var enabled = true
        let run: () -> Void
    }

    private var choosing: Bool { onEquip != nil || onUnequip != nil || action != nil || note != nil || fromBag || banking != nil }

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
                        if let quest = session.content.questGiving(item.id) {
                            section(L("Quest treasure")) {
                                Text(origin(of: quest))
                                    .font(HUDStyle.font(12))
                                    .foregroundStyle(HUDStyle.cream)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else if let place = session.content.chestHolding(item.id).flatMap({ session.content.home(ofNPC: $0.id) }) {
                            section(L("Summit treasure")) {
                                Text(L("Only in the treasure chest at the top of {place}. No monster drops it and no shop sells it.",
                                       ["place": place.name]))
                                    .font(HUDStyle.font(12))
                                    .foregroundStyle(HUDStyle.cream)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else if let prize = session.content.prize(for: item.id), let weaver = session.weaver {
                            // A status cape: what earns it, who weaves it, and how far along you are.
                            let progress = session.prizeProgress(prize)
                            section(L("Cape of renown")) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L("{requirement}, and {weaver} in {town} will weave it for you. No one else has one to give.",
                                           ["requirement": session.prizeRequirement(prize), "weaver": weaver.npc.name, "town": weaver.land.name]))
                                        .font(HUDStyle.font(12))
                                        .foregroundStyle(HUDStyle.cream)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(L("So far: {have} of {need}", ["have": progress.have, "need": progress.need]))
                                        .font(HUDStyle.font(11))
                                        .foregroundStyle(session.hasEarned(prize) ? HUDStyle.gold : HUDStyle.dim)
                                }
                            }
                        }
                        if isGear {
                            requirements
                            if let stats = item.stats, !Self.parts(of: stats).isEmpty {
                                section(L("Stats")) { chips(Self.parts(of: stats)) }
                            }
                            comparison
                        }
                        effects
                        // A quest's piece drops only for its quest, and no smith wants it.
                        if item.type == .material && item.material != "quest" {
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
            .accessibilityHidden(fromBag && window != nil)

            if fromBag, let window {
                Group {
                    switch window {
                    case .drop:
                        ItemDropWindow(session: session, item: item) { dropped in
                            closeWindow()
                            // The last of it gone: back to the Bag.
                            if dropped && session.count(of: item.id) == 0 { onClose() }
                        }
                    case .trade:
                        ItemTradeWindow(session: session, item: item) { closeWindow() }
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private func open(_ window: ItemCardWindow) {
        withAnimation(.easeOut(duration: 0.2)) { self.window = window }
    }

    private func closeWindow() {
        withAnimation(.easeOut(duration: 0.2)) { window = nil }
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
        let issue = onUnequip == nil && banking == nil ? session.equipIssue(item) : nil
        return VStack(alignment: .trailing, spacing: 6) {
            if let issue {
                Text(issue).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.orange)
            }
            if let note {
                Text(note).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            if fromBag, let kept = keptBack {
                Text(kept).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            if let banking {
                BankControls(session: session, item: item, side: banking, onClose: onClose)
            } else if fromBag {
                bagButtons(issue: issue)
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }

    // MARK: - From the Bag

    /// Drop, Trade, and the item's own action in gold; on a narrow card (a long action, a long
    /// language) the action over the other two.
    private func bagButtons(issue: String?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                dropButton
                tradeButton
                mainButton(issue: issue)
            }
            VStack(alignment: .trailing, spacing: 8) {
                mainButton(issue: issue)
                HStack(spacing: 10) {
                    dropButton
                    tradeButton
                }
            }
        }
    }

    /// Why it can't be dropped, if it can't: a quest you're on needs it.
    private var dropBlock: String? {
        if session.questKeepsakes.contains(item.id) { return L("A quest you're on needs it.") }
        if session.count(of: item.id) == 0 { return L("You have none.") }
        return nil
    }

    /// Why it can't go up for trade, if it can't: a quest's, worth nothing, or the list is full.
    private var tradeBlock: String? {
        if let dropBlock { return dropBlock }
        if item.price <= 0 { return L("No one trades for it.") }
        if !session.isForTrade(item.id) && session.forTrade.count >= GameSession.maxForTrade {
            return L("Up to {count} kinds of thing can be up for trade at once.", ["count": GameSession.maxForTrade])
        }
        return nil
    }

    /// One line on the card for why Drop and Trade are faded, when they are.
    private var keptBack: String? {
        dropBlock ?? tradeBlock
    }

    private var dropButton: some View {
        let block = dropBlock
        return Button { open(.drop) } label: {
            Label(L("Drop"), icon: .arrowDown)
        }
        .buttonStyle(PixelButtonStyle())
        .disabled(block != nil)
        .opacity(block == nil ? 1 : 0.5)
        .accessibilityHint(block ?? L("Choose how many to drop"))
    }

    private var tradeButton: some View {
        let block = tradeBlock
        let listed = session.isForTrade(item.id)
        return Button { open(.trade) } label: {
            Label(L("Trade"), icon: .coins)
        }
        .buttonStyle(PixelButtonStyle())
        .disabled(block != nil)
        .opacity(block == nil ? 1 : 0.5)
        .accessibilityValue(listed ? L("For trade") : "")
        .accessibilityHint(block ?? L("Choose a price and how many to sell"))
    }

    /// The item's own action (Use, Give, Hatch, Carve...), Equip for gear, or Use faded when there's
    /// nothing to do with it from the Bag.
    @ViewBuilder
    private func mainButton(issue: String?) -> some View {
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
            .accessibilityHint(action.enabled ? "" : (note ?? ""))
        } else if let onEquip {
            Button(L("Equip"), action: onEquip)
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .disabled(issue != nil)
                .opacity(issue == nil ? 1 : 0.5)
                .accessibilityHint(issue ?? "")
        } else {
            Button(L("Use")) {}
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .disabled(true)
                .opacity(0.5)
                .accessibilityHint(note ?? L("Nothing to use it for here."))
        }
    }

    /// Where a quest treasure comes from: the quest, who gives it and where they live.
    private func origin(of quest: QuestDef) -> String {
        let content = session.content
        let giver = content.npc(quest.giver)?.name ?? quest.giver
        if let place = content.home(ofNPC: quest.giver)?.name {
            return L("Only from the quest “{quest}”, from {giver} in {place}. No monster drops it and no shop sells it.",
                     ["quest": quest.title, "giver": giver, "place": place])
        }
        return L("Only from the quest “{quest}”, from {giver}. No monster drops it and no shop sells it.", ["quest": quest.title, "giver": giver])
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
            case "quest": L("Quest")
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

    /// Against what you wear in that slot: folded into a Compare row (playtesting 2026-10-26,
    /// progressive disclosure) that says at a glance whether it's better or worse for you
    /// (`GameSession.gearValue`, as the grid's upgrade arrow does); a tap opens each stat it would
    /// raise or lower. Debug `compare` opens it.
    @ViewBuilder
    private var comparison: some View {
        let worn = session.equipped(item.type)
        if worn?.id == item.id {
            Text(L("You're wearing one.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
        } else if let worn {
            let gained: Stats = item.stats ?? Stats.zero
            let lost: Stats = worn.stats ?? Stats.zero
            let change = Self.parts(of: gained + lost * -1)
            let gain = session.gearValue(item) - session.gearValue(worn)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    SoundEffects.shared.play(.tap, volume: 0.7)
                    withAnimation(Reveal.animation) { comparing.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(L("Compare"))
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.gold)
                        Spacer(minLength: 6)
                        verdict(gain)
                        IconImage(.chevronDown, size: 11)
                            .foregroundStyle(HUDStyle.gold)
                            .rotationEffect(.degrees(comparing ? 180 : 0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(comparing ? 0.1 : 0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(comparing ? L("Hides the stats") : L("Shows each stat against your {item}", ["item": worn.name]))
                if comparing {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Instead of your {item}", ["item": worn.name]))
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.dim)
                        if change.isEmpty {
                            Text(L("The same stats.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                        } else {
                            chips(change)
                        }
                    }
                    .transition(.reveal)
                }
            }
        } else {
            Text(L("You have no {type} on.", ["type": item.type.displayName.midSentence])).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
        }
    }

    /// Better or worse for you than what you wear, with its arrow, or about the same.
    @ViewBuilder
    private func verdict(_ gain: Double) -> some View {
        if gain > 0.001 {
            Label(L("Better"), icon: .arrowUp, size: 12)
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.green)
        } else if gain < -0.001 {
            Label(L("Worse"), icon: .arrowDown, size: 12)
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.orange)
        } else {
            Text(L("About the same"))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
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
        if session.isForTrade(item.id) {
            let ask = session.tradeAsk(item.id)
            lines.append(L("Up for trade: {count} at {gold}g each", ["count": ask.count, "gold": ask.price]))
        }
        if item.price > 0 {
            // No shop sells a quest treasure, but they'll buy one.
            lines.append(session.content.isTreasure(item.id)
                         ? L("Shops pay {gold}g for it", ["gold": GameSession.sellPrice(of: item)])
                         : L("Shops sell it for {price}g and pay {gold}g", ["price": item.price, "gold": GameSession.sellPrice(of: item)]))
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

    /// A piece of gear in one line: "Lv 100 · DEF +38 · HP +100".
    static func summary(of item: ItemDef) -> String {
        let stats = Self.parts(of: item.stats ?? Stats.zero).map { "\($0.label) \($0.value >= 0 ? "+" : "−")\(abs($0.value))" }
        return ((item.level.map { [L("Lv {level}", ["level": $0])] } ?? []) + stats).joined(separator: " · ")
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
