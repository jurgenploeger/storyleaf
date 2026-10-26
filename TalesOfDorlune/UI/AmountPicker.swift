import SwiftUI

/// How many, or (`coins`) how much: − and + round the amount, the amount a button that opens a keypad
/// to type it, and All (playtesting 2026-10-26: "a stepper to decide how many [...] click on the item
/// count [...] to show a numpad"). One control wherever you choose an amount: the bank's card, and in
/// the Bag dropping, trading (the price too) and using. Digits typed past `maximum` stop at it. While
/// the keypad is open (`typing`), the window hides its own buttons: the keypad has OK and Cancel.
struct AmountPicker: View {
    @Binding var amount: Int
    @Binding var typing: Bool
    /// The most it can be (at least 1).
    let maximum: Int
    /// A price: the coins by it, and no All.
    var coins = false

    /// The keypad's digits while it's open.
    @State private var digits = ""

    private var top: Int { max(1, maximum) }
    private var count: Int { min(max(1, amount), top) }
    private var typed: Int { Int(digits) ?? 0 }

    var body: some View {
        Group {
            if typing {
                keypad
            } else {
                stepper
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepper: some View {
        let count = self.count, top = self.top
        return HStack(spacing: 8) {
            // −, + and All the same size, the signs big enough to read at a glance (playtesting 2026-10-26).
            Button { amount = max(1, count - 1) } label: { Self.face(Text(verbatim: "−").font(HUDStyle.font(22))) }
                .buttonStyle(PixelButtonStyle())
                .disabled(count <= 1)
                .opacity(count <= 1 ? 0.5 : 1)
                .accessibilityLabel(coins ? L("Lower price") : L("Fewer"))
            Button {
                digits = ""
                typing = true
            } label: {
                plate(count, border: HUDStyle.plateDark, size: 17, height: 34)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(coins ? L("Price: {gold}g", ["gold": count]) : L("Amount: {count}", ["count": count]))
            .accessibilityHint(coins ? L("Type the price") : L("Type how many"))
            Button { amount = min(top, count + 1) } label: { Self.face(Text(verbatim: "+").font(HUDStyle.font(22))) }
                .buttonStyle(PixelButtonStyle())
                .disabled(count >= top)
                .opacity(count >= top ? 0.5 : 1)
                .accessibilityLabel(coins ? L("Higher price") : L("More"))
            if !coins {
                Button { amount = top } label: {
                    Self.face(Text(L("All")).lineLimit(1).minimumScaleFactor(0.6))
                }
                    .buttonStyle(PixelButtonStyle())
                    .disabled(count >= top)
                    .opacity(count >= top ? 0.5 : 1)
            }
        }
    }

    /// A stepper button's face: all three the same size.
    private static func face(_ label: some View) -> some View {
        label.frame(width: 30, height: 22)
    }

    /// The amount on a light plate, the coins by it for a price.
    private func plate(_ value: Int, border: Color, size: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 5) {
            if coins {
                IconImage(.coins, size: size)
            }
            Text(value.formatted())
                .font(HUDStyle.mono(size))
                .foregroundStyle(HUDStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(RoundedRectangle(cornerRadius: 6).fill(HUDStyle.plateLight))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 2))
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "⌫"]
        let typed = self.typed
        return VStack(spacing: 8) {
            plate(typed, border: HUDStyle.gold, size: 20, height: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(coins ? L("Price: {gold}g", ["gold": typed]) : L("Amount: {count}", ["count": typed]))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { press(key) } label: {
                        Group {
                            if key == "⌫" { IconImage(.arrowLeft, size: 15) } else { Text(key) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle())
                    .accessibilityLabel(key == "C" ? L("Clear") : key == "⌫" ? L("Delete digit") : key)
                }
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(L("Cancel")) { typing = false }
                    .buttonStyle(PixelButtonStyle())
                Button(L("OK")) {
                    amount = max(1, min(typed, top))
                    typing = false
                }
                .buttonStyle(PixelButtonStyle(tint: HUDStyle.gold))
                .disabled(typed == 0)
                .opacity(typed == 0 ? 0.5 : 1)
            }
        }
    }

    private func press(_ key: String) {
        var next = digits
        switch key {
        case "C": next = ""
        case "⌫": next = String(next.dropLast())
        default: next += key
        }
        next = String(next.drop(while: { $0 == "0" }))
        if next.count > 12 { next = String(top) }
        if let value = Int(next), value > top { next = String(top) }
        digits = next
    }
}
