import SpriteKit
import UIKit

/// A dark map (a cave: `ambience.darkness` in content/maps.json). You carry a light: around you a
/// circle of it, and beyond its edge everything sinks into the dark, so you see only as far as it
/// reaches. It breathes a little, like a flame, and lays a soft glow on the ground round you.
/// Glowing crystals and moss still shine faintly through the dark. It rides with the hero, over
/// the map and everyone on it, and into a fight's backdrop (`WorldScene.battleBackdrop`).
final class Lantern {
    /// How far the light reaches, in points; the minimap shows what's fallen inside it.
    let radius: CGFloat
    private let veil = SKNode()
    private let glints = SKNode()

    init(_ def: MapDef.Ambience.Darkness, in world: SKNode) {
        radius = CGFloat(def.radius ?? 190)
        let shade = def.color.flatMap { UIColor(hex: $0) } ?? UIColor(red: 0.01, green: 0.016, blue: 0.04, alpha: 1)
        let depth = CGFloat(def.alpha ?? 0.9)
        veil.zPosition = 41_000
        world.addChild(veil)

        let hole = SKSpriteNode(texture: Self.hole, size: CGSize(width: radius * 2, height: radius * 2))
        hole.color = shade
        hole.colorBlendFactor = 1
        hole.alpha = depth
        veil.addChild(hole)
        // Plain dark round the hole, out past the edges of any screen. The pieces meet edge to
        // edge, so nowhere is darkened twice.
        let far: CGFloat = 3_000
        let sides = [
            CGRect(x: -far, y: -far, width: far - radius, height: far * 2),
            CGRect(x: radius, y: -far, width: far - radius, height: far * 2),
            CGRect(x: -radius, y: radius, width: radius * 2, height: far - radius),
            CGRect(x: -radius, y: -far, width: radius * 2, height: far - radius),
        ]
        for rect in sides {
            let side = SKSpriteNode(color: shade, size: rect.size)
            side.anchorPoint = .zero
            side.position = rect.origin
            side.alpha = depth
            veil.addChild(side)
        }
        if let color = def.light.flatMap({ UIColor(hex: $0) }) {
            let glow = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: radius * 1.6, height: radius * 1.1))
            glow.color = color
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0.14
            glow.zPosition = -1
            veil.addChild(glow)
        }
        // The flame's breath: the circle swells and shrinks a little, never quite in rhythm.
        var breaths: [SKAction] = []
        for _ in 0..<7 {
            let breath = SKAction.scale(to: .random(in: 0.96...1.04), duration: .random(in: 0.3...0.7))
            breath.timingMode = .easeInEaseOut
            breaths.append(breath)
        }
        veil.run(.repeatForever(.sequence(breaths)))

        glints.zPosition = 41_500
        world.addChild(glints)
    }

    /// Keeps the light on the hero.
    func follow(_ point: CGPoint) {
        veil.position = point
    }

    /// A glowing prop's light, shining faintly through the dark (and a little brighter in yours).
    func glint(at point: CGPoint, color: UIColor, width: CGFloat) {
        let glint = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: width, height: width * 0.8))
        glint.color = color
        glint.colorBlendFactor = 1
        glint.blendMode = .add
        glint.position = point
        let alpha = CGFloat.random(in: 0.18...0.3)
        glint.alpha = alpha
        let duration = Double.random(in: 1.4...2.6)
        glint.run(.repeatForever(.sequence([.fadeAlpha(to: alpha * 0.5, duration: duration), .fadeAlpha(to: alpha, duration: duration)])))
        glints.addChild(glint)
    }

    /// Clear in the middle, easing into the dark toward the edge, and dark in the corners.
    private static let hole: SKTexture = SoftTextures.radial(size: 256, colors: [
        UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.06),
        UIColor(white: 1, alpha: 0.3), UIColor(white: 1, alpha: 0.65), UIColor(white: 1, alpha: 0.9), .white,
    ])
}
