import SwiftUI

/// The windows an item's card in the Bag opens over itself (playtesting 2026-10-26: "The whole app can
/// benefit from progressive disclosure"): the card keeps to what the item is and three buttons, Drop,
/// Trade and Use; how many, and at what price, is chosen in a window of its own, the card dimmed
/// behind. Its corner button closes it back to the card.
nonisolated enum ItemCardWindow: String, Sendable {
    case drop, trade
}

/// A small window over an item's card: its title and close button, the item, then what it's for.
struct ItemSubWindow<Inner: View>: View {
    let title: String
    let session: GameSession
    let item: ItemDef
    /// A line under the item's name.
    let subtitle: String
    let onClose: () -> Void
    @ViewBuilder let inner: () -> Inner

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                WindowTitle(title, onClose: onClose)
                // Scrolls only when it can't all fit (a phone on its side, the keypad open).
                FitOrScroll {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ItemIcon(item: item, size: 36, count: session.count(of: item.id))
                            Text(subtitle)
                                .font(HUDStyle.font(11))
                                .foregroundStyle(HUDStyle.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        inner()
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 360)
            .fitHeight()
            .gameWindow()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { onClose() }
            .padding(24)
            .popIn()
        }
        .foregroundStyle(HUDStyle.cream)
    }
}

/// Drop: how many of it to leave at your feet (`GameSession.drop`), 1 to all you carry.
struct ItemDropWindow: View {
    let session: GameSession
    let item: ItemDef
    /// Closes the window; true once some were dropped.
    let onClose: (Bool) -> Void

    @State private var amount = 1
    @State private var typing = false

    var body: some View {
        let held = session.count(of: item.id)
        let count = min(max(1, amount), max(1, held))
        ItemSubWindow(title: L("Drop {item}", ["item": item.name]), session: session, item: item,
                      subtitle: L("It lies where you stand for a while: yours to pick back up, then anyone's."),
                      onClose: { onClose(false) }) {
            Text(L("How many?")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            AmountPicker(amount: $amount, typing: $typing, maximum: held)
            if !typing {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button {
                        guard session.drop(item.id, count) else { return }
                        session.save()
                        onClose(true)
                    } label: {
                        Label(L("Drop {count}", ["count": count]), icon: .arrowDown)
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .disabled(held == 0)
                }
            }
        }
    }
}

/// Trade: your price for one, starting at the going price (`GameSession.tradeValue`), and how many to
/// sell, then up for trade (`GameSession.putUpForTrade`); for what's up already, what you asked, to
/// change, or Take off trade.
struct ItemTradeWindow: View {
    let session: GameSession
    let item: ItemDef
    let onClose: () -> Void

    @State private var price: Int
    @State private var amount: Int
    /// Which of the two has its keypad open.
    @State private var typingPrice = false
    @State private var typingAmount = false

    init(session: GameSession, item: ItemDef, onClose: @escaping () -> Void) {
        self.session = session
        self.item = item
        self.onClose = onClose
        let ask = session.tradeAsk(item.id)
        _price = State(initialValue: ask.price)
        _amount = State(initialValue: max(1, ask.count))
    }

    var body: some View {
        let held = session.count(of: item.id)
        let listed = session.isForTrade(item.id)
        let count = min(max(1, amount), max(1, held))
        let top = GameSession.topTradePrice(of: item)
        ItemSubWindow(title: L("Trade {item}", ["item": item.name]), session: session, item: item,
                      subtitle: L("Adventurers about come over with offers: your price if they'll pay it, else what they would."),
                      onClose: onClose) {
            if !typingAmount {
                Text(L("Price for one")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
                AmountPicker(amount: $price, typing: $typingPrice, maximum: GameSession.maxTradePrice, coins: true)
                Text(L("A shop pays {gold}g. Adventurers pay up to {top}g.", ["gold": GameSession.sellPrice(of: item), "top": top]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(price > top ? HUDStyle.orange : HUDStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typingPrice {
                Text(L("How many?")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
                AmountPicker(amount: $amount, typing: $typingAmount, maximum: held)
            }
            if !typingPrice && !typingAmount {
                let full = !listed && session.forTrade.count >= GameSession.maxForTrade
                if full {
                    Text(L("Up to {count} kinds of thing can be up for trade at once.", ["count": GameSession.maxForTrade]))
                        .font(HUDStyle.font(11))
                        .foregroundStyle(HUDStyle.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if listed {
                        Button(L("Take off trade")) {
                            session.takeOffTrade(item.id)
                            session.save()
                            onClose()
                        }
                        .buttonStyle(PixelButtonStyle())
                    }
                    Spacer(minLength: 0)
                    Button {
                        session.putUpForTrade(item.id, count: count, price: price)
                        session.save()
                        onClose()
                    } label: {
                        Label(listed ? L("Update") : L("Put up {count}", ["count": count]), icon: .coins)
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                    .disabled(full || held == 0)
                    .opacity(full || held == 0 ? 0.5 : 1)
                }
            }
        }
    }
}
