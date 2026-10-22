import SwiftUI

/// Trading with an adventurer you're standing next to: what they'd buy from you (better than a
/// shop pays) and what they carry (things shops in this town might not stock). Offers change each
/// in-game day; each deal is made once.
struct TradeView: View {
    let session: GameSession
    let adventurer: Adventurer
    let onClose: () -> Void
    @State private var reply: String?
    /// The item tapped for a closer look.
    @State private var info: ItemDef?

    var body: some View {
        let offers = session.tradeOffers(with: adventurer)
        let buying = offers.filter { $0.kind == .theyBuy }
        let selling = offers.filter { $0.kind == .theySell }
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                FLTitleBar(title: L("Trade with {name}", ["name": adventurer.name]), icon: .coins, onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            SpriteImage(art: session.artID(for: adventurer), size: 40)
                            Text(reply ?? L("Got anything good? I've got a few things too."))
                                .font(HUDStyle.font(12))
                                .foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label(L("{gold} gold", ["gold": session.data.gold]), icon: .coins)
                            .font(HUDStyle.font(12))
                            .foregroundStyle(HUDStyle.gold)

                        Text(L("They'd buy")).font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
                        if buying.isEmpty {
                            Text(L("Nothing of yours catches their eye today.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                        }
                        ForEach(buying) { offer in
                            row(offer, button: L("Sell {gold}g", ["gold": offer.price]), enabled: session.count(of: offer.item.id) > 0,
                                note: L("Shop pays {gold}g · you have {count}", ["gold": GameSession.sellPrice(of: offer.item), "count": session.count(of: offer.item.id)]))
                        }

                        Text(L("They're selling")).font(HUDStyle.font(13)).foregroundStyle(HUDStyle.gold)
                        if selling.isEmpty {
                            Text(L("They've traded everything away for today.")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.dim)
                        }
                        ForEach(selling) { offer in
                            row(offer, button: L("Buy {gold}g", ["gold": offer.price]), enabled: session.data.gold >= offer.price,
                                note: summary(of: offer.item), warning: issue(with: offer.item))
                        }
                        Text(L("Tap an item to see more. Offers change every in-game day."))
                            .font(HUDStyle.font(10))
                            .foregroundStyle(HUDStyle.dim)
                    }
                    .padding(14)
                }
            }
            .frame(maxWidth: 520, maxHeight: 560)
            .gameWindow()
            .padding(14)

            if let info {
                ItemInfoCard(session: session, item: info) { self.info = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: info?.id)
    }

    /// What a seller's item is: a potion or material's own words, gear's kind and stats.
    private func summary(of item: ItemDef) -> String {
        if item.type == .consumable || item.type == .material {
            return item.description ?? item.type.displayName
        }
        return "\(item.type.displayName) · \(item.stats?.bonusSummary ?? "")"
    }

    /// Why you couldn't use a piece of gear (the class or level it needs), if you couldn't.
    private func issue(with item: ItemDef) -> String? {
        ItemType.equipmentSlots.contains(item.type) ? session.equipIssue(item) : nil
    }

    /// One offer: the item (tap it for a closer look), what's said about it, and the deal. `warning`:
    /// why you couldn't use it (the level or class it needs).
    private func row(_ offer: GameSession.TradeOffer, button: String, enabled: Bool, note: String,
                     warning: String? = nil) -> some View {
        HStack(spacing: 10) {
            Button { info = offer.item } label: {
                HStack(spacing: 10) {
                    ItemIcon(item: offer.item, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(offer.item.name).font(HUDStyle.font(12)).foregroundStyle(HUDStyle.cream)
                        Text(note).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.dim)
                        if let warning {
                            Text(warning).font(HUDStyle.font(10)).foregroundStyle(HUDStyle.orange)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L("Shows what it does and who can use it"))
            Button(button) {
                if session.trade(offer) {
                    session.post(offer.kind == .theyBuy
                                 ? L("Sold {item} to {name} for {gold} gold.", ["item": offer.item.name, "name": adventurer.name, "gold": offer.price])
                                 : L("Bought {item} from {name} for {gold} gold.", ["item": offer.item.name, "name": adventurer.name, "gold": offer.price]), .reward)
                    reply = offer.kind == .theyBuy ? L("Just what I needed, thanks!") : L("Pleasure doing business!")
                    session.save()
                } else {
                    reply = offer.kind == .theyBuy ? L("Looks like you don't have that any more.") : L("Come back when you've got the gold.")
                }
            }
            .buttonStyle(PixelButtonStyle(tint: enabled ? HUDStyle.gold : HUDStyle.dim, compact: true))
        }
    }
}
