import SwiftUI

/// Someone whose stats you can look at: you, one of your companions, or an adventurer (a friend in
/// your party, or anyone you meet on the map).
enum Profile: Equatable {
    case hero
    case pet(UUID)
    case adventurer(Adventurer)
}

/// Fairyland Online's character window: tap someone on the map, or a face in the top-left corner, to see
/// who they are and how strong: level, HP and MP, attack, defense, magic and speed, and what they
/// fight with (their skills, your gear, a friend's companion), each with its picture.
struct ProfileCard: View {
    let session: GameSession
    let profile: Profile
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                if let facts = facts {
                    FLTitleBar(title: facts.name, icon: facts.icon, onClose: onClose)
                    // As tall as it needs, scrolling only on a short (landscape) screen.
                    ViewThatFits(in: .vertical) {
                        details(facts).padding(14)
                        ScrollView { details(facts).padding(14) }
                    }
                } else {
                    FLTitleBar(title: L("Nobody here"), onClose: onClose)
                    Text(L("They've gone on their way."))
                        .font(HUDStyle.font(12))
                        .foregroundStyle(HUDStyle.dim)
                        .padding(14)
                }
            }
            .frame(maxWidth: 340)
            .gameWindow()
            .padding(14)
        }
    }

    private func details(_ facts: Facts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WalkingSprite(art: facts.art, size: 76)
                    .background(Circle().fill(.white.opacity(0.07)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(facts.kind)
                        .font(HUDStyle.font(13))
                        .foregroundStyle(HUDStyle.gold)
                    if let title = facts.title {
                        TitleBadge(title: title, size: 10)
                    }
                    // BOT for a computer-run adventurer.
                    if let badge = facts.badge { NameBadge(badge: badge) }
                    if let element = facts.element { ElementBadge(element: element) }
                    if let note = facts.note {
                        Text(note)
                            .font(HUDStyle.font(10))
                            .foregroundStyle(facts.noteColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            StatBar(label: L("HP"), value: facts.hp, maximum: facts.stats.hp, color: HUDStyle.hp)
            if facts.stats.mp > 0 {
                StatBar(label: L("MP"), value: facts.mp, maximum: facts.stats.mp, color: HUDStyle.mp)
            }
            if let exp = facts.exp {
                StatBar(label: L("EXP"), value: exp.have, maximum: exp.need, color: HUDStyle.exp)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                StatCell(name: L("Attack"), value: facts.stats.attack)
                StatCell(name: L("Defense"), value: facts.stats.defense)
                StatCell(name: L("Magic"), value: facts.stats.magic)
                StatCell(name: L("Speed"), value: facts.stats.speed)
            }
            if let gear = facts.gear {
                SectionTitle(text: L("Gear"))
                if gear.isEmpty {
                    Text(L("Nothing worn")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                } else {
                    LazyVGrid(columns: Self.tiles, alignment: .leading, spacing: 8) {
                        ForEach(gear) { item in tile(name: item.name) { ItemIcon(item: item, size: 34) } }
                    }
                }
            }
            if let skills = facts.skills {
                SectionTitle(text: L("Skills"))
                if skills.isEmpty {
                    Text(L("None yet")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                } else {
                    LazyVGrid(columns: Self.tiles, alignment: .leading, spacing: 8) {
                        ForEach(skills) { skill in tile(name: skill.name) { SkillIcon(skill: skill, size: 34) } }
                    }
                }
            }
            if let companion = facts.companion {
                SectionTitle(text: L("Companion"))
                HStack(spacing: 10) {
                    WalkingSprite(art: companion.species.art, size: 50)
                        .background(Circle().fill(.white.opacity(0.07)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(companion.species.name)
                            .font(HUDStyle.font(12))
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text(L("Lv {level}", ["level": companion.level]))
                                .font(HUDStyle.font(11))
                                .foregroundStyle(HUDStyle.gold)
                            ElementBadge(element: companion.species.element)
                        }
                    }
                }
            }
        }
    }

    /// Room for a picture with its name under it, as many to a row as fit.
    private static let tiles = [GridItem(.adaptive(minimum: 66), spacing: 6, alignment: .top)]

    private func tile<Picture: View>(name: String, @ViewBuilder picture: () -> Picture) -> some View {
        VStack(spacing: 3) {
            picture()
            Text(name)
                .font(HUDStyle.font(9))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Everything the window shows about them, worked out once.
    private struct Facts {
        var name: String
        var icon: GameIcon
        var art: String
        /// "Lv 42 · Human Fighter", "Lv 12 · Jelly Puff".
        var kind: String
        var badge: PlayerBadge?
        /// The title they wear.
        var title: TitleDef?
        var element: Element?
        var note: String?
        var noteColor = HUDStyle.cream
        var stats: Stats
        var hp: Int
        var mp: Int
        var exp: (have: Int, need: Int)?
        /// What they fight with: your gear, their skills, a friend's companion (nil: not shown).
        var gear: [ItemDef]?
        var skills: [SkillDef]?
        var companion: (species: MonsterDef, level: Int)?
    }

    private var facts: Facts? {
        let content = session.content
        switch profile {
        case .hero:
            let hero = session.data.hero
            var facts = Facts(name: hero.name, icon: .user, art: GameSession.heroArt,
                              kind: L("Lv {level} · {race} {heroClass}", ["level": hero.level, "race": content.race(hero.raceID).name, "heroClass": session.heroClass.name]),
                              stats: session.heroStats, hp: hero.hp, mp: hero.mp,
                              exp: (hero.exp, GameSession.expToNext(level: hero.level)))
            facts.title = session.wornTitle
            facts.gear = ItemType.equipmentSlots.compactMap { session.equipped($0) }
            return facts

        case .pet(let id):
            guard let pet = session.data.pets.first(where: { $0.id == id }), let species = session.species(of: pet) else { return nil }
            var facts = Facts(name: pet.name, icon: .paw, art: session.artID(for: pet), kind: L("Lv {level} · {monster}", ["level": pet.level, "monster": species.name]),
                              element: species.element, stats: session.stats(of: pet), hp: pet.hp, mp: pet.mp,
                              exp: (pet.exp, GameSession.expToNext(level: pet.level)))
            if pet.hp <= 0 {
                facts.note = L("Fainted: a potion or a healer wakes it up.")
                facts.noteColor = HUDStyle.orange
            } else if session.data.activePetID == pet.id {
                facts.note = L("Following you")
                facts.noteColor = HUDStyle.green
            }
            facts.skills = species.skills.compactMap { content.skill($0) }
            return facts

        case .adventurer(let person):
            // A friend shows what their last fight with you left them; anyone else is at full strength.
            let stats = session.stats(of: person)
            let friend = session.data.friends?.first { $0.id == person.id }
            var facts = Facts(name: person.name, icon: .user, art: session.artID(for: person),
                              kind: L("Lv {level} · {race} {heroClass}", ["level": person.level, "race": content.race(person.raceID).name, "heroClass": content.classDef(person.classID).name]),
                              stats: stats, hp: min(stats.hp, friend?.hp ?? stats.hp), mp: min(stats.mp, friend?.mp ?? stats.mp))
            facts.badge = .bot
            facts.title = GameSession.botTitle(level: person.level, id: person.id)
            // What they hold and wear, as on the map and in battle (`registerAdventurer`): in a festive
            // season the hat or scarf they wear for it, the hat it takes the place of not.
            let armor = GameSession.armor(for: person)
            let festive = GameSession.hat(for: person)
            let headpiece = festive?.type == .head ? nil : armor?.headpiece.flatMap(Content.shared.item)
            facts.gear = [GameSession.weapon(for: person), armor, headpiece, festive].compactMap { $0 }
            if let place = session.whereabouts(of: person) {
                facts.note = L("Waiting for you at {place}", ["place": place])
                facts.noteColor = HUDStyle.orange
            } else if session.isInParty(person) {
                facts.note = L("Travelling with you")
                facts.noteColor = HUDStyle.green
            } else if session.isFriend(person) {
                facts.note = L("Your friend")
                facts.noteColor = HUDStyle.green
            } else if person.hostile {
                facts.note = L("Looking for trouble!")
                facts.noteColor = Color(uiColor: Crowd.hostileColor)
            }
            facts.skills = session.skills(of: person)
            // Their companion fights a step below their level, as in battle.
            if let species = person.petSpecies.flatMap({ content.monster($0) }) {
                facts.companion = (species, max(1, person.level - 1))
            }
            return facts
        }
    }
}
