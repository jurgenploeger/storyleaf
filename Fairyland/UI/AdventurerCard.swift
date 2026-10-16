import SwiftUI

/// Fairyland's target frame for another adventurer you're standing next to: who they are,
/// how strong, and what you can do (befriend, invite to your party, or duel in danger zones, where
/// a beaten adventurer drops everything they carry).
struct AdventurerCard: View {
    let coordinator: GameCoordinator
    let adventurer: Adventurer

    private var session: GameSession { coordinator.session }

    var body: some View {
        let stats = session.stats(of: adventurer)
        let content = session.content
        let danger = coordinator.currentLand.danger == true
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Their picture opens their stats.
                Button { coordinator.open(.profile(.adventurer(adventurer))) } label: {
                    SpriteImage(art: session.artID(for: adventurer), size: 46)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("{name}'s stats", ["name": adventurer.name]))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(adventurer.name)
                            .foregroundStyle(Color(uiColor: adventurer.hostile ? Crowd.hostileColor : Crowd.adventurerColor))
                        // Computer-run for now, and says so.
                        NameBadge(badge: .bot)
                        Text(L("Lv {level}", ["level": adventurer.level])).foregroundStyle(HUDStyle.gold)
                        if session.isFriend(adventurer) {
                            IconImage(.heart, size: 12).foregroundStyle(HUDStyle.hp)
                        }
                    }
                    .font(HUDStyle.font(13))
                    Text("\(content.race(adventurer.raceID).name) · \(content.classDef(adventurer.classID).name)")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.cream)
                    if let pet = adventurer.petSpecies.flatMap(content.monster) {
                        Text(L("with a {pet}", ["pet": pet.name])).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                    // Travelling with friends, as you do with your party.
                    if session.nearbyGroupSize > 1 {
                        Text(L("In a party of {count}", ["count": session.nearbyGroupSize])).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                    }
                }
            }
            StatBar(label: L("HP"), value: stats.hp, maximum: stats.hp, color: HUDStyle.hp, labelWidth: 20)
                .frame(width: 190)
            HStack(spacing: 6) {
                if adventurer.hostile {
                    Text(L("Looking for trouble!")).font(HUDStyle.font(10)).foregroundStyle(Color(uiColor: Crowd.hostileColor))
                } else if !session.isFriend(adventurer) {
                    Button { coordinator.befriend(adventurer) } label: { word(L("Befriend")) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                } else if !session.isInParty(adventurer), session.partyMembers.count < GameSession.maxAllies {
                    Button { coordinator.invite(adventurer) } label: { word(L("Invite to party")) }
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                } else if session.partyMembers.count >= GameSession.maxAllies {
                    Text(L("Your party is full")).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                }
                if !adventurer.hostile {
                    Button { coordinator.trade(with: adventurer) } label: { word(L("Trade")) }
                        .buttonStyle(PixelButtonStyle(compact: true))
                }
                if danger {
                    Button { coordinator.challenge(adventurer) } label: { word(L("Duel")) }
                        .buttonStyle(PixelButtonStyle(tint: Color(red: 1, green: 0.55, blue: 0.5), compact: true))
                }
            }
        }
        .padding(10)
        .background(HUDStyle.panel)
        .frame(maxWidth: 260)
    }

    /// A button's word, without an icon so three fit side by side: on one line, shrinking a little
    /// in a longer language rather than wrapping.
    private func word(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
    }
}
