import SwiftUI

/// Change (Character → Equipment): every piece you have for that slot in a grid, what you're
/// wearing first and trimmed in gold, what you can't use yet faded, and the gold upgrade arrow on
/// anything better. With a handful to choose from, search, sort (the best for you first) and show
/// only what you can wear. A tap opens the piece's card (`ItemInfoCard`) with Cancel and Equip, or
/// Unequip for what you're wearing.
struct EquipmentPicker: View {
    let session: GameSession
    let slot: ItemType
    let onClose: () -> Void
    @State private var search = ""
    @AppStorage("gearSort") private var sort: ItemSort = .best
    /// Only what you can put on now (your class's, at your level).
    @AppStorage("gearWearableOnly") private var wearableOnly = false
    /// The piece whose card is open. Debug `inspect=<item>` opens one from the bag.
    @State private var open: Pick? = DebugLaunch.inspectedItem.flatMap { Content.shared.item($0) }.map { Pick(item: $0, worn: false) }

    private struct Pick {
        let item: ItemDef
        /// The one you're wearing (you may also carry more of the same in your bag).
        let worn: Bool
    }

    private var worn: ItemDef? { session.equipped(slot) }
    private var spares: [ItemDef] { session.bagEquipment.filter { $0.type == slot } }
    /// The spares you're looking for, in the order you chose.
    private var shown: [ItemDef] {
        ItemFinder.arrange(spares.filter { !wearableOnly || session.equipIssue($0) == nil },
                           search: search, sort: sort, session: session)
    }
    /// Enough to look through that search and sort earn their room.
    private var findable: Bool { spares.count > 3 }
    private static let sorts: [ItemSort] = [.best, .level, .name, .price, .standard]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                FLTitleBar(title: slot.displayName, icon: Self.icon(of: slot), onClose: onClose)
                if findable {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ItemSearchField(text: $search)
                            ItemSortMenu(sort: $sort, options: Self.sorts)
                        }
                        FilterChip(title: L("Can wear"), on: wearableOnly) { wearableOnly.toggle() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
                ScrollView {
                    if worn == nil && spares.isEmpty {
                        EmptyNote(L("Nothing for this slot yet. Shops, smiths and monsters have more."), size: 11)
                            .padding(14)
                    } else {
                        let found = findable ? shown : spares
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            if let worn { tile(worn, wearing: true) }
                            ForEach(found) { tile($0, wearing: false) }
                        }
                        .padding(14)
                        if found.isEmpty && !spares.isEmpty {
                            EmptyNote(L("Nothing in your bag matches."), size: 11)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 14)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 460)
            .fitHeight()
            .gameWindow()
            .padding(20)
            .popIn()

            if let pick = open {
                ItemInfoCard(session: session, item: pick.item,
                             onClose: { withAnimation(.easeOut(duration: 0.2)) { open = nil } },
                             onEquip: pick.worn ? nil : { wear(pick.item) },
                             onUnequip: pick.worn ? { takeOff() } : nil)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .foregroundStyle(HUDStyle.cream)
    }

    /// Equip or Unequip on the card: done, so back to the Character tab, which shows the change.
    private func wear(_ item: ItemDef) {
        session.equip(item.id)
        onClose()
    }

    private func takeOff() {
        session.unequip(slot)
        onClose()
    }

    private func tile(_ item: ItemDef, wearing: Bool) -> some View {
        let usable = wearing || session.equipIssue(item) == nil
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { open = Pick(item: item, worn: wearing) }
        } label: {
            VStack(spacing: 4) {
                ItemIcon(item: item, size: 44, count: wearing ? 1 : session.count(of: item.id),
                         upgrade: !wearing && session.isUpgrade(item))
                Text(item.name)
                    .font(HUDStyle.font(11))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let bonus = item.stats?.bonusSummary, !bonus.isEmpty {
                    Text(bonus)
                        .font(HUDStyle.font(9))
                        .foregroundStyle(HUDStyle.green)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                if wearing {
                    Text(L("Equipped"))
                        .font(HUDStyle.font(9))
                        .foregroundStyle(HUDStyle.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HUDStyle.gold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(wearing ? 0.1 : 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(wearing ? HUDStyle.gold : .clear, lineWidth: 2))
            )
            .opacity(usable ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }

    static func icon(of slot: ItemType) -> GameIcon {
        switch slot {
        case .weapon: .sword
        case .armor: .shield
        case .necklace: .gem
        case .boots: .wind
        default: .ring
        }
    }
}
