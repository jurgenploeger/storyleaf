import SwiftUI

/// New skills to learn and known skills to raise, each for one skill point: a grid of their tiles
/// (playtesting 2026-10-24: "show them as thumbnails, and when you tap on them you can increase the
/// level"), and under it the one tapped, to learn, raise or cast. Used on the Character screen and the
/// Level Up card after a battle.
struct SkillChoices: View {
    let session: GameSession
    /// The skill tapped, shown under the grid; until one is, the first new one, else the first known.
    @State private var selected: String?

    private static let columns = [GridItem(.adaptive(minimum: 62, maximum: 86), spacing: 8, alignment: .top)]

    var body: some View {
        let learnable = session.learnableSkills
        let known = session.heroSkills
        let shown = selected.flatMap { id in (learnable + known).first { $0.id == id } } ?? learnable.first ?? known.first
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 10) {
                ForEach(learnable) { skill in
                    SkillTileButton(session: session, skill: skill, isNew: true, isSelected: skill.id == shown?.id) { selected = skill.id }
                }
                ForEach(known) { skill in
                    SkillTileButton(session: session, skill: skill, isNew: false, isSelected: skill.id == shown?.id) { selected = skill.id }
                }
            }
            if let shown {
                SkillDetail(session: session, skill: shown, isNew: learnable.contains { $0.id == shown.id })
                    .id(shown.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: shown?.id)
    }
}

/// "Bash (12 MP)": a skill's name with what it costs.
private func skillTitle(_ skill: SkillDef, mp: Int) -> Text {
    Text(skill.name) + Text(L(" ({cost} MP)", ["cost": mp])).foregroundStyle(HUDStyle.mp)
}

/// A skill's tile in the grid: its icon, NEW on one still to learn, its level under it, a gold plus
/// when a point would raise it, ringed in gold while it's the one shown below.
private struct SkillTileButton: View {
    let session: GameSession
    let skill: SkillDef
    let isNew: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let level = session.skillLevel(skill.id)
        let mastered = !isNew && level >= GameSession.maxSkillLevel
        let canRaise = session.unspentSkillPoints > 0 && (isNew || level < GameSession.skillLevelCap)
        let tag = isNew ? L("NEW") : L("Lv {level}", ["level": level])
        Button(action: onTap) {
            VStack(spacing: 4) {
                SkillIcon(skill: skill, size: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 54 * 0.26 + 4)
                            .strokeBorder(isSelected ? HUDStyle.gold : .clear, lineWidth: 2.5)
                            .padding(-4)
                    }
                    .shadow(color: isSelected || mastered ? HUDStyle.gold.opacity(0.6) : .clear, radius: 5)
                    .overlay(alignment: .topTrailing) {
                        if canRaise {
                            IconImage(.plus, size: 11)
                                .foregroundStyle(HUDStyle.ink)
                                .frame(width: 19, height: 19)
                                .background(Circle().fill(HUDStyle.gold))
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                                .offset(x: 6, y: -6)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Text(tag)
                            .font(HUDStyle.font(9))
                            .foregroundStyle(HUDStyle.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(isNew || mastered ? HUDStyle.gold : HUDStyle.cream))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                            .fixedSize()
                            .offset(y: 7)
                    }
                Text(skill.name)
                    .font(HUDStyle.font(10))
                    .foregroundStyle(isSelected ? HUDStyle.gold : HUDStyle.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(Text(skill.name + ", " + tag))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The skill tapped in the grid: what it does and costs, how far it's grown, and Learn, raise it a
/// level for a point, or (a field spell) Cast it here.
private struct SkillDetail: View {
    let session: GameSession
    let skill: SkillDef
    let isNew: Bool

    var body: some View {
        let level = isNew ? 1 : session.skillLevel(skill.id)
        let points = session.unspentSkillPoints
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SkillIcon(skill: skill, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        skillTitle(skill, mp: GameSession.mpCost(of: skill, level: level))
                        if let element = skill.element {
                            ElementBadge(element: element)
                        }
                    }
                    if let description = skill.description {
                        Text(description)
                            .font(HUDStyle.font(10))
                            .foregroundStyle(HUDStyle.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if !isNew { SkillGauge(level: level) }
                Spacer(minLength: 0)
                // Field spells are cast from here, outside battle.
                if !isNew, skill.kind == .field, let cast = session.onCastField {
                    let affordable = session.data.hero.mp >= GameSession.mpCost(of: skill, level: level)
                    Button(L("Cast")) { cast(skill) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                        .disabled(!affordable)
                        .opacity(affordable ? 1 : 0.5)
                }
                if isNew {
                    Button(L("Learn")) { session.learnSkill(skill.id) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                        .disabled(points == 0)
                        .opacity(points == 0 ? 0.5 : 1)
                } else if level < GameSession.skillLevelCap {
                    // Up a level for a point: the level it rises to on the button.
                    Button {
                        session.upgradeSkill(skill.id)
                    } label: {
                        HStack(spacing: 4) {
                            IconImage(.plus, size: 12)
                            Text(L("Lv {level}", ["level": level + 1]))
                        }
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                    .disabled(points == 0)
                    .opacity(points == 0 ? 0.5 : 1)
                    .accessibilityLabel(L("Raise {skill} to level {level}", ["skill": skill.name, "level": level + 1]))
                }
            }
        }
        .font(HUDStyle.font(12))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDStyle.gold.opacity(isNew ? 0.16 : 0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDStyle.gold.opacity(0.35), lineWidth: 1))
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
