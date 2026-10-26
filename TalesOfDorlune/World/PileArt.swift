import SpriteKit
import UIKit

/// What a pile on the ground (`LostPile`: what you dropped, or lost when you fell) looks like: the
/// things in it themselves, very small, in a little heap (playtesting 2026-10-25: "Items that are
/// dropped on the map should look like those items, just very small"). Up to five kinds show, the
/// one there's most of in front, the coins among them; it sits on the ground as anyone does (a
/// `Walker`, its own picture hidden), with its shadow and "Your things" over it.
enum PileArt {
    /// How big each thing shows, in points (a person stands about 48 tall).
    static let size: CGFloat = 14
    /// Where each sits in the heap, the first in front: a little apart and a little back.
    private static let spots: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: -9, y: 4), CGPoint(x: 9, y: 3), CGPoint(x: -3, y: 9), CGPoint(x: 6, y: 11),
    ]

    static func node(for pile: LostPile) -> Walker {
        let library = ArtLibrary.shared
        let walker = Walker(cycle: library.walkCycle("lost_pile"), label: L("Your things"))
        walker.sprite.isHidden = true
        walker.idles = false
        for (index, id) in arts(in: pile).enumerated() {
            // A texture of its own, smoothed: shrunk to a few points, pixel art drawn nearest-pixel
            // came out ragged (the item's shared texture keeps its own filtering).
            guard let image = library.artImage(id) else { continue }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            let icon = SKSpriteNode(texture: texture, size: CGSize(width: size, height: size))
            icon.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            icon.position = spots[index]
            icon.zPosition = -CGFloat(index) * 0.01
            if let light = Walker.light {
                icon.color = light.color
                icon.colorBlendFactor = light.strength
            }
            walker.addChild(icon)
        }
        return walker
    }

    /// What shows of a pile, so a pile that changed (more dropped on it, some picked up) is drawn anew.
    static func look(of pile: LostPile) -> [String] { arts(in: pile) }

    /// The pictures of what's in it: the kinds there's most of first, then the coins, five at most.
    private static func arts(in pile: LostPile) -> [String] {
        let kinds = pile.items.filter { $0.value > 0 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .compactMap { Content.shared.item($0.key)?.art }
        let coins = pile.gold > 0 ? [CoinsTile.art(for: pile.gold)] : []
        return Array((kinds.prefix(spots.count - coins.count) + coins))
    }
}
