import SwiftUI

/// New skills to learn and known skills to raise, each for one skill point. Used on the
/// Character screen and the Level Up card after a battle.
struct SkillChoices: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.learnableSkills) { skill in
                LearnSkillRow(session: session, skill: skill)
            }
            ForEach(session.heroSkills) { skill in
                SkillRow(session: session, skill: skill)
            }
        }
    }
}

/// "Bash (12 MP)": a skill's name with what it costs.
private func skillTitle(_ skill: SkillDef, mp: Int) -> Text {
    Text(skill.name) + Text(L(" ({cost} MP)", ["cost": mp])).foregroundStyle(HUDStyle.mp)
}

/// A skill your class just unlocked: learn it for a point.
struct LearnSkillRow: View {
    let session: GameSession
    let skill: SkillDef

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            SkillIcon(skill: skill, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    skillTitle(skill, mp: GameSession.mpCost(of: skill, level: 1))
                    Text(L("NEW"))
                        .font(HUDStyle.font(9))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HUDStyle.gold))
                    if let element = skill.element {
                        ElementBadge(element: element)
                    }
                }
                if let description = skill.description {
                    Text(description).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
            }
            Spacer()
            Button(L("Learn")) { session.learnSkill(skill.id) }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                .disabled(session.unspentSkillPoints == 0)
                .opacity(session.unspentSkillPoints == 0 ? 0.5 : 1)
        }
        .font(HUDStyle.font(12))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDStyle.gold.opacity(0.12)))
    }
}

struct SkillRow: View {
    let session: GameSession
    let skill: SkillDef

    var body: some View {
        let level = session.skillLevel(skill.id)
        HStack(alignment: .center, spacing: 8) {
            SkillIcon(skill: skill, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    skillTitle(skill, mp: GameSession.mpCost(of: skill, level: level))
                    if let element = skill.element {
                        ElementBadge(element: element)
                    }
                }
                if let description = skill.description {
                    Text(description).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
            }
            Spacer()
            SkillGauge(level: level)
            // Field spells are cast from here, outside battle.
            if skill.kind == .field, let cast = session.onCastField {
                let affordable = session.data.hero.mp >= GameSession.mpCost(of: skill, level: level)
                Button(L("Cast")) { cast(skill) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    .disabled(!affordable)
                    .opacity(affordable ? 1 : 0.5)
            }
            if session.unspentSkillPoints > 0, level < GameSession.skillLevelCap {
                Button {
                    session.upgradeSkill(skill.id)
                } label: {
                    IconImage(.plus, size: 15)
                        .foregroundStyle(HUDStyle.ink)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(HUDStyle.gold).overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5)))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(L("Raise {skill} to level {level}", ["skill": skill.name, "level": level + 1]))
            }
        }
        .font(HUDStyle.font(12))
    }
}

/// After a battle that levelled you up: spend the new point now, or keep it for later.
struct LevelUpCard: View {
    let session: GameSession
    let level: Int
    let onDone: () -> Void

    var body: some View {
        let points = session.unspentSkillPoints
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(L("Level {level}!", ["level": level]))
                    .font(HUDStyle.font(26))
                    .foregroundStyle(HUDStyle.gold)
                Text(points > 0
                     ? (points == 1
                        ? L("You have 1 skill point. Learn a new skill or power one up.")
                        : L("You have {count} skill points. Learn a new skill or power one up.", ["count": points]))
                     : L("All points spent. Good choice!"))
                    .font(HUDStyle.font(12))
                    .foregroundStyle(HUDStyle.cream)
                    .multilineTextAlignment(.center)
            }
            ScrollView {
                SkillChoices(session: session)
                    .foregroundStyle(HUDStyle.cream)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 260)
            Button(points > 0 ? L("Decide later") : L("Done"), action: onDone)
                .buttonStyle(PixelButtonStyle(tint: points > 0 ? HUDStyle.cream : HUDStyle.gold))
        }
        .padding(20)
        .frame(maxWidth: 440)
        // Hugs the list, which scrolls past 260 points, or sooner on a phone on its side.
        .fitHeight()
        .gameWindow()
        // Closing it is Decide later: unspent points wait in the Character menu.
        .windowCloseButton(onDone)
        .padding(20)
    }
}

/// A skill's progress: ten segments in a little bar that fill as you raise it, warming from bronze
/// through silver to gold, and glowing in rainbow colours once mastered. Past mastery the bar fills
/// again toward the next milestone (`GameSession.skillRank`: Heroic at 20, Epic, Mythic, Legendary at
/// 50) in that milestone's colour, its name and the level under it. Its label sits under it, so the bar
/// fits at the end of a skill's row.
struct SkillGauge: View {
    let level: Int

    private var mastered: Bool { level >= GameSession.maxSkillLevel }
    private var rank: Int { GameSession.skillRank(level) }
    /// Past mastery and on the way to the next milestone (or at one, the bar full in its colour).
    private var growing: Bool { level > GameSession.maxSkillLevel }
    private var legendary: Bool { level >= GameSession.skillLevelCap }

    /// Bronze for the first steps, then silver, then gold.
    private func color(for step: Int) -> Color {
        switch step {
        case ...3: Color(red: 0.85, green: 0.55, blue: 0.3)
        case 4...6: Color(red: 0.8, green: 0.85, blue: 0.92)
        default: HUDStyle.gold
        }
    }

    /// The colour of the milestone a growing skill is filling toward (or has just reached).
    private var rankColor: Color {
        let toward = level % 10 == 0 ? rank : rank + 1
        switch toward {
        case 2: return Color(red: 1, green: 0.62, blue: 0.3)       // Heroic, a warm flame
        case 3: return Color(red: 0.75, green: 0.5, blue: 1)       // Epic, violet
        case 4: return Color(red: 1, green: 0.4, blue: 0.5)        // Mythic, crimson
        default: return HUDStyle.gold                              // Legendary
        }
    }

    /// How many of the ten segments are filled.
    private var filled: Int {
        guard growing else { return level }
        return level % 10 == 0 ? 10 : level % 10
    }

    private var label: String {
        if !mastered { return L("Lv {level}/{max}", ["level": level, "max": GameSession.maxSkillLevel]) }
        let name = GameSession.skillRankName(rank) ?? L("Mastered")
        return growing ? L("{rank} Lv {level}", ["rank": name, "level": level]) : name
    }

    private static let rainbow = [Color(red: 1, green: 0.45, blue: 0.45), Color(red: 1, green: 0.8, blue: 0.35),
                                  Color(red: 0.5, green: 0.9, blue: 0.5), Color(red: 0.45, green: 0.75, blue: 1),
                                  Color(red: 0.75, green: 0.55, blue: 1)]

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 1.5) {
                ForEach(1...GameSession.maxSkillLevel, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(step <= filled ? (growing ? rankColor : color(for: step)) : Color.white.opacity(0.12))
                        .frame(width: 7, height: 8)
                }
            }
            .padding(2)
            .overlay {
                if mastered && (!growing || legendary) {
                    // Mastered, and Legendary: the whole bar shimmers in rainbow colours.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: Self.rainbow, startPoint: .leading, endPoint: .trailing))
                        .opacity(0.75)
                        .blendMode(.screen)
                }
            }
            .background(RoundedRectangle(cornerRadius: 3).fill(HUDStyle.ink.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(mastered ? HUDStyle.gold : .white.opacity(0.35), lineWidth: 1))
            .shadow(color: mastered ? (growing && !legendary ? rankColor : HUDStyle.gold).opacity(0.7) : .clear, radius: 4)
            Text(label)
                .font(HUDStyle.font(10))
                .foregroundStyle(mastered ? HUDStyle.gold : HUDStyle.cream)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mastered && !growing ? L("Mastered")
                            : growing ? L("{rank}, level {level} of {max}", ["rank": GameSession.skillRankName(rank) ?? L("Mastered"), "level": level, "max": GameSession.skillLevelCap])
                            : L("Level {level} of {max}", ["level": level, "max": GameSession.maxSkillLevel]))
    }
}
