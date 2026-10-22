import SpriteKit
import UIKit

/// The elemental spells, drawn in light and colour like the rest of the battle's effects: rock
/// spikes of amber light bursting out of glowing ground, a blazing fireball that blooms into a
/// blast, a cyclone of green light, an orb of water that splashes into a crown of droplets.
/// Every glow is layered: a soft disc of the element's deep shade, alpha-blended so it tints the
/// ground under it even on bright sand (added light alone washes out to white there), then its
/// own colour, a brighter heart and a white-hot core added as light on top. They grow in the same
/// five tiers as the rest of SkillEffects.
extension SkillEffects {
    /// Art from art/sprites/fx_*.png (tools/fx_art.py): the poison and curse marks and the
    /// poison's bubbles. The spells themselves are light, below.
    static func fxTexture(_ name: String) -> SKTexture? {
        ArtLibrary.shared.generatedTexture("fx_\(name)")
    }

    /// An element's light, from the deep shade that tints the ground to the white-hot core.
    struct ElementLight {
        let deep: UIColor
        let main: UIColor
        let bright: UIColor
        let core: UIColor

        static let fire = ElementLight(deep: rgb(0.98, 0.30, 0.04), main: rgb(1, 0.50, 0.12), bright: rgb(1, 0.80, 0.40), core: rgb(1, 0.96, 0.80))
        static let water = ElementLight(deep: rgb(0.05, 0.38, 0.95), main: rgb(0.30, 0.62, 1), bright: rgb(0.60, 0.85, 1), core: rgb(0.90, 0.98, 1))
        static let wood = ElementLight(deep: rgb(0.10, 0.60, 0.12), main: rgb(0.40, 0.88, 0.28), bright: rgb(0.72, 1, 0.50), core: rgb(0.92, 1, 0.80))
        /// Earth's brown can't shine, so its light is ochre over a strong brown tint, with a dim core
        /// (a bright one turned it gold, like Light's).
        static let earth = ElementLight(deep: rgb(0.50, 0.28, 0.06), main: rgb(0.80, 0.50, 0.18), bright: rgb(0.95, 0.70, 0.35), core: rgb(1, 0.88, 0.62))

        private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: 1)
        }
    }

    // MARK: - Light

    /// A soft disc of `color`, alpha-blended: it tints whatever's under it, bright ground too.
    static func shade(_ color: UIColor, size: CGSize, alpha: CGFloat) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: SoftTextures.glow, size: size)
        sprite.color = color
        sprite.colorBlendFactor = 1
        sprite.blendMode = .alpha
        sprite.alpha = alpha
        return sprite
    }

    /// A ball of an element's light `size` across: its deep shade under its colour, a brighter heart
    /// and (with `core`) a white-hot middle. Scale and fade the node to animate it all.
    static func lightBall(_ light: ElementLight, size: CGFloat, tint: CGFloat = 0.55, core: Bool = true) -> SKNode {
        let node = SKNode()
        node.zPosition = 18_000
        node.addChild(shade(light.deep, size: CGSize(width: size * 1.25, height: size * 1.25), alpha: tint))
        var layers: [(UIColor, CGFloat, CGFloat)] = [(light.main, 1, 0.9), (light.bright, 0.6, 0.9)]
        if core { layers.append((light.core, 0.28, 1)) }
        for (index, layer) in layers.enumerated() {
            let glow = glowSprite(layer.0, size: CGSize(width: size * layer.1, height: size * layer.1))
            glow.zPosition = 0.1 * CGFloat(index + 1)
            glow.alpha = layer.2
            node.addChild(glow)
        }
        return node
    }

    /// A stroke of light `size` (long and thin), tinted underneath like a ball of light.
    static func streak(_ light: ElementLight, color: UIColor? = nil, size: CGSize, tint: CGFloat = 0.5) -> SKNode {
        let node = SKNode()
        node.zPosition = 18_000
        node.addChild(shade(light.deep, size: size * 1.15, alpha: tint))
        let glow = glowSprite(color ?? light.bright, size: size)
        glow.zPosition = 0.1
        node.addChild(glow)
        return node
    }

    /// A ring of light rolling out over the ground from `point`.
    static func ring(at point: CGPoint, color: UIColor, size: CGSize, grow: CGFloat, delay: TimeInterval = 0, in parent: SKNode) {
        let band = SKShapeNode(ellipseOf: size)
        band.strokeColor = color
        band.lineWidth = 3
        band.glowWidth = 4
        band.blendMode = .add
        band.position = point
        band.zPosition = 18_000
        band.alpha = 0
        parent.addChild(band)
        let spread = SKAction.scale(to: grow, duration: 0.42)
        spread.timingMode = .easeOut
        band.run(.sequence([
            .wait(forDuration: delay),
            .fadeIn(withDuration: 0.03),
            .group([spread, .sequence([.wait(forDuration: 0.12), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent(),
        ]))
    }

    /// The ground under a spell glowing in its light, flat and wide, under every fighter.
    static func groundGlow(at point: CGPoint, light: ElementLight, width: CGFloat, appear: TimeInterval = 0,
                                   hold: TimeInterval, in parent: SKNode) {
        let pool = SKNode()
        pool.position = point
        pool.zPosition = -8_600
        pool.alpha = 0
        pool.addChild(shade(light.deep, size: CGSize(width: width * 1.2, height: width * 0.38), alpha: 0.55))
        let glow = glowSprite(light.main, size: CGSize(width: width, height: width * 0.3))
        glow.zPosition = 0.1
        glow.alpha = 0.6
        pool.addChild(glow)
        parent.addChild(pool)
        pool.run(.sequence([.wait(forDuration: appear), .fadeIn(withDuration: 0.08), .wait(forDuration: hold),
                            .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    /// Sparks of light streaking out from `point`, each stretched along its way.
    static func sparks(from point: CGPoint, light: ElementLight, count: Int, reach: CGFloat, delay: TimeInterval = 0,
                               in parent: SKNode) {
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + .random(in: -0.2...0.2)
            let direction = CGVector(dx: cos(angle), dy: sin(angle) * 0.7)
            let spark = glowSprite(index % 3 == 0 ? light.core : light.bright, size: CGSize(width: 16, height: 4.5))
            spark.position = point
            spark.zRotation = atan2(direction.dy, direction.dx)
            spark.alpha = 0
            parent.addChild(spark)
            let distance = reach * .random(in: 0.6...1)
            let fly = SKAction.moveBy(x: direction.dx * distance, y: direction.dy * distance, duration: 0.38)
            fly.timingMode = .easeOut
            spark.run(.sequence([
                .wait(forDuration: delay),
                .fadeIn(withDuration: 0.02),
                .group([fly, .scaleX(to: 0.3, duration: 0.38), .sequence([.wait(forDuration: 0.12), .fadeOut(withDuration: 0.26)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// Light streaming back from something in flight (a fireball, an orb): sparks in its colours
    /// over a tint of its deep shade, so the trail keeps its colour. `falling`: they drip down.
    static func trail(_ light: ElementLight, level: Int, falling: Bool = false, parent: SKNode) -> SKNode {
        let node = SKNode()
        for tinted in [true, false] {
            let emitter = SKEmitterNode()
            emitter.particleTexture = SoftTextures.glow
            emitter.particleBirthRate = 100 + CGFloat(level) * 20
            emitter.particleLifetime = 0.4
            emitter.particleLifetimeRange = 0.15
            emitter.particleSpeed = 25
            emitter.particleSpeedRange = 15
            emitter.emissionAngleRange = .pi * 2
            emitter.particlePositionRange = CGVector(dx: 6, dy: 6)
            emitter.particleScale = (falling ? 0.3 : 0.55) + CGFloat(level) * 0.07
            emitter.particleScaleRange = 0.15
            emitter.particleScaleSpeed = -0.9
            emitter.particleColorBlendFactor = 1
            if falling { emitter.yAcceleration = -260 }
            if tinted {
                emitter.particleColor = light.deep
                emitter.particleBlendMode = .alpha
                emitter.particleAlpha = 0.45
                emitter.particleAlphaSpeed = -1.1
                emitter.zPosition = -0.2
            } else {
                emitter.particleColorSequence = SKKeyframeSequence(keyframeValues: [light.bright, light.main, light.deep], times: [0, 0.4, 1])
                emitter.particleBlendMode = .add
                emitter.particleAlpha = 0.95
                emitter.particleAlphaSpeed = -2.2
                emitter.zPosition = -0.1
            }
            emitter.targetNode = parent
            node.addChild(emitter)
        }
        return node
    }

    /// Stops a trail and lets its last sparks die out where they are.
    static func settle(_ trail: SKNode, in parent: SKNode) {
        for case let emitter as SKEmitterNode in trail.children { emitter.particleBirthRate = 0 }
        trail.move(toParent: parent)
        trail.zPosition = 18_100
        trail.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
    }

    /// Light rising from a fighter's feet and dying out as it goes (flames, a cyclone's lift).
    static func rising(from target: BattleActor, light: ElementLight, count: Int, height: CGFloat, in parent: SKNode) {
        for index in 0..<count {
            let size = CGFloat.random(in: 20...28)
            let flame = SKNode()
            flame.zPosition = 18_000
            flame.addChild(shade(light.deep, size: CGSize(width: size, height: size * 1.3), alpha: 0.35))
            let glow = glowSprite(index % 2 == 0 ? light.main : light.bright, size: CGSize(width: size * 0.9, height: size * 1.2))
            glow.zPosition = 0.1
            flame.addChild(glow)
            flame.position = target.position + CGVector(dx: .random(in: -18...18), dy: .random(in: -4...6))
            flame.alpha = 0
            parent.addChild(flame)
            let lift = SKAction.moveBy(x: .random(in: -8...8), y: height * .random(in: 0.7...1), duration: 0.5)
            lift.timingMode = .easeOut
            flame.run(.sequence([
                .wait(forDuration: 0.04 + Double(index) * 0.035),
                .fadeIn(withDuration: 0.05),
                .group([lift, .scale(to: 0.35, duration: 0.5), .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.3)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// A column of light roaring up through a fighter.
    static func column(on target: BattleActor, light: ElementLight, width: CGFloat, in parent: SKNode) {
        let pillar = SKNode()
        pillar.position = target.position
        pillar.zPosition = 18_050
        let back = shade(light.deep, size: CGSize(width: width * 1.3, height: 190), alpha: 0.5)
        back.anchorPoint = CGPoint(x: 0.5, y: 0.04)
        pillar.addChild(back)
        for (index, (color, scale)) in [(light.main, CGFloat(1)), (light.bright, 0.5)].enumerated() {
            let glow = glowSprite(color, size: CGSize(width: width * scale, height: 180))
            glow.anchorPoint = CGPoint(x: 0.5, y: 0.04)
            glow.zPosition = 0.1 * CGFloat(index + 1)
            pillar.addChild(glow)
        }
        pillar.yScale = 0.05
        parent.addChild(pillar)
        let rise = SKAction.scaleY(to: 1, duration: 0.15)
        rise.timingMode = .easeOut
        pillar.run(.sequence([.wait(forDuration: 0.06), rise, .wait(forDuration: 0.15),
                              .group([.scaleX(to: 0.4, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
    }

    // MARK: - Stone

    /// Where the spikes stand round the target's feet: `dy` above zero is behind it. They flank
    /// the target (one in the middle would hide behind it), the tall ones behind poking up over
    /// its head. Each tier adds more; at the top tier a giant spike rises behind the target in
    /// place of the tall one, and a short one bursts up right under its feet from tier 4.
    private struct SpikeSpot {
        let kind: SpikeKind
        let dx: CGFloat
        let dy: CGFloat
        let scale: CGFloat
        let tiers: ClosedRange<Int>
    }

    /// How wide and tall a shard of light stands (points) at the usual scale.
    private enum SpikeKind {
        case tall, mid, low, thin

        var size: CGSize {
            switch self {
            case .tall: CGSize(width: 22, height: 64)
            case .mid: CGSize(width: 18, height: 46)
            case .low: CGSize(width: 18, height: 30)
            case .thin: CGSize(width: 11, height: 42)
            }
        }
    }

    private static let spikeSpots: [SpikeSpot] = [
        SpikeSpot(kind: .tall, dx: -20, dy: 8, scale: 1, tiers: 1...4),
        SpikeSpot(kind: .tall, dx: -6, dy: 12, scale: 1.5, tiers: 5...5),
        SpikeSpot(kind: .low, dx: -36, dy: -5, scale: 1, tiers: 1...5),
        SpikeSpot(kind: .mid, dx: 32, dy: 5, scale: 1, tiers: 1...5),
        SpikeSpot(kind: .low, dx: 30, dy: -9, scale: 1, tiers: 1...5),
        SpikeSpot(kind: .thin, dx: -50, dy: 3, scale: 1, tiers: 2...5),
        SpikeSpot(kind: .thin, dx: 50, dy: 1, scale: 1, tiers: 3...5),
        SpikeSpot(kind: .mid, dx: -38, dy: 11, scale: 1, tiers: 4...5),
        SpikeSpot(kind: .low, dx: -4, dy: -18, scale: 1, tiers: 4...5),
        SpikeSpot(kind: .thin, dx: 16, dy: 14, scale: 1, tiers: 5...5),
    ]

    /// A shard of light pointing up, in white to colour: nested triangles from wide and faint to
    /// narrow and bright, so it glows from a bright spine. Its foot is the bottom edge.
    static let shardTexture: SKTexture = {
        let size = CGSize(width: 48, height: 96)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let canvas = context.cgContext
            for (width, alpha) in [(CGFloat(1), CGFloat(0.25)), (0.7, 0.3), (0.42, 0.45), (0.18, 1)] {
                let half = size.width * width / 2
                canvas.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                canvas.beginPath()
                canvas.move(to: CGPoint(x: size.width / 2 - half, y: size.height))
                canvas.addLine(to: CGPoint(x: size.width / 2 + half, y: size.height))
                canvas.addLine(to: CGPoint(x: size.width / 2, y: 0))
                canvas.closePath()
                canvas.fillPath()
            }
        }
        return SKTexture(image: image)
    }()

    /// One shard of an element's light standing at its foot (the node's origin): its deep shade
    /// a little wider underneath, its colour, and a bright spine.
    static func shard(_ light: ElementLight, size: CGSize) -> SKNode {
        let node = SKNode()
        let layers: [(UIColor, CGFloat, CGFloat, CGFloat, SKBlendMode)] = [
            (light.deep, 1.25, 1.05, 0.8, .alpha), (light.main, 1, 1, 0.85, .add), (light.core, 0.55, 0.9, 0.5, .add),
        ]
        for (index, layer) in layers.enumerated() {
            let sprite = SKSpriteNode(texture: shardTexture, size: CGSize(width: size.width * layer.1, height: size.height * layer.2))
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
            sprite.color = layer.0
            sprite.colorBlendFactor = 1
            sprite.alpha = layer.3
            sprite.blendMode = layer.4
            sprite.zPosition = 0.1 * CGFloat(index)
            node.addChild(sprite)
        }
        return node
    }

    /// Stone Spike: the ground under the target glows ochre and shudders, then shards of earth's
    /// light burst up round it from the middle outward (tall ones behind, short ones in front),
    /// puffing light where they break through, and knock it up off its feet; they stand a moment
    /// and sink back. `spread` widens the ring (a mastered skill's forest of spikes). Returns how
    /// long until they break through, when the hit should land.
    @discardableResult
    static func stoneSpikes(under target: BattleActor, level: Int, spread: CGFloat = 1, delay: TimeInterval = 0,
                            in parent: SKNode) -> TimeInterval {
        let light = ElementLight.earth
        let spots = spikeSpots.filter { $0.tiers.contains(level) }.sorted { abs($0.dx) < abs($1.dx) }
        let base = target.position
        let erupt = delay + 0.16
        groundGlow(at: base, light: light, width: (90 + CGFloat(level) * 10) * spread, appear: delay,
                   hold: 0.7 + 0.05 * Double(level), in: parent)
        // Motes of light hop on the shuddering ground before it gives way.
        for index in 0..<4 {
            let mote = glowSprite(light.bright, size: CGSize(width: 8, height: 8))
            mote.position = base + CGVector(dx: .random(in: -30...30), dy: .random(in: -6...6))
            mote.alpha = 0
            parent.addChild(mote)
            let hop = SKAction.moveBy(x: 0, y: 12, duration: 0.08)
            hop.timingMode = .easeOut
            mote.run(.sequence([.wait(forDuration: delay + Double(index) * 0.04), .fadeIn(withDuration: 0.02), hop,
                                .group([.moveBy(x: 0, y: -12, duration: 0.1), .fadeOut(withDuration: 0.1)]), .removeFromParent()]))
        }
        for (index, spot) in spots.enumerated() {
            let foot = base + CGVector(dx: spot.dx * spread, dy: spot.dy * spread)
            let spike = shard(light, size: spot.kind.size * spot.scale)
            spike.position = foot
            spike.zPosition = -foot.y   // stands among the fighters: in front of them or behind
            spike.yScale = 0.02
            spike.alpha = 0
            parent.addChild(spike)
            let start = erupt + Double(index) * 0.035
            let shoot = SKAction.scaleY(to: 1.12, duration: 0.09)
            shoot.timingMode = .easeOut
            spike.run(.sequence([
                .wait(forDuration: start),
                .group([.fadeIn(withDuration: 0.04), shoot]),
                .scaleY(to: 1, duration: 0.06),
                .wait(forDuration: max(0.15, 0.3 + 0.04 * Double(level) - Double(index) * 0.02)),
                .group([.scaleY(to: 0.1, duration: 0.22), .fadeOut(withDuration: 0.22)]),
                .removeFromParent(),
            ]))
            // A puff of light where it breaks through.
            let puff = lightBall(light, size: 30 * spot.scale, tint: 0.45, core: false)
            puff.position = foot
            puff.zPosition = spike.zPosition + 0.5
            puff.yScale = 0.45
            puff.alpha = 0
            parent.addChild(puff)
            puff.run(.sequence([.wait(forDuration: start), .fadeIn(withDuration: 0.04),
                                .group([.scaleX(to: 1.6, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
        sparks(from: base + CGVector(dx: 0, dy: 10), light: light, count: 6 + level * 2, reach: 46, delay: erupt, in: parent)
        // The hit knocks the target up off its feet.
        let knock = 8 + 3 * CGFloat(level)
        let rise = SKAction.moveBy(x: 0, y: knock, duration: 0.08)
        rise.timingMode = .easeOut
        let land = SKAction.moveBy(x: 0, y: -knock, duration: 0.2)
        land.timingMode = .easeIn
        target.sprite.run(.sequence([.wait(forDuration: erupt + 0.05), rise, land]))
        return erupt + 0.08
    }

    // MARK: - Fire

    /// Fire Bolt: a blazing ball of fire's light flies at the target, flickering and streaming
    /// sparks of yellow, orange and red behind it.
    static func fireball(from start: CGPoint?, to end: CGPoint?, level: Int, in parent: SKNode) async {
        guard let start, let end else { return }
        let ball = lightBall(.fire, size: 34 + CGFloat(level) * 8)
        ball.position = start
        ball.zPosition = 18_200
        parent.addChild(ball)
        // In an async function a plain run(_:) is SpriteKit's awaiting one: these go by key.
        ball.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.05), .scale(to: 0.92, duration: 0.05)])), withKey: "flicker")
        let tail = trail(.fire, level: level, parent: parent)
        ball.addChild(tail)
        let travel = SKAction.move(to: end, duration: 0.3)
        travel.timingMode = .easeIn
        await ball.run(travel)
        settle(tail, in: parent)
        ball.removeAllActions()
        ball.removeFromParent()
    }

    /// The fireball bursting on the target: a white-hot flash blooms into a ball of fire that burns
    /// out, sparks streak away and a ring of heat rolls out over glowing ground; from tier 2 flames
    /// rise round its feet, and from tier 4 a column of fire roars up through it.
    static func fireBlast(on target: BattleActor, level: Int, in parent: SKNode) {
        let light = ElementLight.fire
        let bloom = lightBall(light, size: 70 + CGFloat(level) * 14, tint: 0.6)
        bloom.position = target.center
        bloom.setScale(0.25)
        parent.addChild(bloom)
        let grow = SKAction.scale(to: 1, duration: 0.16)
        grow.timingMode = .easeOut
        bloom.run(.sequence([grow, .group([.scale(to: 1.25, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
        groundGlow(at: target.position, light: light, width: 80 + CGFloat(level) * 10, hold: 0.45, in: parent)
        ring(at: target.position + CGVector(dx: 0, dy: 4), color: light.main, size: CGSize(width: 60, height: 24),
             grow: 1.8 + 0.2 * CGFloat(level), in: parent)
        sparks(from: target.center, light: light, count: 10 + level * 4, reach: 50 + CGFloat(level) * 8, in: parent)
        if level >= 2 { rising(from: target, light: light, count: level * 3, height: 50 + CGFloat(level) * 12, in: parent) }
        if level >= 4 { column(on: target, light: light, width: 36 + CGFloat(level) * 4, in: parent) }
    }

    // MARK: - Wood

    /// Leaf Storm: a green glow gathers on the target as strokes of wood's light, like leaves in a
    /// cyclone, whirl round it and up, some gold among the green; it ends in a burst of green.
    static func leafCyclone(around target: BattleActor, level: Int, in parent: SKNode) {
        let light = ElementLight.wood
        let aura = lightBall(light, size: 56 + CGFloat(level) * 8, tint: 0.45, core: false)
        aura.position = target.center
        aura.alpha = 0
        parent.addChild(aura)
        aura.run(.sequence([
            .fadeIn(withDuration: 0.12), .wait(forDuration: 0.3),
            .group([.scale(to: 1.4, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
        sparks(from: target.center, light: light, count: 8 + level * 3, reach: 60, delay: 0.42, in: parent)
        let gold = UIColor(red: 1, green: 0.95, blue: 0.45, alpha: 1)
        let count = 10 + level * 5
        for index in 0..<count {
            let leaf = streak(light, color: index % 3 == 0 ? gold : light.bright, size: CGSize(width: 16, height: 6), tint: 0.55)
            let radius = CGFloat.random(in: 26...(40 + CGFloat(level) * 6))
            let path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius * 0.4, width: radius * 2, height: radius * 0.8)).cgPath
            leaf.position = target.center + CGVector(dx: 0, dy: -24)
            leaf.alpha = 0
            parent.addChild(leaf)
            leaf.run(.sequence([
                .wait(forDuration: Double(index) * 0.012),
                .fadeIn(withDuration: 0.04),
                .group([.follow(path, asOffset: true, orientToPath: true, duration: 0.5), .moveBy(x: 0, y: 46, duration: 0.5)]),
                .group([.fadeOut(withDuration: 0.15), .scale(to: 0.4, duration: 0.15)]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Water

    /// Jelly Splash, Bubble, Frost Breath: an orb of water's light, glinting on top, wobbles at the
    /// target, dripping blue light as it goes.
    static func waterOrb(from start: CGPoint?, to end: CGPoint?, level: Int, in parent: SKNode) async {
        guard let start, let end else { return }
        let size = 32 + CGFloat(level) * 7
        let orb = lightBall(.water, size: size)
        let glint = glowSprite(.white, size: CGSize(width: size * 0.2, height: size * 0.14))
        glint.position = CGPoint(x: -size * 0.13, y: size * 0.13)
        glint.zPosition = 0.5
        glint.alpha = 0.9
        orb.addChild(glint)
        orb.position = start
        orb.zPosition = 18_200
        parent.addChild(orb)
        let squash = SKAction.group([.scaleX(to: 1.12, duration: 0.07), .scaleY(to: 0.9, duration: 0.07)])
        let stretch = SKAction.group([.scaleX(to: 0.92, duration: 0.07), .scaleY(to: 1.1, duration: 0.07)])
        orb.run(.repeatForever(.sequence([squash, stretch])), withKey: "wobble")
        let drips = trail(.water, level: level, falling: true, parent: parent)
        orb.addChild(drips)
        let travel = SKAction.move(to: end, duration: 0.3)
        travel.timingMode = .easeIn
        await orb.run(travel)
        settle(drips, in: parent)
        orb.removeAllActions()
        orb.removeFromParent()
    }

    /// The orb bursting on the target: a flash of blue light in a mist, a crown of droplets thrown
    /// up and falling back, and ripples rolling out at its feet; from tier 4 a column of water
    /// surges up through it.
    static func waterSplash(on target: BattleActor, level: Int, in parent: SKNode) {
        let light = ElementLight.water
        let mist = shade(light.deep, size: CGSize(width: 150 + CGFloat(level) * 10, height: 70), alpha: 0.3)
        mist.position = target.center + CGVector(dx: 0, dy: -6)
        mist.zPosition = 17_990
        parent.addChild(mist)
        mist.run(.sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.4), .removeFromParent()]))
        let bloom = lightBall(light, size: 60 + CGFloat(level) * 12)
        bloom.position = target.center
        bloom.setScale(0.3)
        parent.addChild(bloom)
        let grow = SKAction.scale(to: 1, duration: 0.15)
        grow.timingMode = .easeOut
        bloom.run(.sequence([grow, .group([.scale(to: 1.2, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        for index in 0..<(level >= 3 ? 3 : 2) {
            ring(at: target.position + CGVector(dx: 0, dy: 2), color: index == 0 ? light.bright : light.main,
                 size: CGSize(width: 50, height: 18), grow: 1.8 + 0.25 * CGFloat(level) + CGFloat(index) * 0.4,
                 delay: Double(index) * 0.08, in: parent)
        }
        // The crown: droplets thrown up and out, falling back down.
        let count = 10 + level * 4
        for index in 0..<count {
            let drop = streak(light, color: light.bright, size: CGSize(width: 8, height: 11), tint: 0.5)
            drop.position = target.center
            parent.addChild(drop)
            let side = CGFloat.random(in: -1...1) * (40 + CGFloat(level) * 6)
            let up = SKAction.moveBy(x: side * 0.6, y: .random(in: 36...(56 + CGFloat(level) * 6)), duration: 0.2)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: side * 0.4, y: -CGFloat.random(in: 50...70), duration: 0.24)
            down.timingMode = .easeIn
            drop.run(.sequence([
                .wait(forDuration: Double(index) * 0.006),
                up, .group([down, .fadeOut(withDuration: 0.24), .scale(to: 0.5, duration: 0.24)]),
                .removeFromParent(),
            ]))
        }
        if level >= 4 { column(on: target, light: light, width: 32 + CGFloat(level) * 4, in: parent) }
    }
}
