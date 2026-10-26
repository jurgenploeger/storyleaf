import SwiftUI

/// Who gets it, after Use (a potion or an ether) or Give (a toy) in the Bag: the hero and every
/// companion it can go to, not only the one following you, each with what the item would fill,
/// faded when it wouldn't help. How many first, when you have more than one (`AmountPicker`;
/// playtesting 2026-10-26: "there it should also be able to select the amount"): a tap uses that
/// many there, no more than fills them up (or, for a toy, than they'd play with). The window stays
/// open, counting down, until you close it or the last one is gone. From the Bag it opens over the
/// item's card.
struct ItemTargetPicker: View {
    let session: GameSession
    let item: ItemDef
    /// Closes the window, with what happened last (the Bag shows it).
    let onClose: (String?) -> Void
    @State private var note: String?
    /// How many to use on whoever's tapped.
    @State private var amount = 1
    /// Whether the amount's keypad is open.
    @State private var typing = false

    private var isToy: Bool { item.toy == true }
    private var count: Int { session.count(of: item.id) }

    /// The companion following you first, then the others.
    private var pets: [Pet] {
        let active = session.data.activePetID
        return session.data.pets.filter { $0.id == active } + session.data.pets.filter { $0.id != active }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose(note) }
            VStack(spacing: 0) {
                WindowTitle(isToy ? L("Give {item}", ["item": item.name]) : L("Use {item}", ["item": item.name]), onClose: { onClose(note) })
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        if count > 1 {
                            Text(L("How many?")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
                            AmountPicker(amount: $amount, typing: $typing, maximum: count)
                                .padding(.bottom, 4)
                        }
                        if !typing {
                            if !isToy { row(.hero) }
                            ForEach(pets) { pet in row(.pet(pet)) }
                        }
                    }
                    .padding(14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 420)
            .fitHeight()
            .gameWindow()
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { onClose(note) }
            .padding(20)
            .popIn()
        }
        .foregroundStyle(HUDStyle.cream)
        .onChange(of: count) { _, now in amount = min(amount, max(1, now)) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item, size: 36, count: count)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Who gets it?")).font(HUDStyle.font(13))
                // What it does, until something's been used; then what came of it.
                Text(note ?? effect)
                    .font(HUDStyle.font(10))
                    .foregroundStyle(note == nil ? HUDStyle.dim : HUDStyle.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var effect: String {
        if isToy, let raise = item.stats {
            return L("For a companion: {bonus} for good", ["bonus": raise.bonusSummary])
        }
        return item.description ?? ""
    }

    private enum Target {
        case hero
        case pet(Pet)
    }

    private struct Facts {
        let name: String
        let art: String
        let level: Int
        let hp: Int, maxHP: Int
        let mp: Int, maxMP: Int
        /// Whether the item would do anything for them (`GameSession.use` and `giveToy` refuse otherwise).
        let helps: Bool
        /// How many a tap uses on them: the amount chosen, no more than they need.
        let uses: Int
    }

    private func describe(_ target: Target) -> Facts {
        switch target {
        case .hero:
            let hero = session.data.hero, stats = session.heroStats
            return Facts(name: hero.name, art: GameSession.heroArt, level: hero.level, hp: hero.hp, maxHP: stats.hp,
                         mp: hero.mp, maxMP: stats.mp, helps: fills(hp: hero.hp, of: stats.hp, mp: hero.mp, of: stats.mp),
                         uses: min(chosen, session.usesToFill(item.id)))
        case .pet(let pet):
            let stats = session.stats(of: pet)
            let helps = isToy ? (pet.toys ?? 0) < GameSession.toysPerCompanion
                              : fills(hp: pet.hp, of: stats.hp, mp: pet.mp, of: stats.mp)
            let needs = isToy ? session.toysWanted(by: pet.id) : session.usesToFill(item.id, onPet: pet.id)
            return Facts(name: pet.name, art: session.artID(for: pet), level: pet.level, hp: pet.hp, maxHP: stats.hp,
                         mp: pet.mp, maxMP: stats.mp, helps: helps, uses: min(chosen, needs))
        }
    }

    /// The amount chosen, no more than you have.
    private var chosen: Int { min(max(1, amount), max(1, count)) }

    private func fills(hp: Int, of maxHP: Int, mp: Int, of maxMP: Int) -> Bool {
        ((item.heal ?? 0) > 0 && hp < maxHP) || ((item.mp ?? 0) > 0 && mp < maxMP)
    }

    private func row(_ target: Target) -> some View {
        let facts = describe(target)
        return Button { use(on: target, times: facts.uses) } label: {
            HStack(spacing: 10) {
                SpriteImage(art: facts.art, size: 40)
                    .background(Circle().fill(.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(facts.name).font(HUDStyle.font(13))
                        Text(L("Lv {level}", ["level": facts.level])).font(HUDStyle.font(10).monospacedDigit()).foregroundStyle(HUDStyle.dim)
                        if facts.hp <= 0 {
                            Text(L("Fainted")).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.orange)
                        }
                    }
                    if isToy, case .pet(let pet) = target {
                        Text(toys(of: pet))
                            .font(HUDStyle.font(10))
                            .foregroundStyle(HUDStyle.green)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if (item.heal ?? 0) > 0 {
                            StatBar(label: L("HP"), value: facts.hp, maximum: facts.maxHP, color: HUDStyle.hp)
                        }
                        if (item.mp ?? 0) > 0 {
                            StatBar(label: L("MP"), value: facts.mp, maximum: facts.maxMP, color: HUDStyle.mp)
                        }
                    }
                }
                Spacer(minLength: 4)
                if !facts.helps {
                    Text(L("Full")).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                } else if chosen > 1 {
                    // How many a tap uses here, when it's more than one.
                    Text("×\(facts.uses)")
                        .font(HUDStyle.mono(13))
                        .foregroundStyle(HUDStyle.gold)
                        .accessibilityLabel(isToy ? L("Gives {count}", ["count": facts.uses]) : L("Uses {count}", ["count": facts.uses]))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(facts.helps ? 0.08 : 0.03)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!facts.helps)
        .opacity(facts.helps ? 1 : 0.5)
    }

    private func toys(of pet: Pet) -> String {
        let toys = pet.toys ?? 0
        return toys > 0
            ? L("Toys {count}/{max}: {bonus}", ["count": toys, "max": GameSession.toysPerCompanion, "bonus": (pet.toyStats ?? .zero).bonusSummary])
            : L("Toys {count}/{max}", ["count": toys, "max": GameSession.toysPerCompanion])
    }

    private func use(on target: Target, times: Int) {
        let result: String?
        let times = max(1, times)
        switch target {
        case .hero:
            result = session.use(item.id, times: times).note
        case .pet(let pet):
            result = isToy ? session.giveToy(item.id, to: pet.id, times: times).note : session.use(item.id, times: times, onPet: pet.id).note
        }
        SoundEffects.shared.play(isToy ? .learn : .potion)
        withAnimation(.easeOut(duration: 0.2)) { note = result }
        // The last one's gone: back to the Bag, which shows what happened.
        if count == 0 { onClose(result) }
    }
}
