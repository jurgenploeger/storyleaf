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
    /// What you tapped in the bag or the bank: its card, over the bank.
    /// Debug `inspect=<item>`: that item's card, on the bag's side.
    @State private var picked: BankPick? = DebugLaunch.inspectedItem.flatMap { Content.shared.item($0) }.map { BankPick(item: $0, side: .bag) }
    /// A slot lifted to move it (`ItemSlotGrid`): the window holds still.
    @State private var dragLock = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                WindowTitle(L("Bank"), onClose: onClose)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            SpriteImage(art: npc.art, size: 44)
                            Text(reply ?? npc.greeting)
                                .font(HUDStyle.font(12))
                                .foregroundStyle(HUDStyle.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        BankPanel(session: session, reply: $reply, onPick: { picked = $0 }, dragging: $dragLock)
                    }
                    .padding(14)
                }
                .scrollDisabled(dragLock)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gameWindow()
            .menuWindowMargins()

            if let picked {
                Group {
                    if let item = picked.item {
                        ItemInfoCard(session: session, item: item, onClose: { self.picked = nil }, banking: picked.side)
                    } else {
                        BankCoinsCard(session: session, side: picked.side) { self.picked = nil }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: picked?.id)
    }
}

/// Something tapped in the bank window: an item, or the coins (`item` nil), on one side.
struct BankPick: Identifiable {
    let item: ItemDef?
    let side: BankSide
    var id: String { "\(side.rawValue).\(item?.id ?? "coins")" }
}

/// The bank's insides: your bag over the bank, RuneScape-style. Tap something, coins too, for its card
/// (`onPick`; playtesting 2026-10-26: "tap on an item to open its details in another modal"): how many
/// to put in or take out, or to delete. Deposit all empties the bag. Hold a slot to lift it and move it
/// about its side, the others sliding aside (`ItemSlotGrid`; "In the bank and inventory I should be
/// able to reorder any items"). The bank's search, sort and kinds ("Also add sorting and filtering to the
/// bank") are a way of looking, as the Bag's are: what's filtered out is still there, and a sort
/// leaves your order as it is till you move something while it's on. Nothing in the bank is lost to a
/// defeat.
struct BankPanel: View {
    let session: GameSession
    @Binding var reply: String?
    let onPick: (BankPick) -> Void
    /// True while a slot is lifted to move it: the window holds still.
    var dragging: Binding<Bool>? = nil

    /// The bag as the Bag tab sorts it.
    @AppStorage("bagSort") private var bagSort: ItemSort = .standard
    @AppStorage("bankSort") private var bankSort: ItemSort = .standard
    @State private var search = ""
    @State private var shelf: ItemShelf = .all

    var body: some View {
        let bag = ItemFinder.arrange(session.bagItems, search: "", sort: bagSort, session: session)
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
            if !bag.isEmpty || session.data.gold > 0 {
                grid(bag, coins: session.data.gold, side: .bag)
            }
            SectionTitle(text: L("Bank"))
            let all = session.bankItems
            if all.isEmpty && session.bankGold == 0 {
                EmptyNote(L("Nothing in the bank yet. Tap something in your bag to keep it here."), size: 11)
            }
            if !all.isEmpty {
                finder
                    .zIndex(1)
            }
            let narrowed = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shelf != .all
            let banked = ItemFinder.arrange(all.filter { shelf.holds($0) }, search: search, sort: bankSort, session: session, on: .bank)
            if narrowed && banked.isEmpty && !all.isEmpty {
                EmptyNote(L("Nothing in the bank matches."), size: 11)
                    .padding(.vertical, 8)
            }
            // The coins in the first slot, while you're not looking for something.
            let coins = narrowed ? 0 : session.bankGold
            if !banked.isEmpty || coins > 0 {
                grid(banked, coins: coins, side: .bank)
            }
        }
    }

    /// The bank's search, sort, and the kinds to show.
    private var finder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ItemSearchField(text: $search)
                ItemSortMenu(sort: $bankSort, options: ItemSort.allCases, bank: true)
            }
            // The sort's panel over the chips.
            .zIndex(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ItemShelf.allCases, id: \.self) { kind in
                        FilterChip(title: kind.title, on: shelf == kind) { shelf = kind }
                    }
                }
            }
        }
    }

    /// One side's things, the coins first: a tap for a thing's card; held, it lifts to move about
    /// its side.
    private func grid(_ items: [ItemDef], coins: Int, side: BankSide) -> some View {
        ItemSlotGrid(items: items, leads: coins > 0, dragging: dragging,
                     label: { item in
                         let count = session.held(item.id, on: side)
                         return count > 1 ? L("{item}, {count}", ["item": item.name, "count": count]) : item.name
                     },
                     onTap: { onPick(BankPick(item: $0, side: side)) },
                     onMove: { move($0, onto: $1, on: side) },
                     lead: { size in
                         Button { onPick(BankPick(item: nil, side: side)) } label: {
                             CoinsTile(amount: coins, size: size - 5)
                                 .padding(.top, 5)
                                 .padding(.trailing, 5)
                         }
                         .buttonStyle(PressScaleStyle())
                     },
                     tile: { item, size in
                         ItemIcon(item: item, size: size - 5, count: session.held(item.id, on: side))
                             .padding(.top, 5)
                             .padding(.trailing, 5)
                     })
    }

    /// Puts what was dragged where `target` is; sorted another way, the order you see is yours from
    /// then on, so the sort goes back to your order.
    private func move(_ id: String, onto target: String, on side: BankSide) {
        let sort = side == .bag ? bagSort : bankSort
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            guard session.moveItem(id, onto: target, on: side, sortedBy: sort) else { return }
            if side == .bag { bagSort = .standard } else { bankSort = .standard }
        }
        session.save()
    }
}

/// The coins' card in the bank: how many there are, and how many to put in or take out.
struct BankCoinsCard: View {
    let session: GameSession
    let side: BankSide
    let onClose: () -> Void

    var body: some View {
        let amount = side == .bag ? session.data.gold : session.bankGold
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CoinsTile(amount: amount, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Coins"))
                            .font(HUDStyle.font(17))
                            .foregroundStyle(HUDStyle.gold)
                        Text(side == .bag ? L("In your bag") : L("In the bank"))
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.dim)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 24)
                BankControls(session: session, item: nil, side: side, onClose: onClose)
            }
            .padding(16)
            .frame(maxWidth: 360, alignment: .leading)
            .gameWindow()
            .windowCloseButton(onClose)
            .padding(24)
            .popIn()
            .accessibilityElement(children: .contain)
        }
    }
}

/// How many to move between the bag and the bank, or to delete (playtesting 2026-10-26: "a stepper to
/// decide how many you want to deposit or take [...] delete items and click on the item count [...] to
/// show a numpad"): how many (`AmountPicker`); then Deposit or Withdraw, and Delete behind "…" (items
/// only, not what a quest you're on needs, asked twice). Out of the bank only as many as the bag has
/// room for. The card closes once none are left on its side.
struct BankControls: View {
    let session: GameSession
    /// Nil: the coins.
    let item: ItemDef?
    let side: BankSide
    let onClose: () -> Void

    @State private var amount = 1
    /// Whether the amount's keypad is open (`AmountPicker`).
    @State private var typing = false
    @State private var confirmingDelete = false
    /// "…" tapped: Delete shows under the buttons. Debug `more` opens it.
    @State private var showingMore = DebugLaunch.opensMore

    /// How many there are on this side.
    private var held: Int {
        switch side {
        case .bag: return item.map { session.count(of: $0.id) } ?? session.data.gold
        case .bank: return item.map { session.banked($0.id) } ?? session.bankGold
        }
    }

    /// How many can move to the other side: all of the bag's; out of the bank, what the bag has room for.
    private var movable: Int {
        guard side == .bank else { return held }
        guard item != nil else { return session.hasRoom(for: [], gold: held) ? held : 0 }
        return min(held, session.bagSlotsFree)
    }

    private var deletable: Bool {
        guard let item else { return false }
        return !session.questKeepsakes.contains(item.id)
    }

    var body: some View {
        let held = self.held
        let count = min(max(1, amount), max(1, held))
        VStack(alignment: .leading, spacing: 10) {
            Text(side == .bag ? L("In your bag: {count}", ["count": held]) : L("In the bank: {count}", ["count": held]))
                .font(HUDStyle.font(11))
                .foregroundStyle(HUDStyle.dim)
            AmountPicker(amount: $amount, typing: $typing, maximum: held)
            if movable < count {
                Text(movable == 0 ? L("Your bag is full. Put something in the bank first.")
                                  : L("Your bag has room for {count}.", ["count": movable]))
                    .font(HUDStyle.font(11))
                    .foregroundStyle(HUDStyle.orange)
            }
            if confirmingDelete, let item {
                deleteConfirmation(item: item, count: count)
            } else if !typing {
                buttons(count: count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: held) { _, now in
            if now == 0 { onClose() } else { amount = min(amount, now) }
        }
    }

    /// Deposit or Withdraw, and "…" by it for what's seldom wanted (playtesting 2026-10-26, progressive
    /// disclosure): a tap shows Delete under them, out of the way of a slip of the thumb.
    private func buttons(count: Int) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                if deletable {
                    Button {
                        SoundEffects.shared.play(.tap, volume: 0.7)
                        withAnimation(Reveal.animation) { showingMore.toggle() }
                    } label: {
                        IconImage(.more, size: 16)
                            .frame(minWidth: 18)
                    }
                    .buttonStyle(PixelButtonStyle(tint: showingMore ? HUDStyle.gold : HUDStyle.buttonFace, compact: true))
                    .accessibilityLabel(L("More"))
                    .accessibilityValue(showingMore ? L("Open") : "")
                }
                Spacer(minLength: 0)
                Button(side == .bag ? L("Deposit {count}", ["count": count]) : L("Withdraw {count}", ["count": count])) {
                    move(count)
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .disabled(movable < count)
                .opacity(movable < count ? 0.5 : 1)
            }
            if showingMore && deletable {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    Button {
                        confirmingDelete = true
                    } label: {
                        Label(L("Delete {count}", ["count": count]), icon: .close)
                    }
                    .buttonStyle(PixelButtonStyle(tint: HUDStyle.orange, compact: true))
                }
                .transition(.reveal)
            }
        }
    }

    private func deleteConfirmation(item: ItemDef, count: Int) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(L("Delete {item} for good? It can't be undone.", ["item": count > 1 ? "\(item.name) ×\(count)" : item.name]))
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.cream)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(L("Keep it")) {
                    confirmingDelete = false
                    showingMore = false
                }
                .buttonStyle(PixelButtonStyle())
                Button(L("Delete")) {
                    confirmingDelete = false
                    showingMore = false
                    session.destroy(item.id, count, fromBank: side == .bank)
                    session.save()
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.orange))
            }
        }
    }

    private func move(_ count: Int) {
        switch (side, item) {
        case (.bag, let item?): session.deposit(item.id, count)
        case (.bag, nil): session.depositGold(count)
        case (.bank, let item?): session.withdraw(item.id, count)
        case (.bank, nil): session.withdrawGold(count)
        }
        session.save()
    }
}
