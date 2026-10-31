import SwiftUI

/// Dyeing armour at Orla the Weaver's or a barber's (Dyes.swift, `GameSession.dye`), in a window over
/// the dialog: pick one piece (what you wear, or one from the bag), its main colour or its trim (Main |
/// Trim, for a piece that `takesTrim`), and a dye you carry, see what the piece becomes, and Dye it
/// uses up one dye on that piece alone. A dyed piece washes out to what it was, free: all of it, or
/// its trim alone.
struct DyeWindow: View {
    let session: GameSession
    /// Closes the window, with what the dyer says when something was dyed or washed out.
    let onClose: (String?) -> Void

    @State private var piece: GameSession.DyePiece?
    @State private var dyeID: String?
    /// Dyeing the piece's trim rather than its main colour.
    @State private var trimming = DebugLaunch.dyesTrim

    private static let tiles = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 8)]

    var body: some View {
        let pieces = session.dyeablePieces
        let dyes = session.dyesCarried
        let chosen = piece.flatMap { pieces.contains($0) ? $0 : nil }
        let item = chosen.flatMap { session.content.item($0.itemID) }
        let dye = dyeID.flatMap { id in dyes.first { $0.id == id } }
        let trim = trimming && item?.takesTrim == true
        let result = item.flatMap { item in
            dye.flatMap { session.content.item(ItemDef.dyedID(item.baseID, with: trim ? item.dyeID : $0.id, trim: trim ? $0.id : item.trimDyeID)) }
        }
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose(nil) }
            VStack(spacing: 0) {
                WindowTitle(L("Dye gear"), onClose: { onClose(nil) })
                // Scrolls only when it can't all fit (a phone on its side).
                FitOrScroll {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Pick a piece, its main colour or its trim, then a dye. One dye colours one piece, and washing it out is free."))
                            .font(HUDStyle.font(11))
                            .foregroundStyle(HUDStyle.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        if pieces.isEmpty {
                            Text(L("You have no weapon, armour, hat, gloves or boots to dye."))
                                .font(HUDStyle.font(12))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            let worn = pieces.filter(\.worn)
                            let carried = pieces.filter { !$0.worn }
                            if !worn.isEmpty { pieceGrid(L("You wear"), worn, chosen: chosen) }
                            if !carried.isEmpty { pieceGrid(L("In your bag"), carried, chosen: chosen) }
                        }
                        if item?.takesTrim == true {
                            parts(trim)
                        }
                        Text(L("Dye")).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
                        if dyes.isEmpty {
                            Text(L("You have no dye. Mix one in your Bag from a gem and a Sheepskin."))
                                .font(HUDStyle.font(12))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            LazyVGrid(columns: Self.tiles, alignment: .leading, spacing: 8) {
                                ForEach(dyes) { each in
                                    tile(each, count: session.count(of: each.id), selected: each.id == dye?.id) { dyeID = each.id }
                                }
                            }
                        }
                        if let item {
                            outcome(item, result: result)
                        }
                        HStack(spacing: 10) {
                            if let item, item.isDyed, let chosen {
                                Button(L("Wash out")) {
                                    guard let plain = session.washOut(chosen) else { return }
                                    SoundEffects.shared.play(.equip)
                                    session.save()
                                    onClose(L("All washed out: your {item} is as it was.", ["item": plain.name]))
                                }
                                .buttonStyle(PixelButtonStyle(compact: true))
                                // Its trim alone, when it has a main colour to keep.
                                if item.dyeID != nil, item.trimDyeID != nil {
                                    Button(L("Wash out trim")) {
                                        guard let washed = session.washOut(chosen, trimOnly: true) else { return }
                                        SoundEffects.shared.play(.equip)
                                        session.save()
                                        onClose(L("The trim's washed out: your {item}.", ["item": washed.name]))
                                    }
                                    .buttonStyle(PixelButtonStyle(compact: true))
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                guard let chosen, let dye, let dyed = session.dye(chosen, with: dye.id, trim: trim) else { return }
                                SoundEffects.shared.play(.equip)
                                session.save()
                                onClose(L("There: your {item}.", ["item": dyed.name]))
                            } label: {
                                Label(L("Dye it"), icon: .palette)
                            }
                            .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                            .disabled(result == nil || result?.id == item?.id)
                            .opacity(result == nil || result?.id == item?.id ? 0.5 : 1)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 360)
            .fitHeight()
            .gameWindow()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { onClose(nil) }
            .padding(24)
            .popIn()
            .onAppear {
                // A screenshot of the trim (`dyeing=trim`) opens on the first piece, its Main | Trim showing.
                if trimming, piece == nil { piece = session.dyeablePieces.first }
            }
        }
        .foregroundStyle(HUDStyle.cream)
    }

    /// Main | Trim: which of the piece's colours the dye goes on (its trim: a sash, a hem, clasps, a
    /// hilt or a haft).
    private func parts(_ trim: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach([false, true], id: \.self) { each in
                Button(each ? L("Trim") : L("Main")) { trimming = each }
                    .buttonStyle(PixelButtonStyle(tint: each == trim ? HUDStyle.gold : HUDStyle.dim, compact: true))
                    .accessibilityAddTraits(each == trim ? .isSelected : [])
            }
        }
    }

    /// Pieces under a heading, each a tile to pick.
    private func pieceGrid(_ title: String, _ pieces: [GameSession.DyePiece], chosen: GameSession.DyePiece?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(HUDStyle.font(11)).foregroundStyle(HUDStyle.gold)
            LazyVGrid(columns: Self.tiles, alignment: .leading, spacing: 8) {
                ForEach(pieces) { each in
                    if let item = session.content.item(each.itemID) {
                        tile(item, count: each.worn ? 1 : session.count(of: each.itemID), selected: each == chosen) { piece = each }
                    }
                }
            }
        }
    }

    /// An item to pick, ringed in gold once picked.
    private func tile(_ item: ItemDef, count: Int, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            SoundEffects.shared.play(.tap, volume: 0.7)
            pick()
        } label: {
            ItemIcon(item: item, size: 40, count: count)
                .padding(2)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(HUDStyle.gold, lineWidth: selected ? 2.5 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The piece picked, and what the dye picked makes of it.
    private func outcome(_ item: ItemDef, result: ItemDef?) -> some View {
        HStack(spacing: 8) {
            ItemIcon(item: item, size: 36)
            if let result, result.id != item.id {
                IconImage(.arrowRight, size: 14).foregroundStyle(HUDStyle.gold)
                ItemIcon(item: result, size: 36)
            }
            Text(result?.name ?? item.name)
                .font(HUDStyle.font(12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
