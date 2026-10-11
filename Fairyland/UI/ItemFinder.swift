import SwiftUI

/// How a list of things you carry is ordered (the Bag, the gear for a slot), remembered between
/// visits. Nonisolated like the other enums shown with `ForEach(id: \.self)`.
nonisolated enum ItemSort: String, CaseIterable {
    /// As the game lists them (content/items.json): kind by kind, plainest first.
    case standard
    /// Gear by what it's worth to you (`GameSession.gearValue`), the best first; the rest as they come.
    case best
    case name, level, price, count

    var title: String {
        switch self {
        case .standard: L("Bag order")
        case .best: L("Best for you")
        case .name: L("Name")
        case .level: L("Level")
        case .price: L("Price")
        case .count: L("How many")
        }
    }
}

enum ItemFinder {
    /// `items` narrowed to those whose name (or kind, "boots") holds `search`, in `sort`'s order.
    /// Ties keep the game's own order.
    static func arrange(_ items: [ItemDef], search: String, sort: ItemSort, session: GameSession) -> [ItemDef] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = query.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(query) || $0.type.displayName.localizedStandardContains(query)
        }
        let value: (ItemDef) -> Double
        switch sort {
        case .standard: return found
        case .name: return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .best: value = { session.gearValue($0) }
        case .level: value = { Double($0.level ?? 0) }
        case .price: value = { Double($0.price) }
        case .count: value = { Double(session.count(of: $0.id)) }
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
            TextField(L("Search"), text: $text)
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

    var body: some View {
        Menu {
            Picker(L("Sort by"), selection: $sort) {
                ForEach(options, id: \.self) { Text($0.title).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                IconImage(.sort, size: 14)
                Text(sort.title)
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
        .accessibilityValue(sort.title)
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
