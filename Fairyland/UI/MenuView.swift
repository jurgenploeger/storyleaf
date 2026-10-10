import SwiftUI

/// Character, Companions, Friends, Bag, Quests and Settings in one tabbed panel.
struct MenuView: View {
    let session: GameSession
    let onClose: () -> Void
    var onQuitToTitle: (() -> Void)?
    @State private var tab: MenuTab
    /// A language switch (in Settings) rebuilds the panel's text, staying on the same tab.
    @State private var localizer = Localizer.shared
    /// Use or Give in the Bag: who gets it, in a window over the menu.
    @State private var picking: ItemDef? = DebugLaunch.picksTargetFor.flatMap { Content.shared.item($0) }
    /// What the last thing used from the Bag did.
    @State private var bagNote: String?
    /// Change on the Character tab: the grid of gear for that slot, in a window over the menu.
    @State private var changing: ItemType? = DebugLaunch.changingSlot
    /// The smaller tabs' pages (Character, Companions and Quests have them), kept while the menu
    /// is open. Debug `sub=<page>` opens one.
    @State private var characterPage: CharacterPage = DebugLaunch.subTab.flatMap(CharacterPage.init(rawValue:)) ?? .hero
    @State private var companionsPage: CompanionsPage = DebugLaunch.opensMonsterBook ? .book : .companions
    @State private var questsPage: QuestsPage = DebugLaunch.subTab.flatMap(QuestsPage.init(rawValue:)) ?? .quests
    /// An egg to hatch, chosen on its card: the Bag plays the hatching.
    @State private var hatchRequest: ItemDef?
    /// A tap on something in the Bag: its card, over the menu. Debug `inspect=<item>` opens one
    /// (unless it's for the gear grid, `change=`).
    @State private var inspecting: ItemDef? = DebugLaunch.changingSlot == nil ? DebugLaunch.inspectedItem.flatMap { Content.shared.item($0) } : nil

    init(session: GameSession, initialTab: MenuTab, onClose: @escaping () -> Void, onQuitToTitle: (() -> Void)? = nil) {
        self.session = session
        self.onClose = onClose
        self.onQuitToTitle = onQuitToTitle
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(MenuTab.allCases) { item in
                        Button {
                            if tab != item { SoundEffects.shared.play(.tap, volume: 0.7) }
                            tab = item
                        } label: {
                            Label(item.title, icon: item.icon, size: 20)
                                .labelStyle(TabLabelStyle(selected: item == tab))
                        }
                    }
                    Spacer(minLength: 4)
                    OrangeCloseButton(action: onClose)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(HUDStyle.titleGloss.overlay(alignment: .bottom) { HUDStyle.titleEdge })

                ScrollView {
                    Group {
                        switch tab {
                        case .character:
                            CharacterTab(session: session, page: $characterPage) { slot in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { changing = slot }
                            }
                        case .companions: CompanionsTab(session: session, page: $companionsPage)
                        case .friends: FriendsTab(session: session)
                        case .bag:
                            BagTab(session: session, note: $bagNote, hatchRequest: $hatchRequest,
                                   onInspect: { item in withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { inspecting = item } })
                        case .quests: QuestsTab(session: session, page: $questsPage)
                        case .settings: SettingsView(session: session, onQuitToTitle: onQuitToTitle)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Debug `bottom`: opens at the end of the page (screenshots of the skills).
                .defaultScrollAnchor(DebugLaunch.opensMenuAtBottom ? .bottom : nil)
            }
            .id(localizer.language)
            .frame(maxWidth: 760)
            .gameWindow()
            .padding(10)

            if let slot = changing {
                // Fades in; only its window scales (popIn), so its backdrop always fills the screen.
                EquipmentPicker(session: session, slot: slot) {
                    withAnimation(.easeOut(duration: 0.2)) { changing = nil }
                }
                .transition(.opacity)
                .zIndex(1)
            }

            if let item = picking {
                ItemTargetPicker(session: session, item: item) { note in
                    if let note { bagNote = note }
                    withAnimation(.easeOut(duration: 0.2)) { picking = nil }
                }
                .transition(.opacity)
                .zIndex(1)
            }

            if let item = inspecting {
                let close = { withAnimation(.easeOut(duration: 0.2)) { inspecting = nil } }
                // From the Bag: what you can do with it there, on its card.
                let fromBag = tab == .bag
                let wearable = fromBag && ItemType.equipmentSlots.contains(item.type) && session.count(of: item.id) > 0
                let equip: (() -> Void)? = wearable ? { session.equip(item.id); close() } : nil
                ItemInfoCard(session: session, item: item, onClose: close, onEquip: equip,
                             action: fromBag ? bagAction(for: item, close: close) : nil,
                             note: fromBag ? bagNote(for: item) : nil)
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .foregroundStyle(HUDStyle.cream)
    }
}

extension MenuView {
    /// What an item in the Bag can do, on its card: drink it (or give it) to someone, give a toy to
    /// a companion, fly home on a feather, or hatch an egg.
    func bagAction(for item: ItemDef, close: @escaping () -> Void) -> ItemInfoCard.Action? {
        let pick = { close(); withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { picking = item } }
        if item.hatches != nil {
            return ItemInfoCard.Action(title: L("Hatch"), icon: .egg) { close(); hatchRequest = item }
        }
        if (item.heal ?? 0) > 0 || (item.mp ?? 0) > 0 {
            return ItemInfoCard.Action(title: L("Use"), run: pick)
        }
        if item.travel == true {
            // Back to your checkpoint, like Bridge of Light (closes the menu).
            return ItemInfoCard.Action(title: L("Use"), enabled: session.onTravel != nil) { close(); session.onTravel?(item) }
        }
        if item.toy == true, !session.data.pets.isEmpty {
            return ItemInfoCard.Action(title: L("Give"), icon: .gift, run: pick)
        }
        return nil
    }

    /// Why an item in the Bag has nothing to do there.
    func bagNote(for item: ItemDef) -> String? {
        if item.capture == true { return L("For battle") }
        if item.toy == true, session.data.pets.isEmpty { return L("No companions yet") }
        return nil
    }
}

// MARK: - Smaller tabs

/// A menu tab's smaller tabs, under the menu's own: gold for the one you're on, like the menu's.
/// One you're not on wears the HUD's gold dot when something there waits for you (`waiting`).
/// The pages are a nonisolated enum (its raw value is the debug name, `sub=skills`).
private struct SubTabs<Page: Hashable & CaseIterable>: View {
    @Binding var page: Page
    let title: (Page) -> String
    let icon: (Page) -> GameIcon
    var waiting: (Page) -> Bool = { _ in false }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Page.allCases), id: \.self) { item in
                let selected = item == page
                let marked = !selected && waiting(item)
                Button {
                    guard !selected else { return }
                    SoundEffects.shared.play(.tap, volume: 0.7)
                    page = item
                } label: {
                    Label(title(item), icon: icon(item), size: 16)
                        .font(HUDStyle.font(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? HUDStyle.ink : HUDStyle.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? HUDStyle.gold : .white.opacity(0.06)))
                        .overlay(alignment: .topTrailing) {
                            if marked {
                                Circle().fill(HUDStyle.gold).frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                                    .offset(x: -4, y: -2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(marked ? L("Something to do") : "")
            }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.2)))
    }
}

/// A tab's explanation, folded away once you know the ropes: open while you have none of what it
/// explains (no companions yet, no friends), a tap away after that.
private struct HowItWorks: View {
    let text: String
    @State private var open: Bool

    init(_ text: String, open: Bool) {
        self.text = text
        _open = State(initialValue: open)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Reveal.animation) { open.toggle() }
            } label: {
                HStack(spacing: 5) {
                    IconImage(.book, size: 13)
                    Text(L("How it works"))
                    IconImage(.chevronDown, size: 11)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.gold)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? L("Hides the explanation") : L("Shows the explanation"))
            if open {
                Text(text)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.reveal)
            }
        }
    }
}

private struct TabLabelStyle: LabelStyle {
    let selected: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            // Icons only in narrow portrait layouts.
            if verticalSizeClass == .compact || selected { configuration.title }
        }
        .font(HUDStyle.font(12))
        .foregroundStyle(selected ? HUDStyle.ink : HUDStyle.cream)
        // Six tabs and the close button fit across a phone held upright.
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Capsule().fill(selected ? HUDStyle.gold : .white.opacity(0.08)))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(HUDStyle.font(11))
            .foregroundStyle(HUDStyle.gold)
            .padding(.top, 4)
    }
}

// MARK: - Character

/// The Character tab's pages.
private nonisolated enum CharacterPage: String, CaseIterable {
    /// Who you are: the hero, their stats and what they wear.
    case hero
    /// What you know and can learn, and what your class unlocks later.
    case skills
    /// The titles you've earned, and those still to earn.
    case titles

    var title: String {
        switch self {
        case .hero: L("Hero")
        case .skills: L("Skills")
        case .titles: L("Titles")
        }
    }

    @MainActor var icon: GameIcon {
        switch self {
        case .hero: .user
        case .skills: .sparkles
        case .titles: .star
        }
    }
}

private struct CharacterTab: View {
    let session: GameSession
    @Binding var page: CharacterPage
    /// Change on an equipment row: MenuView opens the grid of gear for that slot.
    let onChange: (ItemType) -> Void
    /// The skills your class unlocks later: the next two, or all of them.
    @State private var showsAllUpcoming = false

    var body: some View {
        let hero = session.data.hero
        let stats = session.heroStats
        // Looks are chosen once, when the hero is made (LookEditor on the title screen).
        VStack(alignment: .leading, spacing: 14) {
            SubTabs(page: $page, title: { $0.title }, icon: { $0.icon }) { waiting(on: $0) }
            switch page {
            case .hero: overview(hero: hero, stats: stats)
            case .skills: skills(hero: hero)
            case .titles: TitlesSection(session: session)
            }
        }
    }

    /// A path to choose (at a guild master), or a skill point to spend.
    private func waiting(on tab: CharacterPage) -> Bool {
        switch tab {
        case .hero: return session.canChooseClass
        case .skills: return session.canSpendSkillPoint
        case .titles: return false
        }
    }

    @ViewBuilder
    private func overview(hero: Hero, stats: Stats) -> some View {
        AdaptiveStack(spacing: 18) {
            VStack(spacing: 6) {
                // The hero in the middle, what they wear in the slots around them.
                PaperDoll(session: session, change: onChange)
                // The name is chosen when the hero is made and stays.
                Text(hero.name).font(HUDStyle.font(18))
                if let title = session.wornTitle {
                    TitleBadge(title: title, size: 12)
                }
                Text("\(session.heroRace.name) · \(session.heroClass.name)")
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                if session.canChooseClass {
                    Text(L("Ready to choose a path! Visit a guild master in Meadowbrook."))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.green)
                        .multilineTextAlignment(.center)
                        .frame(width: 170)
                }
            }
            .frame(minWidth: 250)
            .frame(maxWidth: .infinity)

            StatsPanel(level: session.rebirths > 0 ? L("Level {level} · Reborn ×{rebirths}", ["level": hero.level, "rebirths": session.rebirths]) : L("Level {level}", ["level": hero.level]),
                       exp: hero.exp, expToNext: GameSession.expToNext(level: hero.level), hp: hero.hp, mp: hero.mp, stats: stats)
        }
    }

    /// Skill points, what you know and can learn (SkillChoices), and what your class unlocks later:
    /// the next two, the rest a tap away.
    private func skills(hero: Hero) -> some View {
        // Reborn heroes keep the skills they learned, so those aren't "still locked".
        let learned = Set(hero.learnedSkills ?? [])
        let upcoming = session.heroClass.skills.filter { $0.level > hero.level && !learned.contains($0.skill) }
        return VStack(alignment: .leading, spacing: 10) {
            if session.canSpendSkillPoint {
                Text(session.unspentSkillPoints == 1 ? L("1 skill point to spend") : L("{count} skill points to spend", ["count": session.unspentSkillPoints]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.gold)
            } else if session.unspentSkillPoints > 0 {
                // Everything known is mastered: points wait for the next skill the class unlocks.
                Text(L("{count} saved for your next skill", ["count": session.unspentSkillPoints]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.dim)
            }
            if session.heroSkills.isEmpty && session.learnableSkills.isEmpty {
                EmptyNote(session.skillHint, size: 11)
            }
            SkillChoices(session: session)
            if !upcoming.isEmpty {
                SectionTitle(text: L("Coming up"))
            }
            ForEach(showsAllUpcoming ? upcoming : Array(upcoming.prefix(2)), id: \.skill) { unlock in
                if let skill = session.content.skill(unlock.skill) {
                    // Still locked: a faded tile, with the level it unlocks at.
                    HStack(spacing: 8) {
                        SkillIcon(skill: skill, size: 28)
                            .saturation(0.2)
                            .opacity(0.55)
                        Text(skill.name)
                            .foregroundStyle(HUDStyle.dim)
                        Spacer()
                        Text(L("Lv {level}", ["level": unlock.level]))
                            .font(HUDStyle.font(10))
                            .foregroundStyle(HUDStyle.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(HUDStyle.dim))
                    }
                    .font(HUDStyle.font(11))
                }
            }
            if upcoming.count > 2 {
                Button(showsAllUpcoming ? L("Show fewer") : L("Show {count} more", ["count": upcoming.count - 2])) {
                    withAnimation(.easeOut(duration: 0.2)) { showsAllUpcoming.toggle() }
                }
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Stats section of the Character screen, and of the companion you bring along: the level,
/// EXP, HP and MP bars and the four stats with their icons, every number in one size. Big and easy
/// to read: the screen has the room.
private struct StatsPanel: View {
    let level: String
    let exp: Int
    let expToNext: Int
    let hp: Int
    let mp: Int
    let stats: Stats

    private static let digits: CGFloat = 13
    private static let attackTint = Color(red: 1, green: 0.5, blue: 0.35)
    private static let magicTint = Color(red: 0.78, green: 0.58, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: L("Stats"))
                Spacer()
                Text(level).font(HUDStyle.font(15))
            }
            bar(L("EXP"), exp, expToNext, HUDStyle.exp)
            bar(L("HP"), hp, stats.hp, HUDStyle.hp)
            // Companions without magic have no MP to show.
            if stats.mp > 0 { bar(L("MP"), mp, stats.mp, HUDStyle.mp) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                StatCell(name: L("Attack"), value: stats.attack, size: 13, icon: .sword, tint: Self.attackTint, digits: Self.digits)
                StatCell(name: L("Defense"), value: stats.defense, size: 13, icon: .shield, tint: HUDStyle.mp, digits: Self.digits)
                StatCell(name: L("Magic"), value: stats.magic, size: 13, icon: .sparkles, tint: Self.magicTint, digits: Self.digits)
                StatCell(name: L("Speed"), value: stats.speed, size: 13, icon: .wind, tint: HUDStyle.green, digits: Self.digits)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bar(_ label: String, _ value: Int, _ maximum: Int, _ color: Color) -> some View {
        StatBar(label: label, value: value, maximum: maximum, color: color,
                labelWidth: 36, height: 20, labelSize: 15, numberSize: Self.digits)
    }
}

struct StatCell: View {
    let name: String
    let value: Int
    /// The text size; the padding grows with it (bigger on the Character screen).
    var size: CGFloat = 12
    /// The stat's icon before its name, in its colour (the Character screen).
    var icon: GameIcon?
    var tint: Color = HUDStyle.dim
    /// The number in the HUD's digits at this size, to match the bars beside it.
    var digits: CGFloat?

    var body: some View {
        HStack(spacing: size * 0.45) {
            if let icon {
                IconImage(icon, size: (size * 1.15).rounded()).foregroundStyle(tint)
            }
            Text(name).foregroundStyle(HUDStyle.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("\(value)").foregroundStyle(.white)
                .monospacedDigit()
                .font(digits.map { HUDStyle.mono($0) } ?? HUDStyle.font(size))
        }
        .font(HUDStyle.font(size))
        .padding(.horizontal, size * 0.7)
        .padding(.vertical, size * 0.45)
        .background(RoundedRectangle(cornerRadius: size * 0.45).fill(.white.opacity(0.06)))
    }
}

/// The hero in the middle with what they wear in a ring around them, like a paper doll: the body's
/// slots round the left (necklace, armour, boots, top to bottom), the hands' round the right
/// (weapon, gloves, accessory). A tap on a slot opens everything you have for it (EquipmentPicker).
private struct PaperDoll: View {
    let session: GameSession
    let change: (ItemType) -> Void

    /// Each slot and where it sits on the ring, in degrees clockwise from the right.
    private static let ring: [(slot: ItemType, angle: Double)] = [
        (.weapon, -55), (.gloves, 0), (.accessory, 55),
        (.boots, 125), (.armor, 180), (.necklace, 235),
    ]
    /// The ring's radius (to each slot's middle), and the room a slot takes.
    private static let radius: CGFloat = 112
    private static let slot = CGSize(width: 62, height: 66)

    var body: some View {
        let width = Self.radius * 2 + Self.slot.width
        let height = Self.radius * 2 * CGFloat(sin(55 * Double.pi / 180)) + Self.slot.height
        ZStack {
            // A faint ring through the slots, and the hero on a soft disc in the middle.
            Circle()
                .strokeBorder(.white.opacity(0.08), lineWidth: 2)
                .frame(width: Self.radius * 2, height: Self.radius * 2)
            WalkingSprite(art: GameSession.heroArt, size: 128, weapon: session.equipped(.weapon))
                .background(Circle().fill(.white.opacity(0.06)))
            ForEach(Self.ring, id: \.slot) { place in
                let angle = place.angle * Double.pi / 180
                DollSlot(session: session, slot: place.slot) { change(place.slot) }
                    .frame(width: Self.slot.width, height: Self.slot.height)
                    .offset(x: Self.radius * CGFloat(cos(angle)), y: Self.radius * CGFloat(sin(angle)))
            }
        }
        .frame(width: width, height: height)
        .padding(.vertical, 4)
    }
}

/// One slot on the paper doll: what's worn there, or the slot's shape faded when it's empty, with
/// the slot's name under it. An empty slot you have something for gets the HUD's gold dot.
private struct DollSlot: View {
    let session: GameSession
    let slot: ItemType
    let change: () -> Void

    private static let size: CGFloat = 44

    /// What an empty slot shows, faded: the plainest piece for it.
    private static let silhouettes: [ItemType: String] = [
        .weapon: "wooden_sword", .armor: "cloth_tunic", .gloves: "leather_gloves",
        .necklace: "shell_pendant", .boots: "straw_sandals", .accessory: "novice_ring",
    ]

    var body: some View {
        let worn = session.equipped(slot)
        let spare = worn == nil && session.bagEquipment.contains { $0.type == slot }
        Button(action: change) {
            VStack(spacing: 3) {
                Group {
                    if let worn {
                        ItemIcon(item: worn, size: Self.size)
                    } else if let shape = Self.silhouettes[slot].flatMap(session.content.item) {
                        ItemIcon(item: shape, size: Self.size)
                            .saturation(0)
                            .opacity(0.3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if spare {
                        Circle().fill(HUDStyle.gold).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(HUDStyle.ink, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
                Text(slot.displayName)
                    .font(HUDStyle.font(9))
                    .foregroundStyle(HUDStyle.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.size + 14)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(slot.displayName)
        .accessibilityValue(worn.map { [$0.name, $0.stats?.bonusSummary ?? ""].filter { !$0.isEmpty }.joined(separator: ", ") }
                            ?? (spare ? L("Empty, something to wear in your bag") : L("Empty")))
        .accessibilityHint(L("Change"))
    }
}

/// An element's shape and name on a glossy pill of its gem.
struct ElementBadge: View {
    let element: Element

    var body: some View {
        HStack(spacing: 3) {
            IconImage(element.icon, size: 10)
            Text(element.displayName)
        }
        .font(HUDStyle.font(9))
        // As wide as its name, on one line: a crowded row squeezes the skill's name instead.
        .lineLimit(1)
        .fixedSize()
        .onElementGem(element, horizontal: 7, vertical: 2.5)
    }
}

/// An element's shape on a round gem, where there's no room for its name.
struct ElementIcon: View {
    let element: Element
    var size: CGFloat = 16

    var body: some View {
        let gem = ElementGem(element)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [gem.light, gem.base, gem.shade], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            Ellipse()
                .fill(ElementGem.gloss)
                .frame(width: size * 0.68, height: size * 0.46)
                .offset(y: -size * 0.2)
            Circle().strokeBorder(gem.deep, lineWidth: 1)
            Circle().inset(by: 1).strokeBorder(ElementGem.bevel, lineWidth: 0.75)
            IconImage(element.icon, size: (size * 0.6).rounded())
                .foregroundStyle(gem.ink)
                .shadow(color: gem.inkShadow, radius: 0, x: 0, y: gem.inkDrop)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(element.displayName)
    }
}

extension View {
    /// Sets this shape and name on `element`'s gem, cut as a glossy pill.
    func onElementGem(_ element: Element, horizontal: CGFloat, vertical: CGFloat) -> some View {
        let gem = ElementGem(element)
        return foregroundStyle(gem.ink)
            .shadow(color: gem.inkShadow, radius: 0, x: 0, y: gem.inkDrop)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [gem.light, gem.base, gem.shade], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // The shine across its top half.
                        VStack(spacing: 0) {
                            Capsule().fill(ElementGem.gloss)
                            Color.clear
                        }
                        .padding(.horizontal, 3)
                        .padding(.top, 1.5)
                    }
                    .overlay(Capsule().strokeBorder(gem.deep, lineWidth: 1))
                    .overlay(Capsule().inset(by: 1).strokeBorder(ElementGem.bevel, lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            )
    }
}

/// The gem an element's badges are cut from, lit from the top: a light top, its colour, a shaded
/// lower edge and a deep rim. Its shape sits on it in white with a deep drop, or engraved in a dark
/// tone on the pale gems (gold light, silver metal, pearl neutral), where white wouldn't show.
private struct ElementGem {
    let light: Color
    let base: Color
    let shade: Color
    let deep: Color
    let ink: Color
    let inkShadow: Color
    let inkDrop: CGFloat

    static let gloss = LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
    /// A thin light edge just inside the rim, along the top.
    static let bevel = LinearGradient(colors: [.white.opacity(0.65), .clear], startPoint: .top, endPoint: .center)

    init(_ element: Element) {
        switch element {
        case .fire: self.init(light: (1, 0.78, 0.42), base: (0.92, 0.36, 0.1), deep: (0.55, 0.12, 0.02))
        case .water: self.init(light: (0.6, 0.86, 1), base: (0.18, 0.48, 0.9), deep: (0.05, 0.2, 0.52))
        case .wood: self.init(light: (0.7, 0.95, 0.45), base: (0.22, 0.56, 0.15), deep: (0.07, 0.3, 0.06))
        case .earth: self.init(light: (0.92, 0.76, 0.5), base: (0.66, 0.43, 0.2), deep: (0.36, 0.2, 0.06))
        case .metal: self.init(light: (1, 1, 1), base: (0.72, 0.76, 0.84), deep: (0.38, 0.42, 0.52), engraved: (0.25, 0.29, 0.4))
        case .light: self.init(light: (1, 0.99, 0.8), base: (1, 0.82, 0.25), deep: (0.68, 0.45, 0), engraved: (0.52, 0.32, 0))
        case .dark: self.init(light: (0.8, 0.64, 1), base: (0.48, 0.28, 0.76), deep: (0.2, 0.07, 0.4))
        case .neutral: self.init(light: (1, 1, 1), base: (0.82, 0.84, 0.88), deep: (0.46, 0.49, 0.57), engraved: (0.3, 0.33, 0.4))
        }
    }

    private typealias RGB = (Double, Double, Double)

    private init(light: RGB, base: RGB, deep: RGB, engraved: RGB? = nil) {
        self.light = Self.color(light)
        self.base = Self.color(base)
        self.deep = Self.color(deep)
        // The lower edge leans 40% of the way to the deep tone.
        shade = Self.color((base.0 + (deep.0 - base.0) * 0.4, base.1 + (deep.1 - base.1) * 0.4, base.2 + (deep.2 - base.2) * 0.4))
        ink = engraved.map { Self.color($0) } ?? .white
        inkShadow = engraved == nil ? Self.color(deep) : .white.opacity(0.55)
        inkDrop = engraved == nil ? 1 : 0.75
    }

    private static func color(_ rgb: RGB) -> Color {
        Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

// MARK: - Companions

/// The Companions tab's pages.
private nonisolated enum CompanionsPage: String, CaseIterable {
    /// The monsters you've befriended.
    case companions
    /// Every monster you've met.
    case book

    var title: String {
        switch self {
        case .companions: L("Companions")
        case .book: L("Monster Book")
        }
    }

    @MainActor var icon: GameIcon {
        switch self {
        case .companions: .paw
        case .book: .book
        }
    }
}

private struct CompanionsTab: View {
    let session: GameSession
    @Binding var page: CompanionsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubTabs(page: $page, title: { $0.title }, icon: { $0.icon })
                .padding(.bottom, 4)
            switch page {
            case .companions: companions
            case .book: MonsterBook(session: session)
            }
        }
    }

    private var companions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HowItWorks(L("Companions fight beside you and earn a share of battle EXP. Throw a Seal Stone at a wild monster with Capture to befriend it (up to {count}): any monster, at any HP, but the weaker it is, the better the odds. Each throw uses a stone up, and stronger stones hold more often. Trader Bo in Meadowbrook sells Seal Stones.", ["count": GameSession.maxPets]),
                       open: session.data.pets.isEmpty)
            if session.data.pets.isEmpty {
                EmptyNote(L("No companions yet.\nElder Oak in Meadowbrook gives you an egg with the first quest: hatch it from your Bag."))
            }
            // The one you bring along first, laid out like your hero; the rest in cards below.
            let active = session.data.pets.first { $0.id == session.data.activePetID }
            let others = session.data.pets.filter { $0.id != active?.id }
            if let active {
                CompanionCard(session: session, pet: active, featured: true)
                if !others.isEmpty {
                    SectionTitle(text: L("Other companions")).padding(.top, 6)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(others) { pet in
                    CompanionCard(session: session, pet: pet)
                }
            }
        }
    }
}

// MARK: - Friends

/// The adventurers you've befriended, and who of them travels with you.
private struct FriendsTab: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HowItWorks(L("Befriend adventurers you meet (walk up to one). Up to {count} friends can travel and fight with you, and they bring their companions. They fight on if you faint, and wait where you fell; a friend who faints wakes up at their own checkpoint. Walk up to them to set off together again.", ["count": GameSession.maxAllies]),
                       open: session.friends.isEmpty)
            if session.friends.isEmpty {
                EmptyNote(L("No friends yet.\nSay hi to the adventurers you meet!"))
            }
            ForEach(session.friends) { friend in
                FriendRow(session: session, friend: friend)
            }
        }
    }
}

private struct FriendRow: View {
    let session: GameSession
    let friend: Adventurer

    var body: some View {
        let inParty = session.isInParty(friend)
        let pet = friend.petSpecies.flatMap(session.content.monster)
        HStack(spacing: 10) {
            // Their companion at their feet.
            SpriteImage(art: session.artID(for: friend), size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if let pet {
                        SpriteImage(art: pet.art, size: 24).offset(x: 12, y: 4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.name)
                    NameBadge(badge: .bot)
                    if inParty {
                        Text(L("IN PARTY"))
                            .font(HUDStyle.font(9))
                            .foregroundStyle(HUDStyle.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(HUDStyle.green))
                    }
                }
                Text(L("Lv {level} {race} {class}", ["level": friend.level, "race": session.content.race(friend.raceID).name, "class": session.content.classDef(friend.classID).name]))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                if let pet {
                    Text(L("with their {name}", ["name": pet.name]))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.green)
                }
                if let place = session.whereabouts(of: friend) {
                    Text(L("Waiting for you at {map}", ["map": place]))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.orange)
                }
            }
            Spacer()
            if inParty {
                Button(L("Leave")) { session.leaveParty(friend.id) }
                    .buttonStyle(PixelButtonStyle(compact: true))
            } else if !session.adventurersAround.contains(friend.id) {
                // Friends have to be here to join you.
                Text(L("Not around"))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            } else if session.partyMembers.count < GameSession.maxAllies {
                Button(L("Invite")) { session.invite(friend.id) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            } else {
                Text(L("Party full"))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            }
        }
        .font(HUDStyle.font(12))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
    }
}

private struct CompanionCard: View {
    let session: GameSession
    let pet: Pet
    /// The one you bring along, at the top: big, like the hero on the Character screen.
    var featured = false
    @State private var editing = false

    /// The gentlest potion in the bag that would wake a fainted companion.
    private var potion: ItemDef? {
        session.content.items
            .filter { $0.type == .consumable && ($0.heal ?? 0) > 0 && session.count(of: $0.id) > 0 }
            .min { ($0.heal ?? 0) < ($1.heal ?? 0) }
    }

    var body: some View {
        let species = session.species(of: pet)
        let stats = session.stats(of: pet)
        let isActive = session.data.activePetID == pet.id
        if editing {
            CompanionEditor(session: session, pet: pet) { editing = false }
        } else if featured {
            overview(species: species, stats: stats, isActive: isActive)
        } else {
            card(species: species, stats: stats, isActive: isActive)
        }
    }

    /// Like the hero's overview: the companion big on its disc with its name, what it is and what
    /// it can do, and its stats beside or under it.
    private func overview(species: MonsterDef?, stats: Stats, isActive: Bool) -> some View {
        AdaptiveStack(spacing: 18) {
            VStack(spacing: 6) {
                SpriteImage(art: session.artID(for: pet), size: 128)
                    .background(Circle().fill(.white.opacity(0.06)))
                HStack(spacing: 6) {
                    Text(pet.name).font(HUDStyle.font(18))
                    if let element = species?.element { ElementBadge(element: element) }
                }
                Text(species?.name ?? pet.speciesID)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.gold)
                notes(stats: stats, isActive: isActive)
                    .multilineTextAlignment(.center)
                skillsRow(species: species)
                actions(isActive: isActive)
            }
            .frame(minWidth: 250)
            .frame(maxWidth: .infinity)

            StatsPanel(level: L("Level {level}", ["level": pet.level]),
                       exp: pet.exp, expToNext: GameSession.expToNext(level: pet.level), hp: pet.hp, mp: pet.mp, stats: stats)
        }
    }

    /// Fainted (and how to heal it), and its toys.
    @ViewBuilder
    private func notes(stats: Stats, isActive: Bool) -> some View {
        if pet.hp <= 0 {
            // A fainted companion stays off the map and out of fights until it's healed.
            Text(isActive ? L("Fainted: it can't follow you or fight until it's healed.") : L("Fainted: heal it before it comes along."))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.orange)
                .fixedSize(horizontal: false, vertical: true)
            if let potion {
                Button(L("Give it a {item} ({count} left)", ["item": potion.name, "count": session.count(of: potion.id)])) { session.use(potion.id, onPet: pet.id) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.green, compact: true))
            } else {
                Text(L("No potions in your bag: a healer in town can help."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            }
        }
        // Toys it has played with, and what they've added for good.
        if let toys = pet.toys, toys > 0 {
            Text(L("Toys {count}/{max}: {bonus}", ["count": toys, "max": GameSession.toysPerCompanion, "bonus": (pet.toyStats ?? .zero).bonusSummary]))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.green)
        } else if !session.bagToys.isEmpty {
            Text(L("Give it a toy from your Bag."))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What it can do in a fight.
    @ViewBuilder
    private func skillsRow(species: MonsterDef?) -> some View {
        if let skills = species?.skills.compactMap({ session.content.skill($0) }), !skills.isEmpty {
            HStack(spacing: 6) {
                ForEach(skills) { skill in
                    HStack(spacing: 3) {
                        SkillIcon(skill: skill, size: 22)
                        Text(skill.name)
                            .font(HUDStyle.font(10))
                            .foregroundStyle(HUDStyle.cream)
                    }
                }
            }
        }
    }

    /// Following you (or resting), or Bring along; and Rename.
    private func actions(isActive: Bool) -> some View {
        HStack(spacing: 8) {
            if isActive, pet.hp > 0 {
                Label(L("Following you"), icon: .checkCircle)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.green)
            } else if isActive {
                // Still your choice: it comes along again once it's healed.
                Label(L("Chosen, resting"), icon: .heart)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.orange)
            } else {
                Button(L("Bring along")) { session.setActivePet(pet.id) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
            Button {
                editing = true
            } label: {
                Label(L("Rename"), icon: .edit)
            }
            .buttonStyle(PixelButtonStyle(compact: true))
        }
    }

    @ViewBuilder
    private func card(species: MonsterDef?, stats: Stats, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SpriteImage(art: session.artID(for: pet), size: 72)
                .background(Circle().fill(.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pet.name).font(HUDStyle.font(14))
                    if let element = species?.element { ElementBadge(element: element) }
                }
                Text(L("{species} · Lv {level}", ["species": species?.name ?? pet.speciesID, "level": pet.level]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.gold)
                StatBar(label: L("HP"), value: pet.hp, maximum: stats.hp, color: HUDStyle.hp)
                StatBar(label: L("EXP"), value: pet.exp, maximum: GameSession.expToNext(level: pet.level), color: HUDStyle.exp)
                Text(L("ATK {attack} · DEF {defense} · MAG {magic} · SPD {speed}", ["attack": stats.attack, "defense": stats.defense, "magic": stats.magic, "speed": stats.speed]))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                notes(stats: stats, isActive: isActive)
                skillsRow(species: species)
                actions(isActive: isActive)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(isActive ? 0.1 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isActive ? HUDStyle.green.opacity(0.7) : .clear, lineWidth: 2))
        )
    }
}

// MARK: - Bag

/// Everything you carry in a grid of slots, like an adventurer's pack: potions and other things to
/// use, spare gear, and materials, each with how many you have. A tap opens the item's card, with
/// what it does and the button to use, give, hatch or wear it.
private struct BagTab: View {
    let session: GameSession
    @Binding var note: String?
    /// An egg chosen on its card: it hatches here.
    @Binding var hatchRequest: ItemDef?
    /// A tap on an item: MenuView shows its card.
    let onInspect: (ItemDef) -> Void
    @State private var hatched: Pet?
    @State private var hatching = false

    private static let slot: CGFloat = 52
    private let columns = [GridItem(.adaptive(minimum: BagTab.slot + 6, maximum: BagTab.slot + 14), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("{gold} gold", ["gold": session.data.gold]), icon: .coins)
                    .foregroundStyle(HUDStyle.gold)
                Spacer()
                if let note { Text(note).foregroundStyle(HUDStyle.green) }
            }
            .font(HUDStyle.font(12))

            if hatching, let pet = hatched {
                HatchView(session: session, pet: pet) { hatching = false }
            }

            SectionTitle(text: L("Items"))
            if session.consumables.isEmpty {
                Text(L("No potions. Trader Bo in Meadowbrook sells them.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            grid(session.consumables)

            SectionTitle(text: L("Equipment"))
            if session.bagEquipment.isEmpty {
                Text(L("Nothing spare. Equipped gear is on the Character tab.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            // Gear you can't wear yet (too low a level, another class's) is faded.
            grid(session.bagEquipment) { session.equipIssue($0) == nil }

            SectionTitle(text: L("Materials"))
            if session.bagMaterials.isEmpty {
                Text(L("Monsters drop wood, metal, gems and hides. A town smith forges them into weapons."))
                    .font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
            }
            grid(session.bagMaterials)
        }
        .onChange(of: hatchRequest?.id) { _, id in
            guard let id else { return }
            hatchRequest = nil
            hatching = true
            hatched = session.hatch(id)
            if hatched == nil, session.data.pets.count >= GameSession.maxPets {
                note = L("No room: you have {count} companions.", ["count": GameSession.maxPets])
            }
            session.save()
        }
    }

    /// One slot per kind of item, its count in the corner from two up.
    private func grid(_ items: [ItemDef], usable: @escaping (ItemDef) -> Bool = { _ in true }) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                Button {
                    onInspect(item)
                } label: {
                    ItemIcon(item: item, size: Self.slot, count: session.count(of: item.id))
                        .opacity(usable(item) ? 1 : 0.45)
                        .padding(.top, 5)
                        .padding(.trailing, 5)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(session.count(of: item.id) > 1 ? L("{item}, {count}", ["item": item.name, "count": session.count(of: item.id)]) : item.name)
                .accessibilityHint(L("Shows what it does and who can use it"))
            }
        }
    }
}

/// The egg wobbles, cracks, and your first companion pops out.
private struct HatchView: View {
    let session: GameSession
    let pet: Pet
    let onDone: () -> Void
    @State private var stage = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if stage < 2 {
                    SpriteImage(art: "pet_egg", size: 90)
                        .rotationEffect(.degrees(stage == 1 ? 12 : -12))
                        .animation(.easeInOut(duration: 0.12).repeatCount(8, autoreverses: true), value: stage)
                } else {
                    SpriteImage(art: session.artID(for: pet), size: 110)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                    IconImage(.sparkles, size: 40)
                        .foregroundStyle(HUDStyle.gold)
                        .offset(x: 44, y: -40)
                }
            }
            .frame(height: 120)
            Text(stage < 2 ? L("Something is hatching…") : L("{name} hatched! Your first companion.", ["name": pet.name]))
                .font(HUDStyle.font(14))
                .foregroundStyle(HUDStyle.gold)
            if stage >= 2 {
                Button(L("Hello, {name}!", ["name": pet.name]), action: onDone)
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        .task {
            stage = 1
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { stage = 2 }
        }
    }
}

// MARK: - Quests

/// The Quests tab's two pages. Nonisolated like the other enums shown with `ForEach(id: \.self)`.
private nonisolated enum QuestsPage: String, CaseIterable {
    /// The quests people have given you, active and finished.
    case quests
    /// The day's bounties, their bonus and the daily gift.
    case daily

    var title: String {
        switch self {
        case .quests: L("Quests")
        case .daily: L("Daily challenges")
        }
    }

    @MainActor var icon: GameIcon {
        switch self {
        case .quests: .book
        case .daily: .sun
        }
    }
}

private struct QuestsTab: View {
    let session: GameSession
    @Binding var page: QuestsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubTabs(page: $page, title: { $0.title }, icon: { $0.icon }) { waiting(on: $0) }
                .padding(.bottom, 4)
            switch page {
            case .quests:
                SectionTitle(text: L("Active"))
                if session.activeQuests.isEmpty {
                    Text(L("No active quests. Elder Oak in Meadowbrook always needs help.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                }
                ForEach(session.activeQuests) { quest in
                    QuestRow(session: session, quest: quest, showsGiver: true)
                }
                if !session.completedQuests.isEmpty {
                    SectionTitle(text: L("Completed"))
                    ForEach(session.completedQuests) { quest in
                        CompletedQuestRow(session: session, quest: quest)
                    }
                }
            case .daily:
                BountiesSection(session: session)
            }
        }
    }

    /// A quest to report back on, or a bounty or the bonus to claim.
    private func waiting(on tab: QuestsPage) -> Bool {
        switch tab {
        case .quests:
            return session.activeQuests.contains { session.status(of: $0) == .ready }
        case .daily:
            let bounties = session.data.bounties?.bounties ?? []
            return bounties.contains { $0.isDone && !$0.claimed } || session.canClaimBountyBonus
        }
    }
}

struct QuestRow: View {
    let session: GameSession
    let quest: QuestDef
    /// Who asked and where they live (the Quests list; not while you're talking to them).
    /// In the list a tap also shows the reward in full.
    var showsGiver = false
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsGiver {
                GiverFace(npcID: quest.giver, size: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(quest.title).font(HUDStyle.font(13))
                    Spacer()
                    switch session.status(of: quest) {
                    case .active(let progress, let goal): Text("\(progress)/\(goal)").foregroundStyle(HUDStyle.gold)
                    case .ready: Text(L("Done! Report back")).foregroundStyle(HUDStyle.green)
                    default: EmptyView()
                    }
                }
                .font(HUDStyle.font(12))
                if showsGiver, let giver = session.content.npc(quest.giver) {
                    let home = session.content.home(ofNPC: quest.giver)?.name
                    Text(home.map { L("From {name} · {place}", ["name": giver.name, "place": $0]) } ?? L("From {name}", ["name": giver.name]))
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.gold.opacity(0.85))
                }
                Text(quest.description).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                if showsGiver && expanded {
                    QuestRewardsView(session: session, quest: quest, earned: false)
                        .padding(.top, 4)
                        .transition(.reveal)
                } else {
                    QuestRewardLine(session: session, quest: quest, more: showsGiver)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(expanded ? 0.09 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture {
            guard showsGiver else { return }
            withAnimation(Reveal.animation) { expanded.toggle() }
        }
        .accessibilityAddTraits(showsGiver ? .isButton : [])
        .accessibilityHint(showsGiver ? (expanded ? L("Hides the reward") : L("Shows the reward")) : "")
    }
}

/// A finished quest: who gave it and its name; a tap shows what it said and what you earned.
private struct CompletedQuestRow: View {
    let session: GameSession
    let quest: QuestDef
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                GiverFace(npcID: quest.giver, size: 24)
                Label(quest.title, icon: .badgeCheck)
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.dim)
                Spacer()
                IconImage(.chevronDown, size: 12)
                    .foregroundStyle(HUDStyle.dim)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quest.description).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                    QuestRewardsView(session: session, quest: quest, earned: true)
                }
                .padding(.leading, 32)
                .transition(.reveal)
            }
        }
        .padding(.vertical, expanded ? 6 : 0)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Reveal.animation) { expanded.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? L("Hides what you earned") : L("Shows what you earned"))
    }
}

/// What a quest pays at your level, on one line like a bounty's: gold, EXP and the items' icons.
/// `more`: a chevron says a tap shows it all (item names, roads it opens).
struct QuestRewardLine: View {
    let session: GameSession
    let quest: QuestDef
    var more = false

    var body: some View {
        let pay = session.questPay(quest)
        HStack(spacing: 10) {
            if pay.gold > 0 {
                Label("\(pay.gold)", icon: .coins, size: 12)
            }
            if pay.exp > 0 {
                Label(L("{exp} EXP", ["exp": pay.exp]), icon: .star, size: 12)
            }
            ForEach(RewardList.group(quest.reward.items ?? [], in: session), id: \.item.id) { entry in
                ItemIcon(item: entry.item, size: 20, count: entry.count)
                    .accessibilityLabel(entry.item.name)
            }
            if more {
                Spacer(minLength: 4)
                IconImage(.chevronDown, size: 12)
            }
        }
        .font(HUDStyle.font(10))
        .foregroundStyle(HUDStyle.dim)
    }
}

/// What a quest pays: gold, EXP, items (with their icons) and roads it opens.
/// `earned` words it for a quest you've finished, with what it really paid.
struct QuestRewardsView: View {
    let session: GameSession
    let quest: QuestDef
    let earned: Bool

    private struct RewardItem: Identifiable {
        let item: ItemDef
        var count: Int
        var id: String { item.id }
    }

    /// Items in reward order, repeats counted ("Potion ×2").
    private var items: [RewardItem] {
        var result: [RewardItem] = []
        for id in quest.reward.items ?? [] {
            guard let item = session.content.item(id) else { continue }
            if let index = result.firstIndex(where: { $0.id == id }) {
                result[index].count += 1
            } else {
                result.append(RewardItem(item: item, count: 1))
            }
        }
        return result
    }

    private var roads: [String] {
        let content = session.content
        return content.maps.flatMap { map in
            map.exits.filter { $0.requires == quest.id }.map { "\(map.name) → \(content.map($0.to)?.name ?? $0.to)" }
        }
    }

    var body: some View {
        let pay = earned ? session.paid(for: quest) : session.questPay(quest)
        VStack(alignment: .leading, spacing: 6) {
            Text(earned ? L("You earned") : L("Reward"))
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.gold)
            HStack(spacing: 12) {
                if pay.gold > 0 {
                    Label("\(pay.gold)", icon: .coins, size: 14)
                }
                if pay.exp > 0 {
                    Label(L("{exp} EXP", ["exp": pay.exp]), icon: .star, size: 14)
                }
            }
            .font(HUDStyle.font(12))
            .foregroundStyle(HUDStyle.cream)
            ForEach(items) { entry in
                HStack(spacing: 6) {
                    ItemIcon(item: entry.item, size: 22)
                    Text(entry.count > 1 ? "\(entry.item.name) ×\(entry.count)" : entry.item.name)
                        .font(HUDStyle.font(11))
                        .foregroundStyle(HUDStyle.cream)
                }
            }
            ForEach(roads, id: \.self) { road in
                Label(earned ? L("Opened the road {road}", ["road": road]) : L("Opens the road {road}", ["road": road]), icon: .map, size: 14)
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.cream)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(HUDStyle.ink.opacity(0.35)))
    }
}

/// The quest giver's face in a little round frame, so you remember who asked.
struct GiverFace: View {
    let npcID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let npc = Content.shared.npc(npcID) {
                Image(uiImage: ArtLibrary.shared.face(npc.art))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color(red: 0.98, green: 0.95, blue: 0.85).opacity(0.9)))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(HUDStyle.bevel, lineWidth: size > 30 ? 2 : 1.5))
    }
}
