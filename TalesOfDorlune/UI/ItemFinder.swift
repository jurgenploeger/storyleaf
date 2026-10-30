import SwiftUI
import UIKit

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

/// Sort: a button with the sort icon that opens the orders in a small panel under it, in the HUD
/// menu's look (playtesting 2026-10-26: "The 'Bag order' sorting button should just say 'Sort' with
/// the same leading icon. That button should open the same menu style as the hamburger menu, so no
/// native iOS dropdown menu"): the one in use in gold with a tick; a tap on one, or anywhere else,
/// closes it. Any list's orders (the Bag's and the bank's `ItemSort`, the Quests'), each named by
/// `title`. The row it sits in needs `.zIndex(1)`, so the panel lies over what's under the row.
struct SortMenu<Option: Hashable>: View {
    @Binding var sort: Option
    let options: [Option]
    let title: (Option) -> String
    /// Debug `sortopen`: out from the start.
    @State private var open = DebugLaunch.opensSort

    var body: some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { open.toggle() }
        } label: {
            HStack(spacing: 5) {
                IconImage(.sort, size: 14)
                Text(L("Sort"))
                    .lineLimit(1)
            }
            .font(HUDStyle.font(11))
            .foregroundStyle(HUDStyle.cream)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Capsule().fill(Color.white.opacity(open ? 0.2 : 0.1)))
            .fixedSize()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Sort"))
        .accessibilityValue(title(sort))
        // Anywhere else closes it: a tap catcher over the window round the button, under the panel.
        .overlay {
            if open {
                Color.clear
                    .frame(width: 4000, height: 4000)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if open {
                panel
                    .offset(y: 38)
                    .transition(.scale(scale: 0.6, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { open = false }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options, id: \.self) { row($0) }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(minWidth: 160, alignment: .leading)
        .background(HUDStyle.panelSurface(RoundedRectangle(cornerRadius: 14)))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    private func row(_ option: Option) -> some View {
        let selected = option == sort
        return Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            sort = option
            close()
        } label: {
            HStack(spacing: 8) {
                IconImage(.check, size: 14)
                    .foregroundStyle(HUDStyle.gold)
                    .opacity(selected ? 1 : 0)
                Text(title(option))
                    .font(HUDStyle.font(13))
                    .foregroundStyle(selected ? HUDStyle.gold : .white)
                    .shadow(color: HUDStyle.frameDark, radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Sort button for things you carry (the Bag, the bank, the gear for a slot): `SortMenu` with
/// `ItemSort`'s names, the bank's own order called the bank's.
struct ItemSortMenu: View {
    @Binding var sort: ItemSort
    let options: [ItemSort]
    /// In the bank: your order is the bank's.
    var bank = false

    var body: some View {
        let bank = self.bank
        SortMenu(sort: $sort, options: options, title: { bank ? $0.bankTitle : $0.title })
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

/// The slots of the Bag or one side of the bank, one grid for every kind of thing, in your order
/// (playtesting 2026-10-26: "Make sure 6 grid items fit on the same row"): six to a row on a phone
/// held upright, the slots as big as the width allows; more on a wider window. Hold a slot and it lifts (a little bigger, a shadow, a tap of the
/// Taptic Engine) and follows your finger, the others sliding aside to open the place it would land
/// in; let go and it's there (`onMove`, `GameSession.moveItem`) ("If I tap and hold the item lifts
/// up, then when I move it around the other item grid cards move aside"). A tap opens its card; a
/// swipe still scrolls the window, which holds still while a slot is lifted (`dragging`). VoiceOver
/// moves it a slot at a time.
struct ItemSlotGrid<Tile: View>: View {
    let items: [ItemDef]
    /// True while a slot is lifted: the window's scroll view holds still meanwhile.
    let dragging: Binding<Bool>?
    let label: (ItemDef) -> String
    let hint: String?
    let onTap: (ItemDef) -> Void
    /// Puts the first id where the second is.
    let onMove: (_ id: String, _ target: String) -> Void
    let tile: (_ item: ItemDef, _ size: CGFloat) -> Tile

    init(items: [ItemDef], dragging: Binding<Bool>? = nil,
         label: @escaping (ItemDef) -> String, hint: String? = nil,
         onTap: @escaping (ItemDef) -> Void, onMove: @escaping (_ id: String, _ target: String) -> Void,
         @ViewBuilder tile: @escaping (_ item: ItemDef, _ size: CGFloat) -> Tile) {
        self.items = items
        self.dragging = dragging
        self.label = label
        self.hint = hint
        self.onTap = onTap
        self.onMove = onMove
        self.tile = tile
    }

    /// The room width the grid has, measured.
    @State private var width: CGFloat = 0
    /// The slot that's lifted, where it was, and where it would land, as places in `items`.
    @State private var held: String?
    @State private var start = 0
    @State private var landing = 0
    /// How far the finger has moved it since it lifted.
    @State private var shift: CGSize = .zero
    @GestureState private var pressing = false
    /// When a lifted slot was last put down, so its touch doesn't also open it.
    @State private var putDownAt = Date.distantPast

    /// Between slots, and the most a slot grows to before another fits in the row.
    private static var spacing: CGFloat { 6 }
    private static var widest: CGFloat { 66 }
    private static var settle: Animation { .spring(response: 0.3, dampingFraction: 0.8) }
    /// The grid's own space, which the finger's moves are measured in: the slot itself moves.
    private static var space: String { "itemSlotGrid" }

    private var columns: Int {
        guard width > 0 else { return 6 }
        return max(6, Int((width + Self.spacing) / (Self.widest + Self.spacing)))
    }

    private var slot: CGFloat {
        guard width > 0 else { return 52 }
        return floor((width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// The top-left corner of a cell.
    private func corner(_ cell: Int) -> CGPoint {
        let step = slot + Self.spacing
        return CGPoint(x: CGFloat(cell % columns) * step, y: CGFloat(cell / columns) * step)
    }

    /// The items as they show: while one's lifted, the others close up round where it would land.
    private var shown: [ItemDef] {
        guard let held, let item = items.first(where: { $0.id == held }) else { return items }
        var rest = items.filter { $0.id != held }
        rest.insert(item, at: min(max(0, landing), rest.count))
        return rest
    }

    var body: some View {
        let slot = self.slot
        let cells = items.count
        let rows = max(1, (cells + columns - 1) / columns)
        let height = CGFloat(rows) * slot + CGFloat(rows - 1) * Self.spacing
        ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                cell(item, at: index, slot: slot)
            }
        }
        .frame(width: width > 0 ? width : nil, height: height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // A lift that ends without a lift's end (the window took the touch): it lands where it is.
        .onChange(of: pressing) { _, now in
            if !now { putDown() }
        }
    }

    private func cell(_ item: ItemDef, at index: Int, slot: CGFloat) -> some View {
        let isHeld = held == item.id
        let home = corner(index)
        let lifted = corner(start)
        let place = isHeld ? CGPoint(x: lifted.x + shift.width, y: lifted.y + shift.height) : home
        let position = items.firstIndex { $0.id == item.id }
        let before = position.flatMap { $0 > 0 ? items[$0 - 1] : nil }
        let after = position.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil }
        return tile(item, slot)
            .frame(width: slot, height: slot)
            .contentShape(Rectangle())
            // A tap opens it; held, it lifts. Each a gesture of its own, side by side: as the hold's
            // fallback (`exclusively(before:)`) the tap never came, in a scroll view (playtesting
            // 2026-10-26: "Clicking on items in the inventory doesn't work").
            .onTapGesture {
                // Not the touch that lifted it, nor the one that just put it down.
                guard held == nil, Date().timeIntervalSince(putDownAt) > 0.3 else { return }
                onTap(item)
            }
            .simultaneousGesture(lift(item))
            .scaleEffect(isHeld ? 1.15 : 1)
            .shadow(color: .black.opacity(isHeld ? 0.45 : 0), radius: isHeld ? 8 : 0, x: 0, y: isHeld ? 5 : 0)
            .offset(x: place.x, y: place.y)
            .zIndex(isHeld ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(item))
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap(item) }
            .accessibilityAction(named: L("Move earlier")) { if let before { onMove(item.id, before.id) } }
            .accessibilityAction(named: L("Move later")) { if let after { onMove(item.id, after.id) } }
    }

    /// Held a moment, the slot lifts; then it follows the finger.
    private func lift(_ item: ItemDef) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if held != item.id { pickUp(item) }
                shift = drag?.translation ?? .zero
                hover()
            }
            .onEnded { _ in putDown() }
    }

    private func pickUp(_ item: ItemDef) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        held = item.id
        start = index
        landing = index
        shift = .zero
        dragging?.wrappedValue = true
        Haptics.impact(.light)
    }

    /// Where the lifted slot would land: the cell its middle is over, the others sliding aside.
    private func hover() {
        guard held != nil, !items.isEmpty else { return }
        let step = slot + Self.spacing
        let lifted = corner(start)
        let middle = CGPoint(x: lifted.x + shift.width + slot / 2, y: lifted.y + shift.height + slot / 2)
        let column = min(max(Int(middle.x / step), 0), columns - 1)
        let row = max(Int(middle.y / step), 0)
        let to = min(max(row * columns + column, 0), items.count - 1)
        guard to != landing else { return }
        withAnimation(Self.settle) { landing = to }
        if GameSettings.haptics { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// Let go: it lands where it would, and the order's saved by `onMove`.
    private func putDown() {
        guard let id = held else { return }
        let from = start, to = landing
        let target = items.indices.contains(to) ? items[to].id : nil
        withAnimation(Self.settle) {
            held = nil
            shift = .zero
            if from != to, let target { onMove(id, target) }
        }
        putDownAt = Date()
        dragging?.wrappedValue = false
    }
}
