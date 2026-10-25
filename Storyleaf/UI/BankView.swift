import SwiftUI

/// A banker's bank (playtesting 2026-10-25: "I want to add a bank to the game"; then "the bank
/// interface itself should be a bigger modal, just like the other modals"): after a word with the
/// banker (`NPCDialogView`'s Open the bank), a window as big as a menu window's, the banker and what
/// they say at the top, your bag and the bank under it. Nothing in the bank is lost to a defeat.
struct BankView: View {
    let npc: NPCDef
    let session: GameSession
    let onClose: () -> Void
    @State private var reply: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                FLTitleBar(title: L("Bank"), icon: .coins, onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            SpriteImage(art: npc.art, size: 44)
                            Text(reply ?? npc.greeting)
                                .font(HUDStyle.font(12))
                                .foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        BankPanel(session: session, reply: $reply)
                    }
                    .padding(14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gameWindow()
            .menuWindowMargins()
        }
    }
}

/// The bank's insides: your bag over the bank, RuneScape-style. Tap something in the bag to put it all in the bank, something in the bank to
/// take it all out (if the bag has room); the coins go in and out the same way, and Deposit all empties
/// the bag. Nothing in the bank is lost to a defeat.
struct BankPanel: View {
    let session: GameSession
    @Binding var reply: String?

    private static let slot: CGFloat = 48
    private let columns = [GridItem(.adaptive(minimum: BankPanel.slot + 6, maximum: BankPanel.slot + 12), spacing: 6)]

    var body: some View {
        let bag = session.content.items.filter { session.count(of: $0.id) > 0 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: L("Bag {used}/{slots}", ["used": session.bagSlotsUsed, "slots": GameSession.bagSlots]))
                Spacer()
                Button(L("Deposit all")) {
                    session.depositAll()
                    session.save()
                    reply = L("All safe with me.")
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold, compact: true))
                .disabled(bag.isEmpty && session.data.gold == 0)
            }
            if bag.isEmpty && session.data.gold == 0 {
                EmptyNote(L("Your bag is empty."), size: 11)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                if session.data.gold > 0 {
                    Button {
                        session.depositGold(session.data.gold)
                        session.save()
                    } label: { CoinsTile(amount: session.data.gold, size: Self.slot) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityHint(L("Puts it in the bank"))
                }
                ForEach(bag) { item in
                    Button {
                        session.deposit(item.id)
                        session.save()
                    } label: { ItemIcon(item: item, size: Self.slot, count: session.count(of: item.id)) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(item.name)
                    .accessibilityHint(L("Puts it in the bank"))
                }
            }
            SectionTitle(text: L("Bank"))
            let banked = session.bankItems
            if banked.isEmpty && session.bankGold == 0 {
                EmptyNote(L("Nothing in the bank yet. Tap something in your bag to keep it here."), size: 11)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                if session.bankGold > 0 {
                    Button {
                        if !session.withdrawGold(session.bankGold) { reply = L("Your bag is full. Put something in the bank first.") }
                        session.save()
                    } label: { CoinsTile(amount: session.bankGold, size: Self.slot) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityHint(L("Takes it out of the bank"))
                }
                ForEach(banked) { item in
                    Button {
                        if !session.withdraw(item.id) { reply = L("Your bag is full. Put something in the bank first.") }
                        session.save()
                    } label: { ItemIcon(item: item, size: Self.slot, count: session.banked(item.id)) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(item.name)
                    .accessibilityHint(L("Takes it out of the bank"))
                }
            }
        }
    }
}
