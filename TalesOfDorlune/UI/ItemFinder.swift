import SwiftUI

/// How a list of things you carry is ordered (the Bag, the bank, the gear for a slot), remembered
/// between visits. Nonisolated like the other enums shown with `ForEach(id: \.self)`.
nonisolated enum ItemSort: String, CaseIterable {
    /// Your order of the bag or the bank (`GameSession+ItemOrder`): as the game lists them
    /// (content/items.json) till you move something.
    case standard
    /// As the game lists them, whatever your order: kind by kind, plainest first.
    case kind
    /// What you can wear now before what you can't, each by what it's worth to you
    /// (`GameSession.gearValue`), the best first; the rest as they come.
    case best
    case name, level, price, count

    var title: String {
        switch self {
        case .standard: L("Bag order")
        case .kind: L("Kind")
        case .best: L("Best for you")
        case .name: L("Name")
        case .level: L("Level")
        case .price: L("Price")
        case .count: L("How many")
        }
    }

    /// What it's called in the bank, where your order is the bank's.
    var bankTitle: String { self == .standard ? L("Bank order") : title }
}

/// Which kinds of thing a grid shows (the Bag, the bank). Nonisolated like the other enums in a
/// `ForEach(id: \.self)`.
nonisolated enum ItemShelf: String, CaseIterable {
    case all, items, gear, materials

    var title: String {
        switch self {
        case .all: L("All")
        case .items: L("Items")
        case .gear: L("Gear")
        case .materials: L("Materials")
        }
    }

    func holds(_ item: ItemDef) -> Bool {
        switch self {
        case .all: true
        case .items: item.type == .consumable
        case .gear: ItemType.equipmentSlots.contains(item.type)
        case .materials: item.type == .material
        }
    }
}

enum ItemFinder {
    /// `items` narrowed to those whose name (or kind, "boots") holds `search`, in `sort`'s order.
    /// Ties keep the order they came in. `side`: where they are, for how many there are.
    static func arrange(_ items: [ItemDef], search: String, sort: ItemSort, session: GameSession,
                        on side: BankSide = .bag) -> [ItemDef] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = query.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(query) || $0.type.displayName.localizedStandardContains(query)
        }
        let value: (ItemDef) -> Double
        switch sort {
        case .standard: return found
        case .kind:
            let rank = Dictionary(session.content.items.enumerated().map { ($0.element.id, $0.offset) }) { first, _ in first }
            value = { -Double(rank[$0.id] ?? Int.max) }
        case .name: return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // What you can wear comes first, however good the rest is: no gear is worth anywhere near this.
        case .best: value = { (session.equipIssue($0) == nil ? 1_000_000 : 0) + session.gearValue($0) }
        case .level: value = { Double($0.level ?? 0) }
        case .price: value = { Double($0.price) }
        case .count: value = { Double(session.held($0.id, on: side)) }
        }
        return found.enumerated()
            .map { (item: $0.element, place: $0.offset, value: value($0.element)) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.place < $1.place }
            .map { $0.item }
    }
}

/// A search field in the game's look: a magnifier, what you typed, and a clear button once there's
/// something to clear.
struct ItemSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            IconImage(.search, size: 14)
                .foregroundStyle(HUDStyle.dim)
            // The prompt in the HUD's dim cream: the system's grey hardly shows on the window's blue.
            TextField("", text: $text, prompt: Text(L("Search")).foregroundStyle(HUDStyle.dim))
                .font(HUDStyle.font(12))
                .foregroundStyle(HUDStyle.cream)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    IconImage(.close, size: 12)
                        .foregroundStyle(HUDStyle.dim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(Capsule().fill(.black.opacity(0.25)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

/// Sort: a button showing the order in use, which opens the choice of orders.
struct ItemSortMenu: View {
    @Binding var sort: ItemSort
    let options: [ItemSort]
    /// In the bank: your order is the bank's.
    var bank = false

    private func title(_ sort: ItemSort) -> String { bank ? sort.bankTitle : sort.title }

    var body: some View {
        Menu {
            Picker(L("Sort by"), selection: $sort) {
                ForEach(options, id: \.self) { Text(title($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                IconImage(.sort, size: 14)
                Text(title(sort))
                    .lineLimit(1)
            }
            .font(HUDStyle.font(11))
            .foregroundStyle(HUDStyle.cream)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Capsule().fill(.white.opacity(0.1)))
            .fixedSize()
        }
        .accessibilityLabel(L("Sort by"))
        .accessibilityValue(title(sort))
    }
}

/// One of a few kinds to show, or a filter you turn on and off: gold while it's on.
struct FilterChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            action()
        } label: {
            Text(title)
                .font(HUDStyle.font(11))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? HUDStyle.ink : HUDStyle.cream)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(on ? HUDStyle.gold : .white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A slot in the Bag or the bank you can move (playtesting 2026-10-26: "In the bank and inventory I
/// should be able to reorder any items"): hold it and drag it onto another slot on its side to put it
/// there (`GameSession.moveItem`), the slot under it lifting while it's over it. A tap still opens its
/// card. VoiceOver moves it a slot at a time.
struct ItemSlotMover: ViewModifier {
    let item: ItemDef
    let side: BankSide
    let size: CGFloat
    /// The slots shown before and after it, for VoiceOver.
    let before: ItemDef?
    let after: ItemDef?
    /// Puts the first id where the second is.
    let onMove: (_ id: String, _ target: String) -> Void
    @State private var targeted = false

    /// What's dragged: the side and the item's id, so a drop only takes its own side's things.
    nonisolated static func payload(_ id: String, on side: BankSide) -> String { "\(side.rawValue):\(id)" }

    nonisolated static func id(in payload: String, on side: BankSide) -> String? {
        let prefix = "\(side.rawValue):"
        return payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }

    func body(content: Self.Content) -> some View {
        let payload = Self.payload(item.id, on: side)
        let mySide = self.side, here = item.id, move = self.onMove
        return content
            .draggable(payload) {
                ItemIcon(item: item, size: size)
            }
            .dropDestination(for: String.self) { payloads, _ in
                guard let id = payloads.first.flatMap({ Self.id(in: $0, on: mySide) }), id != here else { return false }
                move(id, here)
                return true
            } isTargeted: { targeted = $0 }
            .scaleEffect(targeted ? 1.12 : 1)
            .shadow(color: targeted ? HUDStyle.gold : .clear, radius: 6)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
            .accessibilityAction(named: L("Move earlier")) { if let before { onMove(item.id, before.id) } }
            .accessibilityAction(named: L("Move later")) { if let after { onMove(item.id, after.id) } }
    }
}

extension View {
    /// Hold and drag to move it (`ItemSlotMover`); `shown`: the slots on its side as they show.
    func movableSlot(_ item: ItemDef, in shown: [ItemDef], side: BankSide, size: CGFloat,
                     onMove: @escaping (_ id: String, _ target: String) -> Void) -> some View {
        let index = shown.firstIndex { $0.id == item.id }
        let before = index.flatMap { $0 > 0 ? shown[$0 - 1] : nil }
        let after = index.flatMap { $0 + 1 < shown.count ? shown[$0 + 1] : nil }
        return modifier(ItemSlotMover(item: item, side: side, size: size, before: before, after: after, onMove: onMove))
    }
}
