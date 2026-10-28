import SwiftUI

/// The day's gift, the first time you're in the game that day: what it held, and where the round is.
struct DailyGiftCard: View {
    let session: GameSession
    let gift: GameSession.DailyGift
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                WindowTitle(L("Daily gift"), onClose: onClose)
                VStack(spacing: 12) {
                    Text(L("Day {day} of {days}", ["day": gift.day, "days": gift.days]))
                        .font(HUDStyle.font(14))
                        .foregroundStyle(HUDStyle.gold)
                    GiftRound(current: gift.day, days: gift.days)
                    if let greeting = gift.greeting {
                        // The first gift of a festive season brings its hat.
                        Text(greeting)
                            .font(HUDStyle.font(12))
                            .foregroundStyle(HUDStyle.gold)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 14) {
                        if gift.gold > 0 {
                            GoldPill(amount: gift.gold, size: 15)
                        }
                        ForEach(RewardList.group(gift.items, in: session), id: \.item.id) { entry in
                            ItemIcon(item: entry.item, size: 38, count: entry.count)
                                .accessibilityLabel(entry.count > 1 ? "\(entry.item.name) ×\(entry.count)" : entry.item.name)
                        }
                    }
                    Text(L("A gift waits each day you play. Come back tomorrow for the next one!"))
                        .font(HUDStyle.font(11))
                        .foregroundStyle(HUDStyle.dim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("Thanks!"), action: onClose)
                        .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                }
                .padding(16)
            }
            .frame(maxWidth: 340)
            .gameWindow()
            .padding(16)
        }
        .foregroundStyle(HUDStyle.cream)
    }
}

/// The daily gift's round: the days given ticked, `current` lit, the last (the best) ringed.
struct GiftRound: View {
    let current: Int
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(1, days), id: \.self) { day in
                Text("\(day)")
                    .font(HUDStyle.font(11))
                    .foregroundStyle(day <= current ? HUDStyle.ink : HUDStyle.cream.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(day == current ? HUDStyle.gold : day < current ? HUDStyle.gold.opacity(0.5) : .white.opacity(0.1)))
                    .overlay(Circle().strokeBorder(day == days ? HUDStyle.gold : .clear, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Day {day} of {days}", ["day": current, "days": days]))
    }
}

/// Items counted for showing ("Potion ×3").
enum RewardList {
    struct Entry {
        let item: ItemDef
        var count: Int
    }

    static func group(_ ids: [String], in session: GameSession) -> [Entry] {
        var entries: [Entry] = []
        for id in ids {
            guard let item = session.content.item(id) else { continue }
            if let index = entries.firstIndex(where: { $0.item.id == id }) {
                entries[index].count += 1
            } else {
                entries.append(Entry(item: item, count: 1))
            }
        }
        return entries
    }
}

// MARK: - Bounties

/// Today's bounties, the Quests tab's Daily challenges: what each asks and how far along it is, Claim
/// once it's done, the bonus for claiming them all, and the daily gift's round.
struct BountiesSection: View {
    let session: GameSession

    var body: some View {
        let board = session.data.bounties
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: L("Today's bounties"))
                Spacer()
                Text(L("New ones each day"))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
            }
            ForEach(Array((board?.bounties ?? []).enumerated()), id: \.offset) { index, bounty in
                BountyRow(session: session, bounty: bounty, index: index)
            }
            if let board, !board.bounties.isEmpty {
                bonus(claimed: board.bonusClaimed)
            }
            giftLine
        }
        .onAppear { session.refreshBounties() }
    }

    /// The bonus for all of them: what it pays, and Claim once they're all claimed.
    private func bonus(claimed: Bool) -> some View {
        let rules = session.content.rewards.bounties.bonus
        let exp = max(1, Int((Double(GameSession.expToNext(level: session.data.hero.level)) * rules.exp).rounded()))
        return HStack(spacing: 10) {
            IconImage(.gift, size: 18)
                .foregroundStyle(HUDStyle.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Claim them all for a bonus"))
                    .font(HUDStyle.font(12))
                HStack(spacing: 8) {
                    Label(L("{exp} EXP", ["exp": exp]), icon: .star, size: 12)
                    ForEach(RewardList.group(rules.items ?? [], in: session), id: \.item.id) { entry in
                        ItemIcon(item: entry.item, size: 20, count: entry.count)
                            .accessibilityLabel(entry.item.name)
                    }
                }
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.dim)
            }
            Spacer(minLength: 6)
            if claimed {
                IconImage(.check, size: 16)
                    .foregroundStyle(HUDStyle.green)
                    .accessibilityLabel(L("Claimed"))
            } else if session.canClaimBountyBonus {
                Button(L("Claim")) { session.claimBountyBonus() }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(HUDStyle.gold.opacity(session.canClaimBountyBonus ? 0.16 : 0.06)))
    }

    /// The daily gift: given when you first play each day; where its round is.
    private var giftLine: some View {
        let days = session.content.rewards.dailyGifts.count
        let given = session.data.giftDays ?? 0
        let today = session.hasCollectedGift() && given > 0 ? (given - 1) % max(1, days) + 1 : 0
        return HStack(spacing: 10) {
            IconImage(.gift, size: 18)
                .foregroundStyle(HUDStyle.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(today > 0 ? L("Daily gift: day {day} of {days}. The next one comes tomorrow.", ["day": today, "days": days])
                               : L("Daily gift: a new one each day you play."))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                GiftRound(current: today, days: days)
            }
        }
        .padding(.top, 2)
    }
}

private struct BountyRow: View {
    let session: GameSession
    let bounty: Bounty
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            IconImage(icon, size: 18)
                .foregroundStyle(HUDStyle.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.describe(bounty))
                    .font(HUDStyle.font(12))
                    .fixedSize(horizontal: false, vertical: true)
                GlossyBar(fraction: CGFloat(bounty.progress) / CGFloat(max(1, bounty.count)),
                          color: bounty.isDone ? HUDStyle.green : HUDStyle.gold, height: 6)
                HStack(spacing: 10) {
                    Text("\(bounty.progress)/\(bounty.count)")
                    GoldPill(amount: bounty.gold, size: 10)
                    Label(L("{exp} EXP", ["exp": bounty.exp]), icon: .star, size: 12)
                }
                .font(HUDStyle.font(10))
                .foregroundStyle(HUDStyle.dim)
            }
            Spacer(minLength: 6)
            if bounty.claimed {
                IconImage(.check, size: 16)
                    .foregroundStyle(HUDStyle.green)
                    .accessibilityLabel(L("Claimed"))
            } else if bounty.isDone {
                Button(L("Claim")) { session.claimBounty(index) }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(bounty.isDone && !bounty.claimed ? 0.12 : 0.05)))
    }

    private var icon: GameIcon {
        switch bounty.type {
        case .defeatOnMap?: .map
        case .defeatElement?: .sparkles
        case .wins?: .sword
        case .rare?: .star
        case .seal?: .paw
        case nil: .book
        }
    }
}

// MARK: - Titles

/// The Character tab's titles: those earned, to wear over your name (tap one; tap it again to take
/// it off), and the next few to earn with how far along each is.
struct TitlesSection: View {
    let session: GameSession
    @State private var showsAll = false

    var body: some View {
        let titles = session.content.titles
        let earned = titles.filter { session.hasEarned($0) }
        let ahead = titles.filter { !session.hasEarned($0) }.sorted { fraction($0) > fraction($1) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: L("Titles"))
                Spacer()
                Text(L("{count} of {total}", ["count": earned.count, "total": titles.count]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.gold)
            }
            if earned.isEmpty {
                Text(L("Earn titles as you go: levels, lands, monsters, bosses and more. Wear one over your name."))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("Tap a title to wear it over your name."))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                WrapRows(spacing: 6) {
                    ForEach(earned) { title in
                        let worn = session.data.title == title.id
                        Button {
                            session.wear(worn ? nil : title)
                        } label: {
                            // Each in its badge; the one you wear ringed in cream, with a tick.
                            TitleBadge(title: title, size: 11)
                                .padding(4)
                                .overlay(Capsule().strokeBorder(HUDStyle.cream.opacity(worn ? 0.9 : 0), lineWidth: 2))
                                .overlay(alignment: .topTrailing) {
                                    if worn {
                                        IconImage(.check, size: 9)
                                            .foregroundStyle(HUDStyle.ink)
                                            .padding(3)
                                            .background(Circle().fill(HUDStyle.cream))
                                            .offset(x: 2, y: -2)
                                    }
                                }
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityAddTraits(worn ? .isSelected : [])
                        .accessibilityHint(worn ? L("Takes it off") : L("Wears it over your name"))
                    }
                }
            }
            ForEach(showsAll ? ahead : Array(ahead.prefix(4))) { title in
                TitleGoalRow(session: session, title: title)
            }
            if ahead.count > 4 {
                Button(showsAll ? L("Show fewer") : L("Show all {count} to earn", ["count": ahead.count])) {
                    withAnimation(.easeOut(duration: 0.2)) { showsAll.toggle() }
                }
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.gold)
            }
        }
    }

    private func fraction(_ title: TitleDef) -> Double {
        let progress = session.titleProgress(title)
        return Double(progress.have) / Double(max(1, progress.need))
    }
}

/// A title still to earn: its name, what it takes, and how far along you are.
private struct TitleGoalRow: View {
    let session: GameSession
    let title: TitleDef

    var body: some View {
        let progress = session.titleProgress(title)
        HStack(spacing: 10) {
            IconImage(.lock, size: 14)
                .foregroundStyle(HUDStyle.dim)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title.name)
                        .font(HUDStyle.font(12))
                    Spacer()
                    Text("\(min(progress.have, progress.need))/\(progress.need)")
                        .font(HUDStyle.font(10))
                        .foregroundStyle(HUDStyle.gold)
                }
                Text(session.titleRequirement(title))
                    .font(HUDStyle.font(10))
                    .foregroundStyle(HUDStyle.dim)
                GlossyBar(fraction: CGFloat(min(progress.have, progress.need)) / CGFloat(max(1, progress.need)), color: HUDStyle.gold, height: 5)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04)))
        .accessibilityElement(children: .combine)
    }
}
