import SpriteKit
import UIKit

/// Special attacks land in a flare of their own light, on top of each skill's own look: a white-hot
/// bloom, a long streak of light across it like a camera's lens flare, a star of thin beams, lens
/// ghosts drifting out along the streak, a ring rolling out over the ground and sparks thrown clear.
/// The caster's hands flare as the skill leaves them. Both grow with the tier (`level` 1–5), so a
/// top-level spell lands like a small sun. Layered like ElementEffects: a deep shade alpha-blended
/// underneath, so the light still reads on bright sand and snow, then added light on top.
extension SkillEffects {
    /// A soft ring, for the lens ghosts.
    private static let ghostTexture = SoftTextures.radial(size: 64, colors: [
        UIColor(white: 1, alpha: 0.06), UIColor(white: 1, alpha: 0.1), UIColor(white: 1, alpha: 0.55), UIColor(white: 1, alpha: 0),
    ])

    /// A spark: a bright head trailing off to nothing.
    private static let sparkTexture: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 32, height: 4)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.6).cgColor, UIColor.white.cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.7, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
        return SKTexture(image: image)
    }()

    /// A special attack's light landing on `target`.
    static func impactFlare(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        let tier = CGFloat(min(5, max(1, level)))
        let point = target.center
        let z: CGFloat = 19_400
        let vivid = flareVivid(color)

        // Underneath: a deep shade, so the light shows on bright ground too.
        let under = shade(flareDeep(vivid), size: CGSize(width: 70 + 22 * tier, height: 56 + 16 * tier), alpha: 0.4)
        under.position = point
        under.zPosition = z
        under.setScale(0.4)
        parent.addChild(under)
        under.run(.sequence([.scale(to: 1, duration: 0.07), .wait(forDuration: 0.05), .fadeOut(withDuration: 0.2), .removeFromParent()]))

        flareBloom(at: point, color: vivid, size: 40 + 12 * tier, z: z + 1, in: parent)
        let length = 140 + 46 * tier
        flareStreak(at: point, color: vivid, length: length, thickness: 7 + 1.6 * tier, z: z + 4, in: parent)
        flareStar(at: point, color: vivid, beams: tier >= 3 ? 8 : 4, reach: 70 + 16 * tier, z: z + 5, in: parent)

        // Lens ghosts along the streak, drifting outward as they fade.
        let ghosts: [(offset: CGFloat, size: CGFloat)] = [(-0.42, 18), (0.28, 12), (0.55, 26)]
        for (index, ghost) in ghosts.prefix(tier >= 2 ? 3 : 2).enumerated() {
            let width = ghost.size + 3 * tier
            let sprite = SKSpriteNode(texture: ghostTexture, size: CGSize(width: width, height: width))
            sprite.color = index == 1 ? flareBright(vivid) : vivid
            sprite.colorBlendFactor = 1
            sprite.blendMode = .add
            sprite.position = point + CGVector(dx: ghost.offset * length, dy: ghost.offset * 10)
            sprite.zPosition = z + 3
            sprite.alpha = 0
            parent.addChild(sprite)
            sprite.run(.sequence([
                .wait(forDuration: 0.05),
                .fadeAlpha(to: 0.55, duration: 0.08),
                .group([.moveBy(x: ghost.offset * 30, y: ghost.offset * 4, duration: 0.5), .fadeOut(withDuration: 0.5)]),
                .removeFromParent(),
            ]))
        }

        // A ring rolling out over the ground under the target.
        ring(at: target.position, color: vivid, size: CGSize(width: 44, height: 16), grow: 2 + 0.5 * tier, in: parent)

        // Sparks thrown clear.
        for _ in 0..<Int(6 + 3 * tier) {
            let spark = SKSpriteNode(texture: sparkTexture, size: CGSize(width: CGFloat.random(in: 14...24) + 2 * tier, height: 2.5))
            spark.color = Bool.random() ? .white : flareBright(vivid)
            spark.colorBlendFactor = 1
            spark.blendMode = .add
            spark.anchorPoint = CGPoint(x: 1, y: 0.5)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            spark.zRotation = angle
            spark.position = point
            spark.zPosition = z + 6
            parent.addChild(spark)
            let reach = CGFloat.random(in: 40...80) + 14 * tier
            let fly = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach * 0.8, duration: 0.38)
            fly.timingMode = .easeOut
            spark.run(.sequence([
                .group([fly, .scaleX(to: 0.4, duration: 0.4), .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.2)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// The skill leaving the caster's hands: a bloom, a short streak and a four-point star.
    static func castFlare(on caster: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        let tier = CGFloat(min(5, max(1, level)))
        let point = caster.center + CGVector(dx: 0, dy: 6)
        let vivid = flareVivid(color)
        let z: CGFloat = 19_300
        flareBloom(at: point, color: vivid, size: 40 + 10 * tier, z: z, in: parent)
        flareStreak(at: point, color: vivid, length: 70 + 24 * tier, thickness: 5 + tier, z: z + 3, in: parent)
        flareStar(at: point, color: vivid, beams: 4, reach: 40 + 10 * tier, z: z + 4, in: parent)
    }

    // MARK: - Parts

    /// A bloom of light: the colour, a brighter heart and a small white-hot core, popping open and
    /// burning out within a third of a second, so whoever it lands on shows again while the streak,
    /// the star and the sparks play out.
    private static func flareBloom(at point: CGPoint, color: UIColor, size: CGFloat, z: CGFloat, in parent: SKNode) {
        let layers: [(tone: UIColor, scale: CGFloat, alpha: CGFloat)] = [(color, 1, 0.7), (flareBright(color), 0.5, 0.6), (.white, 0.18, 0.85)]
        for (index, layer) in layers.enumerated() {
            let width = size * layer.scale
            let glow = glowSprite(layer.tone, size: CGSize(width: width, height: width))
            glow.position = point
            glow.zPosition = z + CGFloat(index) * 0.1
            glow.alpha = layer.alpha
            glow.setScale(0.2)
            parent.addChild(glow)
            let pop = SKAction.scale(to: 1, duration: 0.07)
            pop.timingMode = .easeOut
            glow.run(.sequence([pop, .group([.scale(to: 1.15, duration: 0.24), .fadeOut(withDuration: 0.24)]), .removeFromParent()]))
        }
    }

    /// A long thin line of light across a point, white along its middle, opening out sideways and
    /// thinning as it fades: a lens flare's streak.
    private static func flareStreak(at point: CGPoint, color: UIColor, length: CGFloat, thickness: CGFloat, z: CGFloat, in parent: SKNode) {
        let layers: [(tone: UIColor, height: CGFloat, alpha: CGFloat)] = [(color, thickness, 0.85), (.white, thickness * 0.35, 1)]
        for (index, layer) in layers.enumerated() {
            let streak = glowSprite(layer.tone, size: CGSize(width: length, height: layer.height))
            streak.position = point
            streak.zPosition = z + CGFloat(index) * 0.1
            streak.alpha = layer.alpha
            streak.xScale = 0.1
            parent.addChild(streak)
            let open = SKAction.scaleX(to: 1, duration: 0.12)
            open.timingMode = .easeOut
            streak.run(.sequence([
                open,
                .group([.scaleX(to: 1.25, duration: 0.45), .scaleY(to: 0.3, duration: 0.45), .fadeOut(withDuration: 0.45)]),
                .removeFromParent(),
            ]))
        }
    }

    /// A star of thin beams through a point (long ones upright and level, shorter ones between),
    /// turning a little as it fades.
    private static func flareStar(at point: CGPoint, color: UIColor, beams: Int, reach: CGFloat, z: CGFloat, in parent: SKNode) {
        let star = SKNode()
        star.position = point
        star.zPosition = z
        star.setScale(0.3)
        parent.addChild(star)
        for index in 0..<beams {
            let long = index % 2 == 0
            let beam = glowSprite(long ? .white : flareBright(color), size: CGSize(width: long ? reach : reach * 0.6, height: long ? 3.5 : 2.5))
            beam.zPosition = 0
            beam.zRotation = CGFloat(index) * .pi / CGFloat(beams)
            star.addChild(beam)
        }
        star.run(.sequence([
            .group([
                .sequence([.scale(to: 1, duration: 0.1), .scale(to: 1.2, duration: 0.45)]),
                .rotate(byAngle: 0.4, duration: 0.55),
                .sequence([.wait(forDuration: 0.18), .fadeOut(withDuration: 0.37)]),
            ]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Colours

    /// A skill's colour at full strength: flares need it vivid even when the colour is pale. A colourless
    /// skill (white) flares in warm light.
    private static func flareVivid(_ color: UIColor) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha), saturation >= 0.12 else {
            return UIColor(red: 1, green: 0.93, blue: 0.7, alpha: 1)
        }
        return UIColor(hue: hue, saturation: min(1, max(saturation, 0.55)), brightness: max(brightness, 0.9), alpha: 1)
    }

    /// Halfway to white: a flare's brighter heart.
    private static func flareBright(_ color: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return color }
        return UIColor(red: (red + 1) / 2, green: (green + 1) / 2, blue: (blue + 1) / 2, alpha: 1)
    }

    /// The same hue, dark and strong: the shade under a flare.
    private static func flareDeep(_ color: UIColor) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return color }
        return UIColor(hue: hue, saturation: min(1, saturation + 0.2), brightness: 0.5, alpha: 1)
    }
}
