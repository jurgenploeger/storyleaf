import SpriteKit
import UIKit

/// Battle effects, one per skill `animation` in content/skills.json. Every effect grows in five
/// tiers (`level` 1–5, one per two skill levels, see BattleScene): longer beams, more particles,
/// bigger explosions; on top of that, upgraded skills gather power first and land in glory
/// (`charge`, `glory`, `masterBanner`). The elemental spells (fire, water, wood, stone) are in
/// ElementEffects.swift, drawn in the same light, layered in each element's own colours.
enum SkillEffects {
    static let healGreen = UIColor(red: 0.55, green: 1, blue: 0.6, alpha: 1)

    static func glowSprite(_ color: UIColor, size: CGSize) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: SoftTextures.glow, size: size)
        sprite.color = color
        sprite.colorBlendFactor = 1
        sprite.blendMode = .add
        sprite.zPosition = 18_000
        return sprite
    }

    /// Long crossing light beams — Fairyland Online's signature blade effect.
    static func slash(on target: BattleActor?, level: Int, in parent: SKNode) {
        guard let target else { return }
        let beams = level >= 3 ? 2 : 1
        let colors = [UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), UIColor(red: 1, green: 0.45, blue: 0.9, alpha: 1)]
        for index in 0..<beams {
            let beam = glowSprite(colors[index], size: CGSize(width: 90 + CGFloat(level) * 45, height: 10 + CGFloat(level) * 3))
            beam.position = target.center
            beam.zRotation = index == 0 ? -0.55 : 0.6
            beam.xScale = 0.05
            parent.addChild(beam)
            beam.run(.sequence([
                .wait(forDuration: Double(index) * 0.09),
                .scaleX(to: 1, duration: 0.08),
                .fadeOut(withDuration: 0.28),
                .removeFromParent(),
            ]))
        }
        burst(at: target.center, color: .white, count: 4 + level * 3, speed: 60, in: parent)
    }

    static func whirl(on target: BattleActor, level: Int, in parent: SKNode) {
        for index in 0..<(1 + level) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 50, height: 22))
            ring.strokeColor = UIColor(white: 1, alpha: 0.85)
            ring.lineWidth = 3
            ring.glowWidth = 2
            ring.position = target.position + CGVector(dx: 0, dy: CGFloat(index) * 14)
            ring.zPosition = 18_000
            ring.setScale(0.3)
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.05),
                .group([.scale(to: 1.4 + CGFloat(level) * 0.1, duration: 0.3), .fadeOut(withDuration: 0.35), .rotate(byAngle: .pi, duration: 0.35)]),
                .removeFromParent(),
            ]))
        }
    }

    static func projectile(from start: CGPoint?, to end: CGPoint?, color: UIColor, level: Int, trail: Bool, in parent: SKNode) async {
        guard let start, let end else { return }
        let diameter = 20 + CGFloat(level) * 6
        let orb = glowSprite(color, size: CGSize(width: diameter, height: diameter))
        orb.position = start
        let core = glowSprite(.white, size: CGSize(width: diameter * 0.45, height: diameter * 0.45))
        orb.addChild(core)
        if trail {
            let emitter = SKEmitterNode()
            emitter.particleTexture = SoftTextures.glow
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleBlendMode = .add
            emitter.particleBirthRate = 120
            emitter.particleLifetime = 0.35
            emitter.particleSpeed = 20
            emitter.emissionAngleRange = .pi * 2
            emitter.particleScale = 0.35 + CGFloat(level) * 0.06
            emitter.particleScaleSpeed = -0.8
            emitter.particleAlphaSpeed = -2.5
            emitter.targetNode = parent
            orb.addChild(emitter)
        }
        parent.addChild(orb)
        let travel = SKAction.move(to: end, duration: 0.3)
        travel.timingMode = .easeIn
        await orb.run(travel)
        orb.removeFromParent()
    }

    static func explosion(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        let flash = glowSprite(color, size: CGSize(width: 60, height: 60))
        flash.position = target.center
        flash.setScale(0.3)
        parent.addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.6 + CGFloat(level) * 0.35, duration: 0.25), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        burst(at: target.center, color: color, count: 10 + level * 6, speed: 80 + CGFloat(level) * 18, in: parent)
        if level >= 3 {
            // A column of flame rising from the target.
            for index in 0..<(level * 3) {
                let flame = glowSprite(index % 2 == 0 ? color : UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), size: CGSize(width: 22, height: 22))
                flame.position = target.position + CGVector(dx: .random(in: -18...18), dy: 0)
                parent.addChild(flame)
                flame.run(.sequence([
                    .wait(forDuration: Double(index) * 0.03),
                    .group([.moveBy(x: 0, y: 70 + CGFloat(level) * 12, duration: 0.45), .fadeOut(withDuration: 0.45), .scale(to: 0.3, duration: 0.45)]),
                    .removeFromParent(),
                ]))
            }
        }
    }

    /// A beam of light from the sky (Blessing).
    static func lightPillar(on target: BattleActor, level: Int, in parent: SKNode) {
        let pillar = glowSprite(UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 1), size: CGSize(width: 44 + CGFloat(level) * 8, height: 360))
        pillar.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        pillar.position = target.position
        pillar.yScale = 0.05
        parent.addChild(pillar)
        pillar.run(.sequence([.scaleY(to: 1, duration: 0.15), .wait(forDuration: 0.2), .fadeOut(withDuration: 0.4), .removeFromParent()]))
        sparkles(on: target, color: UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), level: level, in: parent)
    }

    /// Three glowing claw rakes (Wild Call).
    static func claws(on target: BattleActor, level: Int, in parent: SKNode) {
        for index in 0..<3 {
            let claw = glowSprite(UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1), size: CGSize(width: 70 + CGFloat(level) * 12, height: 7))
            claw.position = target.center + CGVector(dx: CGFloat(index - 1) * 12, dy: CGFloat(index - 1) * -6)
            claw.zRotation = -0.9
            claw.xScale = 0.05
            parent.addChild(claw)
            claw.run(.sequence([.wait(forDuration: Double(index) * 0.05), .scaleX(to: 1, duration: 0.07), .fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
    }

    static func needles(on target: BattleActor, level: Int, in parent: SKNode) {
        for index in 0..<(6 + level * 3) {
            let needle = SKSpriteNode(color: UIColor(red: 0.45, green: 0.75, blue: 0.3, alpha: 1), size: CGSize(width: 2, height: 12))
            needle.position = target.center + CGVector(dx: .random(in: -30...30), dy: 90)
            needle.zPosition = 18_000
            parent.addChild(needle)
            needle.run(.sequence([
                .wait(forDuration: Double(index) * 0.025),
                .moveBy(x: 0, y: -80, duration: 0.16),
                .fadeOut(withDuration: 0.1),
                .removeFromParent(),
            ]))
        }
    }

    static func shockwave(under target: BattleActor, level: Int, in parent: SKNode) {
        let ring = SKShapeNode(ellipseOf: CGSize(width: 50, height: 20))
        ring.strokeColor = UIColor(white: 1, alpha: 0.9)
        ring.lineWidth = 3
        ring.position = target.position
        ring.zPosition = target.zPosition + 1
        parent.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 2.2 + CGFloat(level) * 0.3, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        burst(at: target.position, color: UIColor(red: 0.8, green: 0.7, blue: 0.55, alpha: 1), count: 8 + level * 2, speed: 60, in: parent)
    }

    static func bite(on target: BattleActor, in parent: SKNode) {
        for side in [-1.0, 1.0] {
            let jaw = SKShapeNode(path: UIBezierPath(arcCenter: .zero, radius: 18, startAngle: 0.3, endAngle: .pi - 0.3, clockwise: true).cgPath)
            jaw.strokeColor = .white
            jaw.lineWidth = 4
            jaw.position = target.center + CGVector(dx: 0, dy: 16 * side)
            jaw.yScale = side
            jaw.zPosition = 18_000
            parent.addChild(jaw)
            jaw.run(.sequence([.moveBy(x: 0, y: -12 * side, duration: 0.1), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
    }

    static func sparkles(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        for index in 0..<(6 + level * 3) {
            let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 9, height: 9))
            star.color = color
            star.colorBlendFactor = 0.6
            star.blendMode = .add
            star.position = target.position + CGVector(dx: .random(in: -26...26), dy: .random(in: 0...20))
            star.zPosition = 18_000
            star.alpha = 0
            parent.addChild(star)
            star.run(.sequence([
                .wait(forDuration: Double(index) * 0.04),
                .group([.fadeIn(withDuration: 0.1), .moveBy(x: 0, y: 60, duration: 0.6), .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.25)])]),
                .removeFromParent(),
            ]))
        }
    }

    static func shield(on target: BattleActor, in parent: SKNode) {
        let bubble = SKShapeNode(ellipseOf: CGSize(width: target.sprite.size.width * target.fieldScale * 1.1, height: target.height * 0.95))
        bubble.fillColor = UIColor(red: 0.5, green: 0.75, blue: 1, alpha: 0.2)
        bubble.strokeColor = UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.8)
        bubble.lineWidth = 2
        bubble.position = target.center
        bubble.zPosition = 18_000
        bubble.setScale(0.6)
        parent.addChild(bubble)
        bubble.run(.sequence([.scale(to: 1, duration: 0.15), .wait(forDuration: 0.35), .fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    /// Dark puffs when something is defeated, like Fairyland Online's black smoke.
    static func smoke(at point: CGPoint, in parent: SKNode) {
        for _ in 0..<9 {
            let puff = SKSpriteNode(texture: SoftTextures.glow, size: CGSize(width: 26, height: 26))
            puff.color = UIColor(white: 0.08, alpha: 1)
            puff.colorBlendFactor = 1
            puff.alpha = 0.85
            puff.position = point + CGVector(dx: .random(in: -18...18), dy: .random(in: -10...14))
            puff.zPosition = 18_000
            parent.addChild(puff)
            puff.run(.sequence([
                .group([.scale(to: .random(in: 1.6...2.4), duration: 0.6), .moveBy(x: .random(in: -10...10), y: 26, duration: 0.6), .fadeOut(withDuration: 0.6)]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Glory (upgraded skills)

    /// Power gathering around the caster before an upgraded skill (level 2+): rings of light close
    /// in and motes rise, more and brighter with every level; at the top level a golden sunburst
    /// opens behind them. Returns how long to hold before the skill itself plays.
    static func charge(on caster: BattleActor, color: UIColor, level: Int, in parent: SKNode) -> TimeInterval {
        guard level >= 2 else { return 0 }
        let gold = UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
        let tint = level >= 5 ? gold : color
        for index in 0..<(level - 1) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 70, height: 26))
            ring.strokeColor = tint.withAlphaComponent(0.9)
            ring.lineWidth = 2.5
            ring.glowWidth = 4
            ring.position = caster.position
            ring.zPosition = 18_000
            ring.setScale(2.2)
            ring.alpha = 0
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.08),
                .group([.fadeIn(withDuration: 0.08), .scale(to: 0.5, duration: 0.3)]),
                .fadeOut(withDuration: 0.08), .removeFromParent(),
            ]))
        }
        for index in 0..<(level * 5) {
            let mote = glowSprite(index % 3 == 0 ? .white : tint, size: CGSize(width: 9, height: 9))
            mote.position = caster.position + CGVector(dx: .random(in: -26...26), dy: .random(in: -4...10))
            mote.alpha = 0
            parent.addChild(mote)
            mote.run(.sequence([
                .wait(forDuration: .random(in: 0...0.25)),
                .group([.fadeIn(withDuration: 0.06), .moveBy(x: 0, y: 46 + CGFloat(level) * 10, duration: 0.45), .scale(to: 0.3, duration: 0.45)]),
                .fadeOut(withDuration: 0.1), .removeFromParent(),
            ]))
        }
        let aura = glowSprite(tint, size: CGSize(width: 70 + CGFloat(level) * 14, height: 90 + CGFloat(level) * 16))
        aura.position = caster.center
        aura.zPosition = caster.zPosition - 1
        aura.alpha = 0
        parent.addChild(aura)
        aura.run(.sequence([.fadeAlpha(to: 0.35 + 0.1 * CGFloat(level - 2), duration: 0.15), .wait(forDuration: 0.25), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        if level >= 5 {
            rays(at: caster.center, color: gold, count: 14, length: 120, width: 9, z: caster.zPosition - 2, in: parent)
        }
        return 0.25 + 0.06 * Double(level)
    }

    /// The landing of an upgraded skill on each target: a ring of light bursting outward (level 3+),
    /// light rays and a rain of sparkles (4+), all in gold at the top level.
    static func glory(on target: BattleActor, color: UIColor, level: Int, in parent: SKNode) {
        guard level >= 3 else { return }
        let gold = UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
        let tint = level >= 5 ? gold : color
        for index in 0..<(level - 2) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: 40, height: 16))
            ring.strokeColor = index == 0 ? .white : tint
            ring.lineWidth = 3
            ring.glowWidth = 5
            ring.position = target.position
            ring.zPosition = 18_000
            ring.setScale(0.4)
            parent.addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: Double(index) * 0.1),
                .group([.scale(to: 2.4 + CGFloat(level) * 0.4, duration: 0.45), .fadeOut(withDuration: 0.45)]),
                .removeFromParent(),
            ]))
        }
        guard level >= 4 else { return }
        rays(at: target.center, color: tint, count: level >= 5 ? 12 : 8, length: 70 + CGFloat(level) * 14, width: 7,
             z: target.zPosition - 1, in: parent)
        for _ in 0..<(level * 4) {
            let sparkle = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 9, height: 9))
            sparkle.color = Bool.random() ? .white : tint
            sparkle.colorBlendFactor = 1
            sparkle.blendMode = .add
            sparkle.zPosition = 18_500
            sparkle.position = target.center + CGVector(dx: .random(in: -50...50), dy: .random(in: 40...90))
            sparkle.alpha = 0
            parent.addChild(sparkle)
            sparkle.run(.sequence([
                .wait(forDuration: .random(in: 0...0.35)),
                .group([.fadeIn(withDuration: 0.08), .moveBy(x: .random(in: -10...10), y: -70, duration: 0.6), .rotate(byAngle: .pi, duration: 0.6)]),
                .fadeOut(withDuration: 0.15), .removeFromParent(),
            ]))
        }
    }

    /// Beams of light fanning out from a point like a sunburst.
    static func rays(at point: CGPoint, color: UIColor, count: Int, length: CGFloat, width: CGFloat, z: CGFloat, in parent: SKNode) {
        for index in 0..<count {
            let ray = glowSprite(color, size: CGSize(width: length, height: width))
            ray.anchorPoint = CGPoint(x: 0, y: 0.5)
            ray.position = point
            ray.zPosition = z
            ray.zRotation = CGFloat(index) / CGFloat(count) * 2 * .pi
            ray.xScale = 0.05
            ray.alpha = 0.9
            parent.addChild(ray)
            ray.run(.sequence([
                .group([.scaleX(to: 1, duration: 0.18), .rotate(byAngle: 0.25, duration: 0.6)]),
                .fadeOut(withDuration: 0.4), .removeFromParent(),
            ]))
        }
    }

    /// A mastered skill (top level) announces itself: its name in big gold letters.
    static func masterBanner(_ name: String, level: Int, size: CGSize, in scene: SKScene) {
        let banner = NameTag(name, color: Nodes.gold, size: 30, alignment: .center)
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        banner.zPosition = 31_000
        banner.setScale(0.4)
        banner.alpha = 0
        scene.addChild(banner)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.15, duration: 0.18)]),
            .scale(to: 1, duration: 0.1),
            .wait(forDuration: 0.6),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 20, duration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    static func screenFlash(color: UIColor, strength: CGFloat, size: CGSize, in scene: SKScene) {
        let flash = SKSpriteNode(color: color, size: size)
        flash.anchorPoint = .zero
        flash.alpha = strength
        flash.zPosition = 30_000
        scene.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    static func burst(at point: CGPoint, color: UIColor, count: Int, speed: CGFloat, in parent: SKNode) {
        for index in 0..<count {
            let bit = glowSprite(color, size: CGSize(width: 8, height: 8))
            bit.position = point
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi + .random(in: -0.2...0.2)
            let distance = speed * .random(in: 0.5...1)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance * 0.7, duration: 0.4)
            move.timingMode = .easeOut
            parent.addChild(bit)
            bit.run(.sequence([.group([move, .fadeOut(withDuration: 0.4), .scale(to: 0.3, duration: 0.4)]), .removeFromParent()]))
        }
    }

    /// Motes swirling inward to a point (a monster being drawn into a Seal Stone).
    static func implode(to point: CGPoint, color: UIColor, in parent: SKNode) {
        for index in 0..<18 {
            let bit = glowSprite(color, size: CGSize(width: 7, height: 7))
            let angle = CGFloat(index) / 18 * 2 * .pi
            let distance = CGFloat.random(in: 50...80)
            bit.position = point + CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance * 0.7)
            bit.alpha = 0
            parent.addChild(bit)
            let swirl = SKAction.move(to: point, duration: 0.45)
            swirl.timingMode = .easeIn
            bit.run(.sequence([.wait(forDuration: Double(index % 6) * 0.03), .fadeIn(withDuration: 0.08),
                               .group([swirl, .scale(to: 0.3, duration: 0.45)]), .removeFromParent()]))
        }
    }

    /// The Seal Stone as it looks in your bag (art/sprites/item_seal_stone.png, tools/item_art.py):
    /// a faceted teal crystal with a white sealing spiral.
    static var sealStoneTexture: SKTexture { ArtLibrary.shared.sprite("item_seal_stone").texture }

    /// The seal laid on the ground under a monster: two rings of teal light round a spiral, the
    /// stone's own rune, turning slowly, with `marks` diamonds on the outer ring that start dark and
    /// light one by one as the stone pulses (`light(mark:)`). Lies flat, under every fighter.
    final class SealCircle: SKNode {
        private let spinner = SKNode()
        private var diamonds: [SKShapeNode] = []
        private var rings: [SKShapeNode] = []

        init(radius: CGFloat, marks: Int) {
            super.init()
            let light = SkillEffects.ElementLight.seal
            zPosition = -8_500
            yScale = 0.42
            addChild(SkillEffects.shade(light.deep, size: CGSize(width: radius * 2.6, height: radius * 2.6), alpha: 0.5))
            addChild(spinner)
            for (index, scale) in [CGFloat(1), 0.74].enumerated() {
                let ring = SKShapeNode(circleOfRadius: radius * scale)
                ring.strokeColor = index == 0 ? light.main : light.bright
                ring.lineWidth = index == 0 ? 3.5 : 2
                ring.glowWidth = 5
                ring.blendMode = .add
                spinner.addChild(ring)
                rings.append(ring)
            }
            // The spiral: two and a half turns from the middle out to the inner ring.
            let spiral = CGMutablePath()
            let turns: CGFloat = 2.5
            for step in 0...90 {
                let t = CGFloat(step) / 90
                let angle = t * turns * 2 * .pi
                let point = CGPoint(x: cos(angle) * radius * 0.66 * t, y: sin(angle) * radius * 0.66 * t)
                if step == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
            }
            let rune = SKShapeNode(path: spiral)
            rune.strokeColor = light.core
            rune.lineWidth = 2
            rune.glowWidth = 3
            rune.blendMode = .add
            spinner.addChild(rune)
            for index in 0..<max(1, marks) {
                let angle = CGFloat(index) / CGFloat(max(1, marks)) * 2 * .pi + .pi / 2
                let diamond = SKShapeNode(rectOf: CGSize(width: 10, height: 10))
                diamond.zRotation = .pi / 4
                diamond.position = CGPoint(x: cos(angle) * radius * 0.87, y: sin(angle) * radius * 0.87)
                diamond.strokeColor = light.bright
                diamond.fillColor = light.deep
                diamond.lineWidth = 1.5
                diamond.glowWidth = 1
                spinner.addChild(diamond)
                diamonds.append(diamond)
            }
            spinner.run(.repeatForever(.rotate(byAngle: -.pi, duration: 2.4)))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// Opens out from a point.
        func open() {
            setScale(0.15)
            yScale = 0.06
            alpha = 0
            let grow = SKAction.group([.fadeIn(withDuration: 0.18), .scaleX(to: 1, duration: 0.3), .scaleY(to: 0.42, duration: 0.3)])
            grow.timingMode = .easeOut
            run(grow)
        }

        /// One of the outer marks catches the light (each pulse of the stone lights the next).
        func light(mark index: Int) {
            guard !diamonds.isEmpty else { return }
            let diamond = diamonds[index % diamonds.count]
            diamond.fillColor = SkillEffects.ElementLight.seal.core
            diamond.glowWidth = 5
            diamond.run(.sequence([.scale(to: 1.8, duration: 0.08), .scale(to: 1, duration: 0.18)]))
        }

        /// Sealed: the rings turn gold and the circle closes into its middle.
        func close() {
            for ring in rings + diamonds { ring.strokeColor = Nodes.gold }
            spinner.run(.rotate(byAngle: -.pi * 2, duration: 0.4))
            run(.sequence([.group([.scale(to: 0.05, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
        }

        /// Broken: the circle flickers out.
        func shatter() {
            run(.sequence([.fadeAlpha(to: 0.2, duration: 0.05), .fadeAlpha(to: 0.9, duration: 0.05),
                           .fadeAlpha(to: 0.1, duration: 0.05), .fadeAlpha(to: 0.6, duration: 0.05),
                           .group([.fadeOut(withDuration: 0.25), .scaleX(to: 1.3, duration: 0.25)]), .removeFromParent()]))
        }
    }

    /// Motes of seal light spiralling from round a monster (its feet at `base`, `radius` across)
    /// up into the stone at `top`, the way a sealed monster pours into the crystal. `reverse`: they
    /// stream back down out of it (the monster breaking free).
    static func sealSpiral(from base: CGPoint, to top: CGPoint, radius: CGFloat, count: Int, reverse: Bool = false, in parent: SKNode) {
        let light = ElementLight.seal
        let duration: TimeInterval = 0.7
        for index in 0..<count {
            let mote = glowSprite(index % 3 == 0 ? light.core : light.bright, size: CGSize(width: 8, height: 8))
            let start = CGFloat(index) / CGFloat(count) * 2 * .pi
            mote.alpha = 0
            mote.zPosition = 16_000
            parent.addChild(mote)
            let climb = SKAction.customAction(withDuration: duration) { node, elapsed in
                let progress = min(1, elapsed / CGFloat(duration))
                let t = reverse ? 1 - progress : progress
                let eased = t * t * (3 - 2 * t)
                let angle = start + eased * 4 * .pi
                let reach = radius * (1 - eased)
                node.position = CGPoint(x: base.x + (top.x - base.x) * eased + cos(angle) * reach,
                                        y: base.y + (top.y - base.y) * eased + sin(angle) * reach * 0.4)
                node.setScale(1.2 - 0.6 * eased)
            }
            mote.run(.sequence([
                .wait(forDuration: Double(index) * 0.022),
                .fadeIn(withDuration: 0.06),
                climb,
                .fadeOut(withDuration: 0.08),
                .removeFromParent(),
            ]))
        }
    }

    /// The Seal Stone breaking: splinters of teal crystal flying off and dropping away.
    static func crystalShards(at point: CGPoint, in parent: SKNode) {
        let light = ElementLight.seal
        for index in 0..<9 {
            let shard = SKSpriteNode(texture: shardTexture, size: CGSize(width: 7, height: 13))
            shard.color = index % 3 == 0 ? light.core : light.main
            shard.colorBlendFactor = 1
            shard.position = point
            shard.zPosition = 16_000
            shard.zRotation = .random(in: 0...(2 * .pi))
            parent.addChild(shard)
            let angle = CGFloat(index) / 9 * 2 * .pi + .random(in: -0.3...0.3)
            let distance = CGFloat.random(in: 34...60)
            let out = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance * 0.8 + 10, duration: 0.25)
            out.timingMode = .easeOut
            let fall = SKAction.moveBy(x: cos(angle) * 8, y: -46, duration: 0.4)
            fall.timingMode = .easeIn
            shard.run(.sequence([
                .group([.sequence([out, fall]), .rotate(byAngle: .random(in: -6...6), duration: 0.65),
                        .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.25)])]),
                .removeFromParent(),
            ]))
        }
    }
}

// MARK: - Mastered skills

extension SkillEffects {
    /// The stage for a mastered skill: the battlefield dims (fighters stay lit), a spinning magic
    /// circle opens under the caster and a pillar of light rises from it. Returns the dimmer, which
    /// `ultimateEnd` lifts again.
    static func ultimateStart(caster: BattleActor?, color: UIColor, size: CGSize, in parent: SKNode) -> SKNode {
        let dim = SKSpriteNode(color: .black, size: CGSize(width: size.width * 3, height: size.height * 3))
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.zPosition = -9_000   // above the ground, below every fighter
        dim.alpha = 0
        parent.addChild(dim)
        dim.run(.fadeAlpha(to: 0.6, duration: 0.25))
        guard let caster else { return dim }
        magicCircle(at: caster.position, color: color, radius: 70, duration: 1.4, in: parent)
        let pillar = glowSprite(color, size: CGSize(width: 60, height: size.height * 1.2))
        pillar.anchorPoint = CGPoint(x: 0.5, y: 0)
        pillar.position = caster.position
        pillar.zPosition = caster.zPosition - 1
        pillar.xScale = 0.1
        pillar.alpha = 0
        parent.addChild(pillar)
        pillar.run(.sequence([
            .group([.fadeAlpha(to: 0.85, duration: 0.2), .scaleX(to: 1, duration: 0.25)]),
            .wait(forDuration: 0.35),
            .group([.fadeOut(withDuration: 0.4), .scaleX(to: 2.2, duration: 0.4)]),
            .removeFromParent(),
        ]))
        rays(at: caster.center, color: .white, count: 18, length: 170, width: 10, z: caster.zPosition - 2, in: parent)
        for _ in 0..<26 {
            let mote = glowSprite(Bool.random() ? .white : color, size: CGSize(width: 10, height: 10))
            mote.position = caster.position + CGVector(dx: .random(in: -70...70), dy: .random(in: -20...10))
            mote.alpha = 0
            parent.addChild(mote)
            mote.run(.sequence([
                .wait(forDuration: .random(in: 0...0.4)),
                .group([.fadeIn(withDuration: 0.08), .moveBy(x: 0, y: .random(in: 120...220), duration: 0.7), .scale(to: 0.2, duration: 0.7)]),
                .removeFromParent(),
            ]))
        }
        return dim
    }

    /// The finale of a mastered skill on its targets, in the skill's own style (`animation` in
    /// content/skills.json): a meteor rain for fire, a tidal wave for water, a forest of stone
    /// spikes, a leaf hurricane, pillars of holy light, giant crossing blades, a tornado...
    static func ultimateFinale(on targets: [BattleActor], style: String, color: UIColor, size: CGSize, in parent: SKNode) {
        for target in targets {
            magicCircle(at: target.position, color: color, radius: 55, duration: 0.9, in: parent)
        }
        switch style {
        case "fire":
            for (index, target) in targets.enumerated() {
                for drop in 0..<3 {
                    let point = target.center + CGVector(dx: .random(in: -24...24), dy: .random(in: -10...10))
                    let delay = Double(index) * 0.08 + Double(drop) * 0.12
                    meteor(onto: point, color: color, delay: delay, size: size, in: parent)
                }
            }
        case "water":
            let wave = glowSprite(color, size: CGSize(width: size.width * 0.5, height: 160))
            wave.position = CGPoint(x: -size.width * 0.3, y: (targets.first?.center.y ?? size.height / 2))
            wave.zPosition = 19_000
            wave.alpha = 0.85
            parent.addChild(wave)
            wave.run(.sequence([.moveTo(x: size.width * 1.3, duration: 0.55), .removeFromParent()]))
            for target in targets { waterSplash(on: target, level: 5, in: parent) }
        case "stone":
            // A forest of spikes: the full set under each target and a wider ring round it.
            for target in targets {
                stoneSpikes(under: target, level: 5, in: parent)
                stoneSpikes(under: target, level: 3, spread: 1.9, delay: 0.12, in: parent)
            }
        case "leaves":
            for target in targets {
                leafCyclone(around: target, level: 5, in: parent)
                whirl(on: target, level: 5, in: parent)
            }
        case "holy", "heal":
            for target in targets {
                lightPillar(on: target, level: 5, in: parent)
                rays(at: target.center, color: .white, count: 16, length: 140, width: 8, z: target.zPosition - 1, in: parent)
            }
        case "whirlwind":
            for target in targets {
                for level in 0..<3 {
                    let node = SKNode()
                    node.position = CGPoint(x: 0, y: CGFloat(level) * 28)
                    parent.addChild(node)
                    whirl(on: target, level: 5, in: node)
                    node.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
                }
            }
        default:
            // Two giant blades crossing the whole field through the targets.
            let middle = targets.isEmpty ? CGPoint(x: size.width / 2, y: size.height / 2)
                : CGPoint(x: targets.map(\.center.x).reduce(0, +) / CGFloat(targets.count), y: targets.map(\.center.y).reduce(0, +) / CGFloat(targets.count))
            for (index, angle) in [CGFloat(-0.6), 0.6].enumerated() {
                let blade = glowSprite(index == 0 ? .white : color, size: CGSize(width: size.width * 1.4, height: 22))
                blade.position = middle
                blade.zRotation = angle
                blade.zPosition = 19_000
                blade.xScale = 0.02
                parent.addChild(blade)
                blade.run(.sequence([
                    .wait(forDuration: Double(index) * 0.12),
                    .scaleX(to: 1, duration: 0.1),
                    .fadeOut(withDuration: 0.45),
                    .removeFromParent(),
                ]))
            }
            for target in targets { burst(at: target.center, color: color, count: 22, speed: 120, in: parent) }
        }
    }

    /// Lifts the dimmer with a last shower of light.
    static func ultimateEnd(_ dim: SKNode, color: UIColor, size: CGSize, in parent: SKNode) {
        dim.run(.sequence([.fadeOut(withDuration: 0.45), .removeFromParent()]))
        for _ in 0..<30 {
            let spark = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 10, height: 10))
            spark.color = Bool.random() ? .white : color
            spark.colorBlendFactor = 1
            spark.blendMode = .add
            spark.zPosition = 19_500
            spark.position = CGPoint(x: .random(in: 0...size.width), y: size.height * .random(in: 0.5...1))
            spark.alpha = 0
            parent.addChild(spark)
            spark.run(.sequence([
                .wait(forDuration: .random(in: 0...0.4)),
                .group([.fadeIn(withDuration: 0.1), .moveBy(x: 0, y: -CGFloat.random(in: 120...240), duration: 0.9), .rotate(byAngle: .pi, duration: 0.9)]),
                .fadeOut(withDuration: 0.2), .removeFromParent(),
            ]))
        }
    }

    /// A glowing double ring with runes, squashed flat on the ground and spinning.
    static func magicCircle(at point: CGPoint, color: UIColor, radius: CGFloat, duration: TimeInterval, in parent: SKNode) {
        let flat = SKNode()
        flat.position = point
        flat.yScale = 0.4
        flat.zPosition = -8_500
        parent.addChild(flat)
        let spinner = SKNode()
        flat.addChild(spinner)
        for (index, scale) in [CGFloat(1), 0.72].enumerated() {
            let ring = SKShapeNode(circleOfRadius: radius * scale)
            ring.strokeColor = index == 0 ? color : .white
            ring.lineWidth = index == 0 ? 4 : 2
            ring.glowWidth = 6
            ring.fillColor = .clear
            spinner.addChild(ring)
        }
        for index in 0..<8 {
            let rune = SKShapeNode(rectOf: CGSize(width: 12, height: 12), cornerRadius: 2)
            rune.strokeColor = .white
            rune.fillColor = color.withAlphaComponent(0.6)
            rune.glowWidth = 3
            let angle = CGFloat(index) / 8 * 2 * .pi
            rune.position = CGPoint(x: cos(angle) * radius * 0.86, y: sin(angle) * radius * 0.86)
            rune.zRotation = angle
            spinner.addChild(rune)
        }
        flat.setScale(0.2)
        flat.yScale = 0.08
        flat.alpha = 0
        spinner.run(.repeatForever(.rotate(byAngle: .pi, duration: 0.8)))
        flat.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .scaleX(to: 1, duration: 0.2), .scaleY(to: 0.4, duration: 0.2)]),
            .wait(forDuration: duration),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    /// A blazing rock streaking down from the top-left onto a point, bursting into fire.
    static func meteor(onto point: CGPoint, color: UIColor, delay: TimeInterval, size: CGSize, in parent: SKNode) {
        let rock = glowSprite(.white, size: CGSize(width: 26, height: 26))
        let tail = glowSprite(color, size: CGSize(width: 90, height: 22))
        tail.position = CGPoint(x: -40, y: 0)
        tail.zPosition = -1
        rock.addChild(tail)
        let start = point + CGVector(dx: -size.width * 0.45, dy: size.height * 0.6)
        rock.position = start
        rock.zRotation = atan2(point.y - start.y, point.x - start.x)
        rock.zPosition = 19_000
        rock.alpha = 0
        parent.addChild(rock)
        let fall = SKAction.move(to: point, duration: 0.32)
        fall.timingMode = .easeIn
        rock.run(.sequence([
            .wait(forDuration: delay), .fadeIn(withDuration: 0.04), fall,
            .run {
                SkillEffects.burst(at: point, color: color, count: 16, speed: 90, in: parent)
                SkillEffects.burst(at: point, color: .white, count: 8, speed: 50, in: parent)
                let blast = SkillEffects.glowSprite(color, size: CGSize(width: 110, height: 80))
                blast.position = point
                blast.setScale(0.3)
                parent.addChild(blast)
                blast.run(.sequence([.group([.scale(to: 1.3, duration: 0.25), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
            },
            .removeFromParent(),
        ]))
    }
}

// MARK: - Fighting styles

extension SkillEffects {
    /// How someone gathers themselves before a skill, by class: a mage draws a rune circle, a
    /// fighter flares up in a battle aura, a beast tamer calls a swirl of wild spirits. Their race
    /// adds its touch: elves shed leaves, dwarves crack the ground, humans glint.
    static func flourish(on caster: BattleActor, classID: String?, raceID: String?, color: UIColor, in parent: SKNode) {
        switch classID ?? "" {
        case "mage":
            magicCircle(at: caster.position, color: color, radius: 42, duration: 0.45, in: parent)
        case "fighter":
            let aura = glowSprite(UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1), size: CGSize(width: 80, height: 110))
            aura.position = caster.center
            aura.zPosition = caster.zPosition - 1
            aura.setScale(0.6)
            aura.alpha = 0
            parent.addChild(aura)
            aura.run(.sequence([.group([.fadeAlpha(to: 0.7, duration: 0.12), .scale(to: 1.2, duration: 0.25)]), .fadeOut(withDuration: 0.25), .removeFromParent()]))
        case "tamer":
            for index in 0..<10 {
                let spirit = glowSprite(UIColor(red: 0.6, green: 1, blue: 0.6, alpha: 1), size: CGSize(width: 10, height: 10))
                let angle = CGFloat(index) / 10 * 2 * .pi
                spirit.position = caster.center + CGVector(dx: cos(angle) * 40, dy: sin(angle) * 20)
                parent.addChild(spirit)
                let swirl = SKAction.customAction(withDuration: 0.45) { node, time in
                    let a = angle + time * 9
                    let r = 40 * (1 - time / 0.45 * 0.6)
                    node.position = caster.center + CGVector(dx: cos(a) * r, dy: sin(a) * r * 0.5 + time * 40)
                }
                spirit.run(.sequence([swirl, .fadeOut(withDuration: 0.1), .removeFromParent()]))
            }
        default:
            break
        }
        let touch: UIColor? = switch raceID ?? "" {
        case "elf": UIColor(red: 0.55, green: 0.95, blue: 0.45, alpha: 1)
        case "dwarf": UIColor(red: 0.8, green: 0.6, blue: 0.35, alpha: 1)
        case "human": UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 1)
        default: nil
        }
        guard let touch else { return }
        if raceID == "dwarf" {
            burst(at: caster.position, color: touch, count: 10, speed: 50, in: parent)
        } else {
            for _ in 0..<8 {
                let bit = glowSprite(touch, size: CGSize(width: 7, height: 7))
                bit.position = caster.center + CGVector(dx: .random(in: -22...22), dy: .random(in: 10...40))
                parent.addChild(bit)
                bit.run(.sequence([.group([.moveBy(x: .random(in: -14...14), y: raceID == "elf" ? -30 : 24, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            }
        }
    }
}
