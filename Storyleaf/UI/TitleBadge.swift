import SwiftUI
import UIKit

/// A title worn over your name as a badge of honour: a little metal pill with a darker rim and a
/// bevelled edge, its metal set by the title's `rank` (content/titles.json): bronze, silver, gold,
/// ruby, and for the rarest a prismatic one with a star either side and a slow shine across it.
struct TitleBadge: View {
    let title: TitleDef
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shining = false

    private struct Metal {
        let fill: [Color]
        let rim: Color
        let text: Color
        /// The text's 1-point drop shadow, for legibility on the metal.
        let shadow: Color
    }

    private static func metal(_ tier: Int) -> Metal {
        switch tier {
        case 1: Metal(fill: [hex(0xF2B98A), hex(0xC97A3E), hex(0x9C5526)], rim: hex(0x5E3214), text: hex(0xFFF2E0), shadow: hex(0x5E3214))
        case 2: Metal(fill: [hex(0xFFFFFF), hex(0xD5DCE6), hex(0xA3AEBE)], rim: hex(0x4E5869), text: hex(0x26303F), shadow: .white.opacity(0.7))
        case 3: Metal(fill: [hex(0xFFF3A6), hex(0xF5C842), hex(0xD4961C)], rim: hex(0x7A4E08), text: hex(0x3D2604), shadow: hex(0xFFF6C8).opacity(0.8))
        case 4: Metal(fill: [hex(0xFF9DB4), hex(0xE0325A), hex(0xA3163A)], rim: hex(0x5C0A20), text: .white, shadow: hex(0x5C0A20))
        default: Metal(fill: [hex(0xE24BB4), hex(0x8A5CF0), hex(0x2FA7E8), hex(0x2DBF8A), hex(0xE8A92A)],
                       rim: hex(0x6A3FB0), text: .white, shadow: hex(0x3A1F6E))
        }
    }

    var body: some View {
        let tier = title.tier
        let metal = Self.metal(tier)
        let legendary = tier >= 5
        HStack(spacing: size * 0.3) {
            if legendary { IconImage(.star, size: size * 0.8) }
            Text(title.name)
                .font(HUDStyle.font(size))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if legendary { IconImage(.star, size: size * 0.8) }
        }
        .foregroundStyle(metal.text)
        .shadow(color: metal.shadow, radius: 0, x: 0, y: 1)
        .padding(.horizontal, size * 0.85)
        .padding(.vertical, size * 0.38)
        .background {
            ZStack {
                // The prismatic one runs across, the metals top to bottom.
                Capsule().fill(LinearGradient(colors: metal.fill,
                                              startPoint: legendary ? .leading : .top,
                                              endPoint: legendary ? .trailing : .bottom))
                // A gloss along the top, like the game's buttons.
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(height: size * 0.55)
                    .padding(.horizontal, size * 0.5)
                    .padding(.top, size * 0.15)
                    .frame(maxHeight: .infinity, alignment: .top)
                if legendary && !reduceMotion {
                    // A slow band of light sweeping across.
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.35)
                            .offset(x: shining ? proxy.size.width * 1.1 : -proxy.size.width * 0.45)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .overlay(Capsule().strokeBorder(metal.rim, lineWidth: 1.5))
        // The bevelled edge under it.
        .background(Capsule().fill(metal.rim).offset(y: 2))
        .onAppear {
            guard legendary, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).delay(0.6).repeatForever(autoreverses: false)) { shining = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Title: {title}", ["title": title.name]))
    }

    /// The title's colour over a name on the map, where there's no room for a badge.
    static func mapColor(rank: Int) -> UIColor {
        switch rank {
        case 1: UIColor(red: 0.95, green: 0.68, blue: 0.45, alpha: 1)
        case 2: UIColor(red: 0.86, green: 0.9, blue: 0.96, alpha: 1)
        case 3: UIColor(red: 1, green: 0.83, blue: 0.3, alpha: 1)
        case 4: UIColor(red: 1, green: 0.45, blue: 0.58, alpha: 1)
        default: UIColor(red: 0.8, green: 0.66, blue: 1, alpha: 1)
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
