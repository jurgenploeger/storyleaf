import SpriteKit
import UIKit

/// The palettes of the skills' own effects (SkillStyles below), alongside the elements' own.
extension SkillEffects.ElementLight {
    static let frost = Self(deep: tone(0.22, 0.5, 0.88), main: tone(0.6, 0.86, 1), bright: tone(0.86, 0.97, 1), core: tone(1, 1, 1))
    static let bubble = Self(deep: tone(0.1, 0.5, 0.75), main: tone(0.4, 0.82, 0.95), bright: tone(0.75, 0.95, 1), core: tone(1, 1, 1))
    /// A Seal Stone's teal, the colour of the crystal in your bag.
    static let seal = Self(deep: tone(0.04, 0.42, 0.40), main: tone(0.22, 0.84, 0.76), bright: tone(0.58, 1, 0.9), core: tone(0.92, 1, 0.98))
    static let gold = Self(deep: tone(0.7, 0.45, 0.05), main: tone(1, 0.78, 0.2), bright: tone(1, 0.92, 0.55), core: tone(1, 1, 0.85))
    static let shadow = Self(deep: tone(0.2, 0.05, 0.35), main: tone(0.55, 0.3, 0.85), bright: tone(0.78, 0.6, 1), core: tone(0.95, 0.88, 1))
    static let venom = Self(deep: tone(0.32, 0.1, 0.5), main: tone(0.66, 0.36, 0.95), bright: tone(0.86, 0.66, 1), core: tone(0.97, 0.92, 1))
    static let holy = Self(deep: tone(0.85, 0.6, 0.1), main: tone(1, 0.88, 0.45), bright: tone(1, 0.96, 0.75), core: tone(1, 1, 1))
    static let mend = Self(deep: tone(0.1, 0.6, 0.25), main: tone(0.45, 0.95, 0.55), bright: tone(0.75, 1, 0.8), core: tone(1, 1, 1))
    static let rose = Self(deep: tone(0.75, 0.2, 0.55), main: tone(1, 0.5, 0.82), bright: tone(1, 0.78, 0.94), core: tone(1, 0.97, 1))
    static let steel = Self(deep: tone(0.2, 0.35, 0.6), main: tone(0.6, 0.75, 0.95), bright: tone(0.85, 0.92, 1), core: tone(1, 1, 1))
    static let rage = Self(deep: tone(0.6, 0.02, 0.02), main: tone(1, 0.2, 0.12), bright: tone(1, 0.55, 0.35), core: tone(1, 0.9, 0.75))
    static let boost = Self(deep: tone(0.8, 0.35, 0.02), main: tone(1, 0.6, 0.15), bright: tone(1, 0.85, 0.45), core: tone(1, 1, 0.85))
    static let wind = Self(deep: tone(0.25, 0.55, 0.45), main: tone(0.65, 0.95, 0.85), bright: tone(0.88, 1, 0.95), core: tone(1, 1, 1))
    static let amber = Self(deep: tone(0.55, 0.35, 0.12), main: tone(0.95, 0.7, 0.35), bright: tone(1, 0.88, 0.6), core: tone(1, 1, 0.9))
    static let sound = Self(deep: tone(0.75, 0.4, 0.1), main: tone(1, 0.75, 0.4), bright: tone(1, 0.92, 0.75), core: tone(1, 1, 1))

    fileprivate static func tone(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// Every skill's own effect, so no two look alike (each skill has its own `animation` in
/// content/skills.json, and tools/check_content.py keeps them apart): frost that crystallises,
/// bubbles that wobble and pop, a spray of embers, a lobbed gob of mud, a tumbling boulder, a
/// lashing vine, a whirling gold disc, gusts, a roar, webs, three kinds of bite, a heavy smash, an
/// evil eye, a rolling poison fog, a blinding flash, four heals and six buffs. They're drawn in
/// light in their own colours like the elemental spells (ElementEffects.swift). The ones that
/// travel return how long until they land, when BattleScene shows the hits.
extension SkillEffects {
    /// The colour a style casts in (the caster's flash and charge, the glory where it lands), where
    /// it has one of its own rather than its element's.
    static func styleColor(_ style: String) -> UIColor? {
        let light: ElementLight? = switch style {
        case "frost": .frost
        case "bubbles": .bubble
        case "gold_spin": .gold
        case "shadow_bite", "glare": .shadow
        case "venom_bite", "mist": .venom
        case "flash", "bless", "rain": .holy
        case "first_aid", "heart", "paw": .mend
        case "glow": .rose
        case "shield", "ward", "smash": .steel
        case "rage": .rage
        case "boost": .boost
        case "gust": .wind
        case "spur": .amber
        case "roar": .sound
        default: nil
        }
        return light?.main
    }

    /// The mastered finale a style borrows (`ultimateFinale` has the elemental ones).
    static func finale(for style: String) -> String {
        switch style {
        case "frost", "bubbles": "water"
        case "embers": "fire"
        case "mud", "boulder": "stone"
        case "vine": "leaves"
        case "gold_spin", "gust": "whirlwind"
        case "flash": "holy"
        case "first_aid", "heart", "paw", "rain": "heal"
        default: style
        }
    }

    /// A curve from `start` to `end`, bowing up to `lift` points above the higher of the two.
    static func arc(from start: CGPoint, to end: CGPoint, lift: CGFloat) -> CGPath {
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + lift))
        return path.cgPath
    }

    // MARK: - Water and frost

    /// Frost Breath: an icy breath billows from the caster over every target in puffs of pale
    /// light, snowflakes drift down round them, and crystals of ice spring up at their feet and
    /// shatter. Nothing like a bubble.
    @discardableResult
    static func frostBreath(from start: CGPoint?, on targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        let light = ElementLight.frost
        let reach: TimeInterval = 0.35
        for target in targets {
            let from = start ?? target.center + CGVector(dx: -120, dy: 60)
            for index in 0..<(5 + level) {
                let puff = lightBall(light, size: 20 + CGFloat(index) * 3, tint: 0.3, core: false)
                puff.position = from
                puff.alpha = 0
                parent.addChild(puff)
                let drift = SKAction.move(to: target.center + CGVector(dx: .random(in: -16...16), dy: .random(in: -12...12)), duration: reach)
                drift.timingMode = .easeOut
                puff.run(.sequence([
                    .wait(forDuration: Double(index) * 0.03),
                    .fadeIn(withDuration: 0.04),
                    .group([drift, .scale(to: 2, duration: reach), .sequence([.wait(forDuration: reach * 0.6), .fadeOut(withDuration: 0.25)])]),
                    .removeFromParent(),
                ]))
            }
            for index in 0..<(6 + level * 2) {
                let flake = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 9, height: 9))
                flake.color = index % 2 == 0 ? .white : light.bright
                flake.colorBlendFactor = 1
                flake.blendMode = .add
                flake.zPosition = 18_400
                flake.position = target.center + CGVector(dx: .random(in: -40...40), dy: .random(in: 20...60))
                flake.alpha = 0
                parent.addChild(flake)
                let fall = SKAction.moveBy(x: .random(in: -12...12), y: -CGFloat.random(in: 40...70), duration: 0.9)
                flake.run(.sequence([
                    .wait(forDuration: 0.15 + Double(index) * 0.03),
                    .fadeIn(withDuration: 0.1),
                    .group([fall, .rotate(byAngle: .pi, duration: 0.9), .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3)])]),
                    .removeFromParent(),
                ]))
            }
            // Crystals of ice, leaning out round its feet.
            for index in 0..<(4 + level) {
                let side: CGFloat = index % 2 == 0 ? -1 : 1
                let crystal = shard(light, size: CGSize(width: 12, height: .random(in: 26...40)))
                crystal.position = target.position + CGVector(dx: side * CGFloat.random(in: 14...34), dy: CGFloat.random(in: -6...6))
                crystal.zRotation = -side * CGFloat.random(in: 0.15...0.5)
                crystal.zPosition = -crystal.position.y
                crystal.yScale = 0.05
                crystal.alpha = 0
                parent.addChild(crystal)
                let grow = SKAction.scaleY(to: 1, duration: 0.12)
                grow.timingMode = .easeOut
                crystal.run(.sequence([
                    .wait(forDuration: reach + Double(index) * 0.03),
                    .group([.fadeIn(withDuration: 0.05), grow]),
                    .wait(forDuration: 0.35),
                    .group([.fadeOut(withDuration: 0.15), .scale(to: 1.3, duration: 0.15)]),
                    .removeFromParent(),
                ]))
            }
            ring(at: target.position, color: light.bright, size: CGSize(width: 50, height: 18), grow: 2 + 0.2 * CGFloat(level), delay: reach, in: parent)
            sparks(from: target.center, light: light, count: 8 + level * 2, reach: 50, delay: reach + 0.45, in: parent)
            target.sprite.run(.sequence([
                .wait(forDuration: reach),
                .colorize(with: light.bright, colorBlendFactor: 0.7, duration: 0.05),
                .wait(forDuration: 0.35),
                .colorize(withColorBlendFactor: 0, duration: 0.25),
            ]), withKey: "frozen")
        }
        return reach
    }

    /// Bubble: a stream of glinting bubbles wobbles from the caster to the target and pops on it
    /// in rings and droplets.
    @discardableResult
    static func bubbleStream(from start: CGPoint?, to targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard let main = targets.first else { return 0 }
        let light = ElementLight.bubble
        let from = start ?? main.center + CGVector(dx: -120, dy: 60)
        let flight: TimeInterval = 0.45
        for index in 0..<(6 + level * 2) {
            let radius = CGFloat.random(in: 5...9) + CGFloat(level)
            let bubble = SKShapeNode(circleOfRadius: radius)
            bubble.strokeColor = light.bright
            bubble.lineWidth = 1.5
            bubble.glowWidth = 1.5
            bubble.fillColor = light.main.withAlphaComponent(0.18)
            bubble.blendMode = .add
            let glint = SKShapeNode(circleOfRadius: radius * 0.25)
            glint.fillColor = .white
            glint.strokeColor = .clear
            glint.position = CGPoint(x: -radius * 0.35, y: radius * 0.35)
            bubble.addChild(glint)
            bubble.position = from
            bubble.zPosition = 18_300
            bubble.alpha = 0
            parent.addChild(bubble)
            let end = main.center + CGVector(dx: .random(in: -14...14), dy: .random(in: -10...14))
            let wobble = SKAction.sequence([.scaleX(to: 1.15, duration: 0.075), .scaleX(to: 0.9, duration: 0.075)])
            bubble.run(.sequence([
                .wait(forDuration: Double(index) * 0.05),
                .fadeIn(withDuration: 0.05),
                .group([.follow(arc(from: from, to: end, lift: .random(in: -30...40)), asOffset: false, orientToPath: false, duration: flight),
                        .repeat(wobble, count: 3)]),
                .group([.scale(to: 1.8, duration: 0.1), .fadeOut(withDuration: 0.1)]),
                .removeFromParent(),
            ]))
        }
        for target in targets {
            for index in 0..<2 {
                ring(at: target.center, color: light.bright, size: CGSize(width: 26, height: 26), grow: 2.2 + CGFloat(index) * 0.6,
                     delay: flight + Double(index) * 0.12, in: parent)
            }
            sparks(from: target.center, light: light, count: 6 + level * 2, reach: 36, delay: flight + 0.05, in: parent)
        }
        return flight + 0.05
    }

    // MARK: - Fire, earth, wood

    /// Ember: a spray of small embers flies from the caster in loose arcs and peppers the target
    /// with sparks: many quick little lights where a Fire Bolt is one big ball.
    @discardableResult
    static func emberSpray(from start: CGPoint?, to targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard let main = targets.first else { return 0 }
        let light = ElementLight.fire
        let from = start ?? main.center + CGVector(dx: -120, dy: 60)
        let flight: TimeInterval = 0.28
        for index in 0..<(5 + level * 2) {
            let ember = lightBall(light, size: CGFloat.random(in: 10...15) + CGFloat(level), tint: 0.4)
            ember.position = from
            ember.zPosition = 18_200
            ember.alpha = 0
            parent.addChild(ember)
            let end = main.center + CGVector(dx: .random(in: -18...18), dy: .random(in: -14...16))
            let delay = Double(index) * 0.035
            ember.run(.sequence([
                .wait(forDuration: delay),
                .fadeIn(withDuration: 0.03),
                .follow(arc(from: from, to: end, lift: .random(in: 10...50)), asOffset: false, orientToPath: false, duration: flight),
                .group([.scale(to: 1.8, duration: 0.08), .fadeOut(withDuration: 0.12)]),
                .removeFromParent(),
            ]))
            sparks(from: end, light: light, count: 3, reach: 20, delay: delay + flight, in: parent)
        }
        for target in targets {
            groundGlow(at: target.position, light: light, width: 60 + CGFloat(level) * 6, appear: flight, hold: 0.3, in: parent)
        }
        return flight + 0.05
    }

    /// Mud Shot: a gob of mud is lobbed in an arc and splats on the target: brown splotches fly up
    /// and drop, and a puddle spreads at its feet.
    @discardableResult
    static func mudShot(from start: CGPoint?, to targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard let main = targets.first else { return 0 }
        let mud = UIColor(red: 0.42, green: 0.27, blue: 0.12, alpha: 1)
        let wet = UIColor(red: 0.62, green: 0.44, blue: 0.24, alpha: 1)
        let from = start ?? main.center + CGVector(dx: -120, dy: 60)
        let flight: TimeInterval = 0.4
        let gob = shade(mud, size: CGSize(width: 26 + CGFloat(level) * 3, height: 22 + CGFloat(level) * 3), alpha: 1)
        gob.zPosition = 18_200
        let shine = glowSprite(wet, size: CGSize(width: 12, height: 8))
        shine.position = CGPoint(x: -4, y: 4)
        shine.zPosition = 0.1
        gob.addChild(shine)
        gob.position = from
        parent.addChild(gob)
        gob.run(.sequence([
            .group([.follow(arc(from: from, to: main.center, lift: 90), asOffset: false, orientToPath: false, duration: flight),
                    .rotate(byAngle: -.pi * 2, duration: flight)]),
            .removeFromParent(),
        ]))
        for target in targets {
            for index in 0..<(8 + level * 2) {
                let blob = shade(index % 3 == 0 ? wet : mud, size: CGSize(width: .random(in: 6...11), height: .random(in: 6...10)), alpha: 1)
                blob.position = target.center
                blob.zPosition = 18_250
                blob.alpha = 0
                parent.addChild(blob)
                let side = CGFloat.random(in: -1...1) * 50
                let up = SKAction.moveBy(x: side * 0.6, y: .random(in: 20...46), duration: 0.18)
                up.timingMode = .easeOut
                let down = SKAction.moveBy(x: side * 0.4, y: -CGFloat.random(in: 50...80), duration: 0.3)
                down.timingMode = .easeIn
                blob.run(.sequence([
                    .wait(forDuration: flight), .fadeIn(withDuration: 0.02), up,
                    .group([down, .sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.15)])]),
                    .removeFromParent(),
                ]))
            }
            let puddle = shade(mud, size: CGSize(width: 70 + CGFloat(level) * 8, height: 20), alpha: 0.75)
            puddle.position = target.position
            puddle.zPosition = -8_600
            puddle.setScale(0.2)
            puddle.alpha = 0
            parent.addChild(puddle)
            puddle.run(.sequence([
                .wait(forDuration: flight), .fadeAlpha(to: 0.75, duration: 0.05), .scale(to: 1, duration: 0.2),
                .wait(forDuration: 0.5), .fadeOut(withDuration: 0.4), .removeFromParent(),
            ]))
            target.sprite.run(.sequence([
                .wait(forDuration: flight),
                .colorize(with: mud, colorBlendFactor: 0.6, duration: 0.04),
                .wait(forDuration: 0.25),
                .colorize(withColorBlendFactor: 0, duration: 0.3),
            ]), withKey: "mud")
        }
        return flight
    }

    /// Rock Throw: a boulder tumbles through the air in a high arc and crashes down on the target
    /// in a burst of dust and flying chips.
    @discardableResult
    static func rockThrow(from start: CGPoint?, to targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard let main = targets.first else { return 0 }
        let from = start ?? main.center + CGVector(dx: -120, dy: 60)
        let flight: TimeInterval = 0.45
        let stone = UIColor(red: 0.52, green: 0.47, blue: 0.42, alpha: 1)
        let dust = UIColor(red: 0.62, green: 0.56, blue: 0.48, alpha: 1)
        let rock = SKShapeNode(path: boulderPath(radius: 14 + CGFloat(level) * 2))
        rock.fillColor = stone
        rock.strokeColor = UIColor(red: 0.24, green: 0.2, blue: 0.18, alpha: 1)
        rock.lineWidth = 2
        let lit = SKShapeNode(path: boulderPath(radius: 7 + CGFloat(level)))
        lit.fillColor = UIColor(red: 0.72, green: 0.67, blue: 0.6, alpha: 1)
        lit.strokeColor = .clear
        lit.position = CGPoint(x: -4, y: 4)
        rock.addChild(lit)
        rock.position = from
        rock.zPosition = 18_300
        parent.addChild(rock)
        let fall = SKAction.follow(arc(from: from, to: main.center, lift: 150), asOffset: false, orientToPath: false, duration: flight)
        fall.timingMode = .easeIn
        rock.run(.sequence([.group([fall, .rotate(byAngle: .pi * 3, duration: flight)]), .removeFromParent()]))
        for target in targets {
            for _ in 0..<(5 + level) {
                let puff = shade(dust, size: CGSize(width: 30, height: 24), alpha: 0.7)
                puff.position = target.position + CGVector(dx: .random(in: -24...24), dy: .random(in: -4...10))
                puff.zPosition = 18_200
                puff.alpha = 0
                puff.setScale(0.5)
                parent.addChild(puff)
                puff.run(.sequence([
                    .wait(forDuration: flight), .fadeAlpha(to: 0.7, duration: 0.04),
                    .group([.scale(to: 1.8, duration: 0.6), .moveBy(x: .random(in: -16...16), y: 18, duration: 0.6), .fadeOut(withDuration: 0.6)]),
                    .removeFromParent(),
                ]))
            }
            for _ in 0..<(6 + level * 2) {
                let chip = SKSpriteNode(color: Bool.random() ? stone : dust, size: CGSize(width: 4, height: 4))
                chip.position = target.center
                chip.zPosition = 18_350
                chip.alpha = 0
                parent.addChild(chip)
                let side = CGFloat.random(in: -1...1) * 60
                let up = SKAction.moveBy(x: side * 0.6, y: .random(in: 24...50), duration: 0.2)
                up.timingMode = .easeOut
                let down = SKAction.moveBy(x: side * 0.4, y: -CGFloat.random(in: 60...90), duration: 0.3)
                down.timingMode = .easeIn
                chip.run(.sequence([
                    .wait(forDuration: flight), .fadeIn(withDuration: 0.02), up,
                    .group([down, .rotate(byAngle: .pi * 2, duration: 0.3)]),
                    .fadeOut(withDuration: 0.1), .removeFromParent(),
                ]))
            }
            ring(at: target.position, color: dust, size: CGSize(width: 50, height: 18), grow: 2 + 0.2 * CGFloat(level), delay: flight, in: parent)
        }
        return flight
    }

    /// An irregular boulder's outline, a little squat.
    private static func boulderPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let bumps: [CGFloat] = [1, 0.86, 0.95, 0.8, 1, 0.9, 0.82, 0.96]
        for (index, bump) in bumps.enumerated() {
            let angle = CGFloat(index) / CGFloat(bumps.count) * 2 * .pi
            let point = CGPoint(x: cos(angle) * radius * bump, y: sin(angle) * radius * bump * 0.85)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Vine Whip: a vine lashes out from the caster in a curve and cracks across the target, leaves
    /// flying where it strikes.
    @discardableResult
    static func vineWhip(from start: CGPoint?, to targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard let main = targets.first else { return 0 }
        let light = ElementLight.wood
        let from = start ?? main.center + CGVector(dx: -120, dy: 60)
        let reach = main.center - from
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: reach.dx, y: reach.dy),
                          controlPoint: CGPoint(x: reach.dx * 0.5 - reach.dy * 0.35, y: reach.dy * 0.5 + reach.dx * 0.35))
        let vine = SKShapeNode(path: path.cgPath)
        vine.strokeColor = UIColor(red: 0.3, green: 0.72, blue: 0.24, alpha: 1)
        vine.lineWidth = 4 + CGFloat(level) * 0.5
        vine.glowWidth = 2
        vine.lineCap = .round
        vine.fillColor = .clear
        vine.position = from
        vine.zPosition = 18_300
        vine.setScale(0.05)
        parent.addChild(vine)
        let lash = SKAction.scale(to: 1, duration: 0.14)
        lash.timingMode = .easeOut
        vine.run(.sequence([lash, .wait(forDuration: 0.12), .group([.scale(to: 0.05, duration: 0.16), .fadeOut(withDuration: 0.16)]), .removeFromParent()]))
        for target in targets {
            let crack = lightBall(light, size: 36 + CGFloat(level) * 6, tint: 0.4)
            crack.position = target.center
            crack.setScale(0.3)
            crack.alpha = 0
            parent.addChild(crack)
            crack.run(.sequence([
                .wait(forDuration: 0.14), .fadeIn(withDuration: 0.02),
                .group([.scale(to: 1.2, duration: 0.2), .fadeOut(withDuration: 0.25)]),
                .removeFromParent(),
            ]))
            for index in 0..<(6 + level * 2) {
                let leaf = streak(light, color: index % 3 == 0 ? light.core : light.bright, size: CGSize(width: 12, height: 5), tint: 0.5)
                leaf.position = target.center
                leaf.zRotation = .random(in: 0...(2 * .pi))
                leaf.alpha = 0
                parent.addChild(leaf)
                let fly = SKAction.moveBy(x: .random(in: -50...50), y: .random(in: -10...50), duration: 0.45)
                fly.timingMode = .easeOut
                leaf.run(.sequence([
                    .wait(forDuration: 0.14), .fadeIn(withDuration: 0.02),
                    .group([fly, .rotate(byAngle: .random(in: -3...3), duration: 0.45), .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.2)])]),
                    .removeFromParent(),
                ]))
            }
        }
        return 0.14
    }

    // MARK: - Metal, wind, sound, webs

    /// Golden Spin: a whirling disc of gold light flies from the caster and saws into the target,
    /// throwing off glittering stars.
    @discardableResult
    static func goldenSpin(from start: CGPoint?, to targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard let main = targets.first else { return 0 }
        let light = ElementLight.gold
        let from = start ?? main.center + CGVector(dx: -120, dy: 60)
        let flight: TimeInterval = 0.3
        let disc = SKNode()
        disc.position = from
        disc.zPosition = 18_300
        let glow = lightBall(light, size: 34 + CGFloat(level) * 4, tint: 0.4)
        glow.zPosition = 0
        disc.addChild(glow)
        // The spinning part, in a child so the disc stays tilted as it turns.
        let spinner = SKNode()
        spinner.zPosition = 0.5
        disc.addChild(spinner)
        let rim = SKShapeNode(circleOfRadius: 12 + CGFloat(level))
        rim.strokeColor = light.bright
        rim.lineWidth = 3
        rim.glowWidth = 3
        rim.fillColor = .clear
        rim.blendMode = .add
        spinner.addChild(rim)
        for index in 0..<4 {
            let spoke = glowSprite(light.core, size: CGSize(width: 22 + CGFloat(level) * 2, height: 3))
            spoke.zRotation = CGFloat(index) * .pi / 4
            spoke.zPosition = 0.1
            spinner.addChild(spoke)
        }
        spinner.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.18)))
        disc.yScale = 0.65
        parent.addChild(disc)
        let travel = SKAction.move(to: main.center, duration: flight)
        travel.timingMode = .easeIn
        disc.run(.sequence([travel, .wait(forDuration: 0.18), .group([.scale(to: 0.2, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
        for target in targets {
            sparks(from: target.center, light: light, count: 8 + level * 2, reach: 44, delay: flight, in: parent)
            for index in 0..<(5 + level) {
                let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: 11, height: 11))
                star.color = index % 2 == 0 ? light.core : light.main
                star.colorBlendFactor = 1
                star.blendMode = .add
                star.zPosition = 18_500
                star.position = target.center
                star.alpha = 0
                parent.addChild(star)
                let fly = SKAction.moveBy(x: .random(in: -40...40), y: .random(in: 10...50), duration: 0.5)
                fly.timingMode = .easeOut
                star.run(.sequence([
                    .wait(forDuration: flight + 0.05), .fadeIn(withDuration: 0.03),
                    .group([fly, .rotate(byAngle: .pi, duration: 0.5), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.2)])]),
                    .removeFromParent(),
                ]))
            }
        }
        return flight
    }

    /// Gust: streaks of wind sweep across the field from the caster's side through every target,
    /// each one buffeted back a step.
    @discardableResult
    static func gust(from start: CGPoint?, on targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        guard !targets.isEmpty else { return 0 }
        let light = ElementLight.wind
        let middle = CGPoint(x: targets.map(\.center.x).reduce(0, +) / CGFloat(targets.count),
                             y: targets.map(\.center.y).reduce(0, +) / CGFloat(targets.count))
        let from = start ?? middle + CGVector(dx: -160, dy: 60)
        let way = (middle - from).normalized
        let across = CGVector(dx: -way.dy, dy: way.dx)
        let span = from.distance(to: middle) + 140
        for index in 0..<(10 + level * 3) {
            let wisp = streak(light, size: CGSize(width: .random(in: 40...80), height: .random(in: 3...6)), tint: 0.3)
            wisp.position = from + across * CGFloat.random(in: -70...70) + way * CGFloat.random(in: -40...0)
            wisp.zRotation = atan2(way.dy, way.dx)
            wisp.alpha = 0
            parent.addChild(wisp)
            let blow = SKAction.move(by: way * span, duration: 0.4)
            blow.timingMode = .easeIn
            wisp.run(.sequence([
                .wait(forDuration: Double(index) * 0.025), .fadeIn(withDuration: 0.05),
                .group([blow, .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.15)])]),
                .removeFromParent(),
            ]))
        }
        let reach: TimeInterval = 0.3
        let push = way * 10
        for target in targets {
            for index in 0..<2 {
                ring(at: target.center, color: light.bright, size: CGSize(width: 30, height: 14), grow: 2 + CGFloat(index) * 0.5,
                     delay: reach + Double(index) * 0.08, in: parent)
            }
            target.sprite.run(.sequence([.wait(forDuration: reach), .moveBy(x: push.dx, y: push.dy, duration: 0.08),
                                         .moveBy(x: -push.dx, y: -push.dy, duration: 0.2)]))
        }
        return reach
    }

    /// Roar: shockwaves of sound burst from the caster across the field, and every target flinches
    /// as one passes.
    @discardableResult
    static func roar(from caster: BattleActor?, on targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        let light = ElementLight.sound
        let origin = caster?.center ?? targets.first?.center ?? .zero
        caster?.sprite.run(.sequence([.scale(by: 1.15, duration: 0.1), .scale(by: 1 / 1.15, duration: 0.2)]))
        for index in 0..<(3 + level / 2) {
            let wave = SKShapeNode(ellipseOf: CGSize(width: 60, height: 40))
            wave.strokeColor = index % 2 == 0 ? light.bright : light.main
            wave.lineWidth = 3
            wave.glowWidth = 4
            wave.fillColor = .clear
            wave.blendMode = .add
            wave.position = origin
            wave.zPosition = 18_300
            wave.alpha = 0
            parent.addChild(wave)
            let spread = SKAction.scale(to: 7 + CGFloat(level), duration: 0.6)
            spread.timingMode = .easeOut
            wave.run(.sequence([
                .wait(forDuration: Double(index) * 0.1), .fadeIn(withDuration: 0.03),
                .group([spread, .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.35)])]),
                .removeFromParent(),
            ]))
        }
        for target in targets {
            let delay = min(0.35, Double(origin.distance(to: target.center)) / 900)
            let shudder = SKAction.sequence([.moveBy(x: 3, y: 0, duration: 0.04), .moveBy(x: -3, y: 0, duration: 0.04)])
            target.sprite.run(.sequence([.wait(forDuration: delay), .repeat(shudder, count: 3)]))
        }
        return 0.25
    }

    /// Web Shot: sticky webs fly at the targets and spread over them in silvery strands.
    @discardableResult
    static func webShot(from start: CGPoint?, on targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        let flight: TimeInterval = 0.28
        for target in targets {
            let web = SKShapeNode(path: webPath(radius: 22 + CGFloat(level) * 2))
            web.strokeColor = UIColor(red: 0.92, green: 0.92, blue: 1, alpha: 0.95)
            web.lineWidth = 1.2
            web.glowWidth = 1
            web.fillColor = UIColor(red: 0.55, green: 0.45, blue: 0.75, alpha: 0.12)
            web.position = start ?? target.center + CGVector(dx: -120, dy: 60)
            web.zPosition = 18_400
            web.setScale(0.2)
            parent.addChild(web)
            let fly = SKAction.move(to: target.center, duration: flight)
            fly.timingMode = .easeOut
            web.run(.sequence([
                .group([fly, .scale(to: 1, duration: flight), .rotate(byAngle: .pi, duration: flight)]),
                .scaleX(to: 1.15, duration: 0.08),
                .wait(forDuration: 0.45),
                .group([.fadeOut(withDuration: 0.3), .scale(to: 1.3, duration: 0.3)]),
                .removeFromParent(),
            ]))
        }
        return flight
    }

    /// A spider's web: spokes and three rings round them.
    private static func webPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let spokes = 8
        for index in 0..<spokes {
            let angle = CGFloat(index) / CGFloat(spokes) * 2 * .pi
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
        }
        for band in 1...3 {
            let r = radius * CGFloat(band) / 3
            for index in 0...spokes {
                let angle = CGFloat(index % spokes) / CGFloat(spokes) * 2 * .pi
                let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path
    }

    // MARK: - Close-up blows

    /// Bash: a heavy blow from above: a shaft of light slams down on the target, the ground
    /// cracks in a ring and dust kicks up.
    static func smash(on target: BattleActor, level: Int, in parent: SKNode) {
        let light = ElementLight.steel
        let shaft = glowSprite(light.bright, size: CGSize(width: 16 + CGFloat(level) * 2, height: 80))
        shaft.anchorPoint = CGPoint(x: 0.5, y: 0)
        shaft.position = target.top + CGVector(dx: 0, dy: 60)
        shaft.alpha = 0
        parent.addChild(shaft)
        let slam = SKAction.move(to: target.center, duration: 0.07)
        slam.timingMode = .easeIn
        shaft.run(.sequence([.fadeIn(withDuration: 0.02), slam, .group([.scaleY(to: 0.2, duration: 0.12), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
        let bloom = lightBall(light, size: 40 + CGFloat(level) * 6, tint: 0.3)
        bloom.position = target.center
        bloom.setScale(0.3)
        bloom.alpha = 0
        parent.addChild(bloom)
        bloom.run(.sequence([
            .wait(forDuration: 0.07), .fadeIn(withDuration: 0.02),
            .group([.scale(to: 1.2, duration: 0.18), .fadeOut(withDuration: 0.22)]),
            .removeFromParent(),
        ]))
        ring(at: target.position, color: light.main, size: CGSize(width: 46, height: 16), grow: 2 + 0.25 * CGFloat(level), delay: 0.07, in: parent)
        let dust = UIColor(red: 0.62, green: 0.56, blue: 0.48, alpha: 1)
        for _ in 0..<(4 + level) {
            let puff = shade(dust, size: CGSize(width: 22, height: 16), alpha: 0.6)
            puff.position = target.position + CGVector(dx: .random(in: -26...26), dy: .random(in: -4...6))
            puff.zPosition = 18_200
            puff.alpha = 0
            parent.addChild(puff)
            puff.run(.sequence([
                .wait(forDuration: 0.08), .fadeAlpha(to: 0.6, duration: 0.03),
                .group([.scale(to: 1.8, duration: 0.45), .moveBy(x: .random(in: -14...14), y: 12, duration: 0.45), .fadeOut(withDuration: 0.45)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Shadow Bite: jaws of dark light snap shut on the target and shadow bursts from the bite.
    static func shadowBite(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.shadow
        for side in [-1.0, 1.0] {
            let jaw = SKShapeNode(path: UIBezierPath(arcCenter: .zero, radius: 20, startAngle: 0.3, endAngle: .pi - 0.3, clockwise: true).cgPath)
            jaw.strokeColor = light.bright
            jaw.lineWidth = 5
            jaw.glowWidth = 4
            jaw.blendMode = .add
            jaw.position = target.center + CGVector(dx: 0, dy: 18 * side)
            jaw.yScale = side
            jaw.zPosition = 18_400
            parent.addChild(jaw)
            jaw.run(.sequence([.moveBy(x: 0, y: -14 * side, duration: 0.08), .fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        for _ in 0..<7 {
            let wisp = shade(light.deep, size: CGSize(width: 22, height: 22), alpha: 0.75)
            wisp.position = target.center + CGVector(dx: .random(in: -14...14), dy: .random(in: -10...10))
            wisp.zPosition = 18_350
            parent.addChild(wisp)
            wisp.run(.sequence([
                .wait(forDuration: 0.08),
                .group([.scale(to: 2, duration: 0.5), .moveBy(x: .random(in: -20...20), y: .random(in: 0...24), duration: 0.5), .fadeOut(withDuration: 0.5)]),
                .removeFromParent(),
            ]))
        }
        sparks(from: target.center, light: light, count: 8, reach: 40, delay: 0.08, in: parent)
        target.sprite.flash(light.main)
    }

    /// Venom Bite: purple fangs sink in and drops of venom drip from the wound.
    static func venomBite(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.venom
        for side in [-1.0, 1.0] {
            let fang = SKShapeNode(path: fangPath())
            fang.fillColor = light.bright
            fang.strokeColor = light.deep
            fang.lineWidth = 1.5
            fang.glowWidth = 2
            fang.position = target.center + CGVector(dx: 9 * side, dy: 30)
            fang.zPosition = 18_400
            parent.addChild(fang)
            fang.run(.sequence([.moveBy(x: 0, y: -22, duration: 0.07), .wait(forDuration: 0.1), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
        for index in 0..<6 {
            let drop = glowSprite(index % 2 == 0 ? light.main : light.bright, size: CGSize(width: 6, height: 8))
            drop.position = target.center + CGVector(dx: .random(in: -10...10), dy: .random(in: -4...6))
            drop.alpha = 0
            parent.addChild(drop)
            let fall = SKAction.moveBy(x: 0, y: -CGFloat.random(in: 30...50), duration: 0.45)
            fall.timingMode = .easeIn
            drop.run(.sequence([
                .wait(forDuration: 0.12 + Double(index) * 0.06), .fadeIn(withDuration: 0.03),
                .group([fall, .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.15)])]),
                .removeFromParent(),
            ]))
        }
        ring(at: target.position, color: light.main, size: CGSize(width: 30, height: 12), grow: 1.8, delay: 0.3, in: parent)
        target.sprite.flash(light.main)
    }

    /// A fang, its point down.
    private static func fangPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -5, y: 8))
        path.addQuadCurve(to: CGPoint(x: 0, y: -10), control: CGPoint(x: -4, y: -2))
        path.addQuadCurve(to: CGPoint(x: 5, y: 8), control: CGPoint(x: 4, y: -2))
        path.closeSubpath()
        return path
    }

    // MARK: - Dark arts and light

    /// Evil Eye: a great eye of violet light opens over the target, glares, and beams its curse
    /// down into it.
    static func evilEye(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.shadow
        let eye = SKNode()
        eye.position = target.top + CGVector(dx: 0, dy: 44)
        eye.zPosition = 18_600
        let lid = SKShapeNode(path: eyePath(width: 56, height: 26))
        lid.strokeColor = light.bright
        lid.lineWidth = 2.5
        lid.glowWidth = 3
        lid.fillColor = UIColor(red: 0.12, green: 0.04, blue: 0.2, alpha: 0.85)
        eye.addChild(lid)
        let iris = lightBall(light, size: 22, tint: 0.5)
        iris.zPosition = 0.5
        eye.addChild(iris)
        let slit = SKSpriteNode(color: UIColor(red: 1, green: 0.3, blue: 0.45, alpha: 1), size: CGSize(width: 3, height: 12))
        slit.zPosition = 0.8
        eye.addChild(slit)
        eye.yScale = 0.05
        eye.alpha = 0
        parent.addChild(eye)
        eye.run(.sequence([
            .group([.fadeIn(withDuration: 0.08), .scaleY(to: 1, duration: 0.14)]),
            .wait(forDuration: 0.4),
            .scaleY(to: 0.05, duration: 0.1),
            .fadeOut(withDuration: 0.1),
            .removeFromParent(),
        ]))
        for index in 0..<3 {
            let beam = glowSprite(light.main, size: CGSize(width: 6, height: 50))
            beam.anchorPoint = CGPoint(x: 0.5, y: 1)
            beam.position = eye.position + CGVector(dx: CGFloat(index - 1) * 10, dy: -10)
            beam.zRotation = CGFloat(index - 1) * 0.15
            beam.yScale = 0.05
            beam.alpha = 0
            parent.addChild(beam)
            beam.run(.sequence([
                .wait(forDuration: 0.25 + Double(index) * 0.04), .fadeIn(withDuration: 0.02), .scaleY(to: 1, duration: 0.1),
                .fadeOut(withDuration: 0.25), .removeFromParent(),
            ]))
        }
        target.sprite.run(.sequence([
            .wait(forDuration: 0.3),
            .colorize(with: light.main, colorBlendFactor: 0.8, duration: 0.04),
            .colorize(withColorBlendFactor: 0, duration: 0.3),
        ]), withKey: "glared")
    }

    /// An eye's outline: two arcs meeting at the corners.
    private static func eyePath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: 0))
        path.addQuadCurve(to: CGPoint(x: width / 2, y: 0), control: CGPoint(x: 0, y: height))
        path.addQuadCurve(to: CGPoint(x: -width / 2, y: 0), control: CGPoint(x: 0, y: -height))
        path.closeSubpath()
        return path
    }

    /// Poison Mist: a choking purple fog rolls across every target, bubbling as it goes.
    static func poisonMist(on targets: [BattleActor], in parent: SKNode) {
        guard !targets.isEmpty else { return }
        let light = ElementLight.venom
        let xs = targets.map(\.center.x)
        let ys = targets.map(\.center.y)
        let left = (xs.min() ?? 0) - 80
        let width = (xs.max() ?? 0) - (xs.min() ?? 0) + 160
        let middleY = ys.reduce(0, +) / CGFloat(ys.count)
        for index in 0..<14 {
            let puff = shade(index % 3 == 0 ? light.main : light.deep, size: CGSize(width: .random(in: 60...100), height: .random(in: 40...60)), alpha: 0.45)
            puff.position = CGPoint(x: left + CGFloat.random(in: -40...0), y: middleY + CGFloat.random(in: -50...50))
            puff.zPosition = 18_400
            puff.alpha = 0
            parent.addChild(puff)
            let roll = SKAction.moveBy(x: width * CGFloat.random(in: 0.7...1), y: .random(in: -10...10), duration: 0.9)
            roll.timingMode = .easeOut
            puff.run(.sequence([
                .wait(forDuration: Double(index) * 0.03), .fadeAlpha(to: 0.45, duration: 0.15),
                .group([roll, .scale(to: 1.4, duration: 0.9), .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
                .removeFromParent(),
            ]))
        }
        for target in targets {
            for index in 0..<5 {
                let bubble = glowSprite(index % 2 == 0 ? light.bright : poisonLilac, size: CGSize(width: 7, height: 7))
                bubble.position = target.position + CGVector(dx: .random(in: -16...16), dy: .random(in: 4...30))
                bubble.alpha = 0
                parent.addChild(bubble)
                let pop = SKAction.group([.scale(to: 1.6, duration: 0.15), .fadeOut(withDuration: 0.15)])
                bubble.run(.sequence([
                    .wait(forDuration: 0.35 + Double(index) * 0.06), .fadeIn(withDuration: 0.05),
                    .group([.moveBy(x: 0, y: 28, duration: 0.5), .sequence([.wait(forDuration: 0.35), pop])]),
                    .removeFromParent(),
                ]))
            }
            target.sprite.run(.sequence([
                .wait(forDuration: 0.35),
                .colorize(with: light.main, colorBlendFactor: 0.6, duration: 0.05),
                .colorize(withColorBlendFactor: 0, duration: 0.35),
            ]), withKey: "fogged")
        }
    }

    /// Flash: a blinding star of light bursts on the target, its rays stabbing out.
    static func flashBurst(on target: BattleActor, level: Int, in parent: SKNode) {
        let light = ElementLight.holy
        let side = 60 + CGFloat(level) * 10
        let star = SKSpriteNode(texture: SoftTextures.star, size: CGSize(width: side, height: side))
        star.color = light.core
        star.colorBlendFactor = 1
        star.blendMode = .add
        star.position = target.center
        star.zPosition = 18_600
        star.setScale(0.2)
        parent.addChild(star)
        star.run(.sequence([
            .group([.scale(to: 1.6, duration: 0.15), .rotate(byAngle: .pi / 4, duration: 0.3)]),
            .group([.scale(to: 2, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
        let bloom = lightBall(light, size: 50 + CGFloat(level) * 10, tint: 0.3)
        bloom.position = target.center
        bloom.setScale(0.3)
        parent.addChild(bloom)
        bloom.run(.sequence([.scale(to: 1.2, duration: 0.14), .group([.scale(to: 1.5, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        rays(at: target.center, color: light.bright, count: 10, length: 70 + CGFloat(level) * 10, width: 5, z: 18_550, in: parent)
    }

    // MARK: - Heals

    /// First Aid: a white cross of light rises from the patient in a soft green glow.
    static func firstAid(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.mend
        let cross = SKNode()
        cross.position = target.center
        cross.zPosition = 18_600
        let halo = lightBall(light, size: 46, tint: 0.3, core: false)
        halo.zPosition = 0
        cross.addChild(halo)
        for size in [CGSize(width: 8, height: 26), CGSize(width: 26, height: 8)] {
            let bar = SKShapeNode(rectOf: size, cornerRadius: 3)
            bar.fillColor = .white
            bar.strokeColor = UIColor(red: 0.95, green: 0.35, blue: 0.4, alpha: 1)
            bar.lineWidth = 1.5
            bar.glowWidth = 2
            bar.zPosition = 0.5
            cross.addChild(bar)
        }
        cross.setScale(0.5)
        cross.alpha = 0
        parent.addChild(cross)
        cross.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), .scale(to: 1, duration: 0.15)]),
            .group([.moveBy(x: 0, y: 36, duration: 0.6), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent(),
        ]))
        sparkles(on: target, color: light.bright, level: 1, in: parent)
    }

    /// Recovery: a heart of green light swells on the patient, beats twice and rises away in rings.
    static func healingHeart(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.mend
        let heart = SKShapeNode(path: heartPath(size: 30))
        heart.fillColor = light.main.withAlphaComponent(0.85)
        heart.strokeColor = light.bright
        heart.lineWidth = 2
        heart.glowWidth = 4
        heart.blendMode = .add
        heart.position = target.center
        heart.zPosition = 18_600
        heart.setScale(0.3)
        parent.addChild(heart)
        let beat = SKAction.sequence([.scale(to: 1.15, duration: 0.1), .scale(to: 0.95, duration: 0.1)])
        heart.run(.sequence([
            .scale(to: 1, duration: 0.15), beat, beat,
            .group([.moveBy(x: 0, y: 30, duration: 0.4), .fadeOut(withDuration: 0.4)]),
            .removeFromParent(),
        ]))
        for index in 0..<2 {
            ring(at: target.center, color: light.bright, size: CGSize(width: 30, height: 30), grow: 2.4, delay: 0.25 + Double(index) * 0.2, in: parent)
        }
    }

    /// A heart `size` points across, its point down.
    private static func heartPath(size: CGFloat) -> CGPath {
        let s = size / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -s))
        path.addCurve(to: CGPoint(x: -s, y: s * 0.35), control1: CGPoint(x: -s * 0.4, y: -s * 0.55), control2: CGPoint(x: -s, y: -s * 0.1))
        path.addArc(center: CGPoint(x: -s * 0.5, y: s * 0.35), radius: s * 0.5, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addArc(center: CGPoint(x: s * 0.5, y: s * 0.35), radius: s * 0.5, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addCurve(to: CGPoint(x: 0, y: -s), control1: CGPoint(x: s, y: -s * 0.1), control2: CGPoint(x: s * 0.4, y: -s * 0.55))
        path.closeSubpath()
        return path
    }

    /// Mend Beast: paw prints of green light pad up round the patient and fade into it.
    static func pawPrints(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.mend
        let spots = [CGVector(dx: -26, dy: 0), CGVector(dx: -10, dy: 22), CGVector(dx: 12, dy: 6), CGVector(dx: 26, dy: 28)]
        let toes = [CGPoint(x: -7, y: 8), CGPoint(x: -2.5, y: 11), CGPoint(x: 2.5, y: 11), CGPoint(x: 7, y: 8)]
        for (index, spot) in spots.enumerated() {
            let paw = SKNode()
            paw.position = target.position + spot
            paw.zPosition = 18_600
            let pad = glowSprite(light.main, size: CGSize(width: 14, height: 12))
            pad.zPosition = 0
            paw.addChild(pad)
            for toe in toes {
                let bean = glowSprite(light.bright, size: CGSize(width: 6, height: 6))
                bean.position = toe
                bean.zPosition = 0.1
                paw.addChild(bean)
            }
            paw.alpha = 0
            parent.addChild(paw)
            paw.run(.sequence([
                .wait(forDuration: Double(index) * 0.1), .fadeIn(withDuration: 0.06), .wait(forDuration: 0.25),
                .group([.move(to: target.center, duration: 0.3), .scale(to: 0.4, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                .removeFromParent(),
            ]))
        }
        let glow = lightBall(light, size: 50, tint: 0.3, core: false)
        glow.position = target.center
        glow.alpha = 0
        parent.addChild(glow)
        glow.run(.sequence([.wait(forDuration: 0.5), .fadeIn(withDuration: 0.1), .group([.scale(to: 1.4, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
    }

    /// Blessing: a soft rain of golden light falls over the whole party and pools at their feet.
    static func lightRain(on targets: [BattleActor], level: Int, in parent: SKNode) {
        let light = ElementLight.holy
        for target in targets {
            for index in 0..<(8 + level * 2) {
                let drop = glowSprite(index % 3 == 0 ? light.core : light.bright, size: CGSize(width: 3, height: 14))
                drop.position = target.center + CGVector(dx: .random(in: -30...30), dy: .random(in: 70...120))
                drop.alpha = 0
                parent.addChild(drop)
                let fall = SKAction.moveBy(x: 0, y: -CGFloat.random(in: 80...120), duration: 0.4)
                fall.timingMode = .easeIn
                drop.run(.sequence([
                    .wait(forDuration: Double(index) * 0.035), .fadeIn(withDuration: 0.05),
                    .group([fall, .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.1)])]),
                    .removeFromParent(),
                ]))
            }
            groundGlow(at: target.position, light: .mend, width: 60, appear: 0.3, hold: 0.4, in: parent)
        }
    }

    // MARK: - Buffs

    /// A buff's own look on everyone it raises (`animation` in content/skills.json): Bless's pillar
    /// of light, Protection's shield, Holy Glow's orb, Guardianship's dome, Animal Training's paw
    /// prints, Boost's arrows, Berserk's flames. What it raised shows in the events after it.
    /// Returns how long before those should show.
    @discardableResult
    static func buff(_ style: String, on targets: [BattleActor], level: Int, in parent: SKNode) -> TimeInterval {
        switch style {
        case "shield":
            for target in targets { protectionShield(on: target, in: parent) }
            return 0.35
        case "glow":
            for target in targets { holyGlow(on: target, in: parent) }
            return 0.45
        case "ward":
            guardianWard(over: targets, in: parent)
            return 0.45
        case "spur":
            for target in targets { spur(on: target, in: parent) }
            return 0.4
        case "boost":
            for target in targets { boostArrows(on: target, in: parent) }
            return 0.35
        case "rage":
            for target in targets { rage(on: target, in: parent) }
            return 0.4
        default:
            // Bless: a pillar of light, and a shield.
            for target in targets {
                lightPillar(on: target, level: level, in: parent)
                shield(on: target, in: parent)
            }
            return 0.4
        }
    }

    /// Protection: a tall shield of steel-blue light forms in front of the ally, flashes, and
    /// settles into them.
    private static func protectionShield(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.steel
        let plate = SKShapeNode(path: kiteShieldPath(width: 40, height: 52))
        plate.fillColor = light.main.withAlphaComponent(0.25)
        plate.strokeColor = light.bright
        plate.lineWidth = 3
        plate.glowWidth = 4
        plate.blendMode = .add
        plate.position = target.center + CGVector(dx: 0, dy: 4)
        plate.zPosition = 18_500
        plate.setScale(0.5)
        plate.alpha = 0
        parent.addChild(plate)
        let pop = SKAction.scale(to: 1.15, duration: 0.14)
        pop.timingMode = .easeOut
        plate.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), pop]), .scale(to: 1, duration: 0.08), .wait(forDuration: 0.3),
            .group([.scale(to: 0.4, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
        sparks(from: target.center, light: light, count: 8, reach: 36, delay: 0.15, in: parent)
    }

    /// A kite shield's outline, `width` × `height`, its point down.
    private static func kiteShieldPath(width: CGFloat, height: CGFloat) -> CGPath {
        let w = width / 2
        let h = height / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w, y: h * 0.8))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: 0, y: h * 1.2))
        path.addQuadCurve(to: CGPoint(x: 0, y: -h), control: CGPoint(x: w, y: -h * 0.2))
        path.addQuadCurve(to: CGPoint(x: -w, y: h * 0.8), control: CGPoint(x: -w, y: -h * 0.2))
        path.closeSubpath()
        return path
    }

    /// Holy Glow: an orb of rosy light drifts down onto the ally and sinks into them, sparkling.
    private static func holyGlow(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.rose
        let orb = lightBall(light, size: 40, tint: 0.4)
        orb.position = target.center + CGVector(dx: 0, dy: 70)
        orb.alpha = 0
        parent.addChild(orb)
        let descend = SKAction.move(to: target.center, duration: 0.35)
        descend.timingMode = .easeInEaseOut
        orb.run(.sequence([.fadeIn(withDuration: 0.1), descend, .group([.scale(to: 0.2, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        sparkles(on: target, color: light.bright, level: 2, in: parent)
        target.sprite.run(.sequence([
            .wait(forDuration: 0.4),
            .colorize(with: light.main, colorBlendFactor: 0.5, duration: 0.05),
            .colorize(withColorBlendFactor: 0, duration: 0.35),
        ]), withKey: "glow")
    }

    /// Guardianship: a dome of light rises over the whole party and shimmers as it closes.
    private static func guardianWard(over targets: [BattleActor], in parent: SKNode) {
        guard !targets.isEmpty else { return }
        let light = ElementLight.steel
        let xs = targets.map(\.position.x)
        let ys = targets.map(\.position.y)
        let middle = CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2 - 10)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0) + 110
        let height = (ys.max() ?? 0) - (ys.min() ?? 0) + 120
        let dome = CGMutablePath()
        dome.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: false,
                    transform: CGAffineTransform(scaleX: width / 2, y: height))
        let arch = SKShapeNode(path: dome)
        arch.strokeColor = light.bright
        arch.lineWidth = 3
        arch.glowWidth = 6
        arch.fillColor = light.main.withAlphaComponent(0.12)
        arch.blendMode = .add
        arch.position = middle
        arch.zPosition = 18_700
        arch.yScale = 0.05
        arch.alpha = 0
        parent.addChild(arch)
        let rise = SKAction.scaleY(to: 1, duration: 0.25)
        rise.timingMode = .easeOut
        let shimmer = SKAction.sequence([.fadeAlpha(to: 0.5, duration: 0.08), .fadeAlpha(to: 1, duration: 0.08)])
        arch.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), rise]), .wait(forDuration: 0.3),
            .repeat(shimmer, count: 2),
            .fadeOut(withDuration: 0.3), .removeFromParent(),
        ]))
        for target in targets { shield(on: target, in: parent) }
    }

    /// Animal Training: paw prints of amber light race up to the ally, who springs forward with
    /// streaks of speed behind them.
    private static func spur(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.amber
        for index in 0..<4 {
            let step = glowSprite(index % 2 == 0 ? light.main : light.bright, size: CGSize(width: 10, height: 9))
            step.position = target.position + CGVector(dx: -60 + CGFloat(index) * 16, dy: index % 2 == 0 ? -6 : 4)
            step.alpha = 0
            parent.addChild(step)
            step.run(.sequence([
                .wait(forDuration: Double(index) * 0.06), .fadeIn(withDuration: 0.03), .wait(forDuration: 0.2),
                .fadeOut(withDuration: 0.25), .removeFromParent(),
            ]))
        }
        for index in 0..<5 {
            let line = streak(light, size: CGSize(width: 34, height: 3), tint: 0.3)
            line.position = target.center + CGVector(dx: -30, dy: CGFloat(index - 2) * 8)
            line.alpha = 0
            parent.addChild(line)
            line.run(.sequence([
                .wait(forDuration: 0.25 + Double(index) * 0.02), .fadeIn(withDuration: 0.03),
                .group([.moveBy(x: -30, y: 0, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                .removeFromParent(),
            ]))
        }
        target.sprite.run(.sequence([.wait(forDuration: 0.25), .moveBy(x: 0, y: 12, duration: 0.1), .moveBy(x: 0, y: -12, duration: 0.14)]))
    }

    /// Boost: chevrons of orange light shoot up from the fighter's feet as an aura flares round them.
    private static func boostArrows(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.boost
        let aura = lightBall(light, size: 60, tint: 0.35, core: false)
        aura.position = target.center
        aura.alpha = 0
        parent.addChild(aura)
        aura.run(.sequence([.fadeIn(withDuration: 0.1), .wait(forDuration: 0.25), .group([.scale(to: 1.4, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        for index in 0..<4 {
            let chevron = SKShapeNode(path: chevronPath(width: 22, height: 10))
            chevron.strokeColor = index % 2 == 0 ? light.bright : light.main
            chevron.lineWidth = 3
            chevron.glowWidth = 3
            chevron.lineCap = .round
            chevron.lineJoin = .round
            chevron.blendMode = .add
            chevron.position = target.position + CGVector(dx: 0, dy: 4)
            chevron.zPosition = 18_600
            chevron.alpha = 0
            parent.addChild(chevron)
            let rise = SKAction.moveBy(x: 0, y: 60 + CGFloat(index) * 6, duration: 0.45)
            rise.timingMode = .easeOut
            chevron.run(.sequence([
                .wait(forDuration: Double(index) * 0.07), .fadeIn(withDuration: 0.04),
                .group([rise, .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.2)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// An upward chevron, `width` × `height`.
    private static func chevronPath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: -height / 2))
        path.addLine(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: -height / 2))
        return path
    }

    /// Berserk: red flames roar up round the fighter, who flushes red, a shockwave of rage rolls
    /// out at their feet and steam rises off their head.
    private static func rage(on target: BattleActor, in parent: SKNode) {
        let light = ElementLight.rage
        rising(from: target, light: light, count: 10, height: 70, in: parent)
        ring(at: target.position, color: light.main, size: CGSize(width: 40, height: 16), grow: 2.6, in: parent)
        target.sprite.run(.sequence([
            .colorize(with: light.main, colorBlendFactor: 0.7, duration: 0.05), .colorize(withColorBlendFactor: 0, duration: 0.15),
            .colorize(with: light.main, colorBlendFactor: 0.7, duration: 0.05), .colorize(withColorBlendFactor: 0, duration: 0.25),
        ]), withKey: "rage")
        for _ in 0..<4 {
            let steam = shade(UIColor(white: 0.95, alpha: 1), size: CGSize(width: 16, height: 16), alpha: 0.5)
            steam.position = target.top + CGVector(dx: .random(in: -10...10), dy: -6)
            steam.zPosition = 18_500
            parent.addChild(steam)
            steam.run(.sequence([
                .wait(forDuration: .random(in: 0...0.2)),
                .group([.moveBy(x: .random(in: -10...10), y: 26, duration: 0.6), .scale(to: 2, duration: 0.6), .fadeOut(withDuration: 0.6)]),
                .removeFromParent(),
            ]))
        }
    }
}
