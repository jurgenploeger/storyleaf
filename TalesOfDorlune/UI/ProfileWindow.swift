import SwiftUI

/// Someone whose stats you can look at: you, one of your companions, or an adventurer (a friend in
/// your party, or anyone you meet on the map).
enum Profile: Equatable {
    case hero
    case pet(UUID)
    case adventurer(Adventurer)
}

/// The profile window's pages. Its raw value is the debug name (`sub=companion`).
private nonisolated enum ProfilePage: String, CaseIterable {
    /// Who they are: their stats, what they wear and their skills.
    case hero
    /// The companion they bring along.
    case companion

    var title: String {
        switch self {
        case .hero: L("Hero")
        case .companion: L("Companion")
        }
    }
}

/// Fairyland Online's character window for another adventurer: tap someone on the map, or a friend's
/// face in the top-left corner (your own face and your companion's open the Hero and Companions windows,
/// `GameCoordinator.open`). The same big window as your Hero's (playtesting 2026-10-26), laid out as
/// your own pages are: Hero, them in their gear on the paper doll's ring with their stats beside it and
/// their skills under it; Companion, the one they bring along in its ring of skills, as yours is. One
/// without a companion has just the Hero page, under their name. Standing next to them, what you can
/// do with them, as on their card by the map (`AdventurerCard`).
struct ProfileWindow: View {
    let coordinator: GameCoordinator
    let person: Adventurer
    let onClose: () -> Void
    /// Debug `sub=companion` opens on the Companion page.
    @State private var page: ProfilePage = DebugLaunch.subTab.flatMap(ProfilePage.init(rawValue:)) ?? .hero
    /// A tap on something they wear: its card, over the window.
    @State private var inspecting: ItemDef?

    init(coordinator: GameCoordinator, person: Adventurer, onClose: @escaping () -> Void) {
        self.coordinator = coordinator
        self.person = person
        self.onClose = onClose
    }

    private var session: GameSession { coordinator.session }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            // As big as the menu's windows, presented as they are (`MenuView`).
            window
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gameWindow()
                .windowCloseButton(onClose)
                .accessibilityAction(.escape) { onClose() }
                .popIn()
                .menuWindowMargins()

            if let item = inspecting {
                ItemInfoCard(session: session, item: item, onClose: {
                    withAnimation(.easeOut(duration: 0.2)) { inspecting = nil }
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .foregroundStyle(HUDStyle.cream)
    }

    /// The tabs along the top (or their name alone, with no companion), and the page you're on.
    private var window: some View {
        let species = companion
        return VStack(spacing: 0) {
            if species != nil {
                PageTabs(page: $page, title: { $0.title })
            } else {
                WindowTitle(person.name)
                    .padding(.bottom, 2)
            }

            ScrollView {
                Group {
                    if let species, page == .companion {
                        companionPage(species)
                    } else {
                        heroPage
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Hero

    /// Laid out as your own Hero page: them in their gear on the ring, their name, title, race and
    /// class, who they are to you and what you can do with them; their stats beside or under it; their
    /// skills below.
    private var heroPage: some View {
        let stats = session.stats(of: person)
        // A friend shows what their last fight with you left them; anyone else is at full strength.
        let friend = session.data.friends?.first { $0.id == person.id }
        let race = session.content.race(person.raceID).name
        let heroClass = session.content.classDef(person.classID).name
        return VStack(alignment: .leading, spacing: 14) {
            AdaptiveStack(spacing: 18) {
                VStack(spacing: 6) {
                    WornDoll(session: session, art: session.artID(for: person), weapon: GameSession.weapon(for: person),
                             worn: gear) { item in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { inspecting = item }
                    }
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(HUDStyle.font(18))
                            .foregroundStyle(person.hostile ? Color(uiColor: Crowd.hostileColor) : HUDStyle.cream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        // Computer-run for now, and says so.
                        NameBadge(badge: .bot)
                    }
                    if let title = GameSession.botTitle(level: person.level, id: person.id) {
                        TitleBadge(title: title, size: 12)
                    }
                    Text("\(race) · \(heroClass)")
                        .font(HUDStyle.font(12))
                        .foregroundStyle(HUDStyle.gold)
                    if let note {
                        Text(note.text)
                            .font(HUDStyle.font(11))
                            .foregroundStyle(note.color)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                }
                .frame(minWidth: 250)
                .frame(maxWidth: .infinity)

                StatsPanel(level: L("Level {level}", ["level": person.level]), exp: nil, expToNext: 0,
                           hp: min(stats.hp, friend?.hp ?? stats.hp), mp: min(stats.mp, friend?.mp ?? stats.mp), stats: stats)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: L("Skills"))
                let skills = session.skills(of: person)
                if skills.isEmpty {
                    Text(L("None yet")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                } else {
                    LazyVGrid(columns: Self.tiles, alignment: .leading, spacing: 8) {
                        ForEach(skills) { skill in tile(name: skill.name) { SkillIcon(skill: skill, size: 40) } }
                    }
                }
            }
        }
    }

    /// What they hold and wear, as on the map and in battle (`GameSession.registerAdventurer`): in a
    /// festive season the hat or scarf they wear for it, the hat or necklace it takes the place of not.
    private var gear: [ItemDef] {
        let armor = GameSession.armor(for: person)
        let festive = GameSession.hat(for: person)
        let headpiece = festive?.type == .head ? nil : armor?.headpiece.flatMap(Content.shared.item)
        return [GameSession.weapon(for: person), armor, headpiece, festive].compactMap { $0 }
            + GameSession.trinkets(for: person).filter { $0.type != festive?.type }
    }

    /// Where they are and who they are to you, in its colour.
    private var note: (text: String, color: Color)? {
        if let place = session.whereabouts(of: person) {
            return (L("Waiting for you at {place}", ["place": place]), HUDStyle.orange)
        }
        if session.isInParty(person) { return (L("Travelling with you"), HUDStyle.green) }
        if session.isFriend(person) { return (L("Your friend"), HUDStyle.green) }
        if person.hostile { return (L("Looking for trouble!"), Color(uiColor: Crowd.hostileColor)) }
        return nil
    }

    /// Standing next to them, what you can do with them, as on their card by the map (`AdventurerCard`):
    /// befriend them, trade, duel in a danger zone, invite them along (friend or not), or ask to join
    /// the party they travel with. What takes you back to the map closes the window first.
    @ViewBuilder
    private var actions: some View {
        let here = session.nearbyAdventurer?.id == person.id
        let danger = coordinator.currentLand.danger == true
        if here {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if !person.hostile, !session.isFriend(person) {
                        Button { coordinator.befriend(person) } label: { word(L("Befriend")) }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    }
                    if !person.hostile {
                        Button { coordinator.trade(with: person) } label: { word(L("Trade")) }
                            .buttonStyle(PixelButtonStyle(compact: true))
                    }
                    if danger {
                        Button { onClose(); coordinator.challenge(person) } label: { word(L("Duel")) }
                            .buttonStyle(PixelButtonStyle(tint: Color(red: 1, green: 0.55, blue: 0.5), compact: true))
                    }
                }
                if !person.hostile, !session.isInParty(person) {
                    if session.partyIsFull {
                        Text(L("Your party is full")).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    } else {
                        Button { onClose(); coordinator.invite(person) } label: { word(L("Invite to party")) }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    }
                }
                if !person.hostile, session.nearbyGroupSize > 1, session.joinedParty == nil {
                    Button { onClose(); coordinator.askToJoin(person) } label: { word(L("Ask to join their party")) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                }
            }
            .padding(.top, 4)
        }
    }

    /// A button's word on one line, shrinking a little in a longer language rather than wrapping.
    private func word(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
    }

    /// Room for a picture with its name under it, as many to a row as fit.
    private static let tiles = [GridItem(.adaptive(minimum: 72), spacing: 6, alignment: .top)]

    private func tile<Picture: View>(name: String, @ViewBuilder picture: () -> Picture) -> some View {
        VStack(spacing: 3) {
            picture()
            Text(name)
                .font(HUDStyle.font(10))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Companion

    /// The companion they bring along, a step below their level as in battle.
    private var companion: MonsterDef? {
        person.petSpecies.flatMap { session.content.monster($0) }
    }

    /// Laid out as your own companion is on the Companions page: in its ring of skills, its name and
    /// element under it, its stats beside or under it, at full strength as it comes into a fight.
    private func companionPage(_ species: MonsterDef) -> some View {
        let level = max(1, person.level - 1)
        let stats = species.stats(at: level)
        return AdaptiveStack(spacing: 18) {
            VStack(spacing: 6) {
                CompanionDoll(art: species.art, skills: species.skills.compactMap { session.content.skill($0) })
                HStack(spacing: 6) {
                    Text(L("{owner}'s {monster}", ["owner": person.name, "monster": species.name]))
                        .font(HUDStyle.font(18))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ElementBadge(element: species.element)
                }
            }
            .frame(minWidth: 250)
            .frame(maxWidth: .infinity)

            StatsPanel(level: L("Level {level}", ["level": level]), exp: nil, expToNext: 0,
                       hp: stats.hp, mp: stats.mp, stats: stats)
        }
    }
}
