import SpriteKit

/// Poison and curses (Fairyland Online's dark arts): the spell sinking into its target, the word as it
/// takes hold, and poison's bite at the end of each round; and any stat a spell raises or lowers
/// (a buff, a curse), by how much. The marks by the HP bar are BattleActor's.
extension SkillEffects {
    /// Poison is purple, a curse crimson, so the two never look alike.
    static let poisonPurple = UIColor(red: 0.74, green: 0.42, blue: 1, alpha: 1)
    static let poisonLilac = UIColor(red: 0.88, green: 0.72, blue: 1, alpha: 1)
    static let curseCrimson = UIColor(red: 0.86, green: 0.24, blue: 0.38, alpha: 1)
    static let iceBlue = UIColor(red: 0.62, green: 0.88, blue: 1, alpha: 1)

    /// The colour of an ailment's word, marks and effects.
    static func color(of effect: Ailment) -> UIColor {
        switch effect {
        case .poison: poisonPurple
        case .curse: curseCrimson
        case .freeze: iceBlue
        }
    }

    /// A curse landing: a dark circle under the target and shadow drawn into it.
    static func curseSpell(on target: BattleActor, level: Int, in parent: SKNode) {
        magicCircle(at: target.position, color: curseCrimson, radius: 26 + CGFloat(level) * 3, duration: 0.6, in: parent)
        implode(to: target.center, color: curseCrimson, in: parent)
        target.sprite.flash(curseCrimson)
    }

    /// A poison spell or mist: a sickly cloud welling up round the target, bubbling.
    static func poisonCloud(on target: BattleActor, level: Int, in parent: SKNode) {
        let cloud = glowSprite(poisonPurple, size: CGSize(width: 76, height: 48))
        cloud.position = target.center
        cloud.zPosition = 18_400
        cloud.alpha = 0
        parent.addChild(cloud)
        cloud.run(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.2), .wait(forDuration: 0.3), .fadeOut(withDuration: 0.4), .removeFromParent(),
        ]))
        bubbles(on: target, count: 4 + level * 2, in: parent)
        target.sprite.flash(poisonPurple)
    }

    /// The poison or curse taking hold: its word over the target's head.
    static func afflicted(_ target: BattleActor, effect: Ailment, in parent: SKNode) {
        let tint = color(of: effect)
        switch effect {
        case .poison: bubbles(on: target, count: 5, in: parent)
        case .curse: implode(to: target.center, color: tint, in: parent)
        case .freeze: frostCrackle(on: target, in: parent)
        }
        let word = switch effect {
        case .poison: L("Poisoned!")
        case .curse: L("Cursed!")
        case .freeze: L("Frozen!")
        }
        Effects.floatingText(word, color: tint, at: target.top + CGVector(dx: 0, dy: 10), in: parent, size: 14)
    }

    /// Ice closing round a fighter: a pale flash and splinters of frost glinting outward.
    static func frostCrackle(on target: BattleActor, in parent: SKNode) {
        target.sprite.flash(iceBlue)
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * 2 * .pi
            let glint = glowSprite(index % 2 == 0 ? .white : iceBlue, size: CGSize(width: 12, height: 3.5))
            glint.position = target.center
            glint.zRotation = angle
            glint.zPosition = 18_400
            parent.addChild(glint)
            let out = SKAction.moveBy(x: cos(angle) * 26, y: sin(angle) * 20, duration: 0.3)
            out.timingMode = .easeOut
            glint.run(.sequence([.group([out, .sequence([.wait(forDuration: 0.1), .fadeOut(withDuration: 0.2)])]), .removeFromParent()]))
        }
    }

    /// A frozen fighter's turn passing by: it shivers in place inside the ice.
    static func frozenShiver(on target: BattleActor, in parent: SKNode) {
        target.sprite.flash(iceBlue)
        target.run(.sequence([
            .moveBy(x: 2, y: 0, duration: 0.04), .moveBy(x: -4, y: 0, duration: 0.06),
            .moveBy(x: 4, y: 0, duration: 0.06), .moveBy(x: -2, y: 0, duration: 0.04),
        ]), withKey: "shudder")
        Effects.floatingText(L("Frozen!"), color: iceBlue, at: target.top + CGVector(dx: 0, dy: 10), in: parent, size: 14)
    }

    /// Poison's bite at the end of a round: the target shudders purple and bubbles rise off it.
    static func poisonBite(on target: BattleActor, in parent: SKNode) {
        target.sprite.flash(poisonPurple)
        bubbles(on: target, count: 4, in: parent)
        target.run(.sequence([
            .moveBy(x: 3, y: 0, duration: 0.05), .moveBy(x: -6, y: 0, duration: 0.08), .moveBy(x: 3, y: 0, duration: 0.05),
        ]), withKey: "shudder")
    }

    /// Raised stats: the blue of the up-arrow mark by the HP bar.
    static let raiseBlue = UIColor(red: 0.45, green: 0.8, blue: 1, alpha: 1)
    /// Lowered stats: the curse's crimson, lighter so it reads on the field.
    static let lowerRose = UIColor(red: 1, green: 0.55, blue: 0.62, alpha: 1)

    /// Stats raised or lowered: each by name and by how much over the fighter's head ("ATK +25%"
    /// in blue, "DEF −20%" in rose), held long enough to read, with motes of light rising off
    /// them for a raise and sinking for a drop.
    static func statChanges(_ changes: [StatChange], on target: BattleActor, in parent: SKNode) {
        guard !changes.isEmpty else { return }
        for (index, change) in changes.enumerated() {
            let line = NameTag("\(change.stat.short) \(BattleController.percent(change.amount))",
                               color: change.amount > 0 ? raiseBlue : lowerRose, size: 14, alignment: .center)
            line.position = target.top + CGVector(dx: 0, dy: 30 + CGFloat(index) * 17)
            line.zPosition = 21_500
            line.setScale(0.4)
            line.alpha = 0
            parent.addChild(line)
            line.run(.sequence([
                .wait(forDuration: Double(index) * 0.08),
                .group([.fadeIn(withDuration: 0.1), .scale(to: 1.1, duration: 0.14)]),
                .scale(to: 1, duration: 0.08),
                .wait(forDuration: 0.9),
                .group([.moveBy(x: 0, y: 14, duration: 0.35), .fadeOut(withDuration: 0.35)]),
                .removeFromParent(),
            ]))
        }
        let up = changes.contains { $0.amount > 0 }
        let tint = up ? raiseBlue : lowerRose
        target.sprite.flash(tint)
        for index in 0..<8 {
            let mote = glowSprite(tint, size: CGSize(width: 7, height: 7))
            let start: CGFloat = up ? .random(in: 0...12) : target.height * .random(in: 0.6...0.9)
            mote.position = target.position + CGVector(dx: .random(in: -20...20), dy: start)
            mote.alpha = 0
            parent.addChild(mote)
            let drift = SKAction.moveBy(x: 0, y: up ? 40 : -34, duration: 0.6)
            drift.timingMode = .easeOut
            mote.run(.sequence([
                .wait(forDuration: Double(index) * 0.04),
                .fadeIn(withDuration: 0.06),
                .group([drift, .scale(to: 0.4, duration: 0.6), .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.3)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// Little purple (and now and then lilac) bubbles rising off a fighter and popping.
    private static func bubbles(on target: BattleActor, count: Int, in parent: SKNode) {
        let texture = fxTexture("bubble")
        for index in 0..<count {
            let tint = index % 3 == 2 ? poisonLilac : poisonPurple
            let bubble: SKSpriteNode
            if let texture {
                bubble = SKSpriteNode(texture: texture, size: texture.size() * CGFloat.random(in: 1.4...2.2))
                bubble.color = tint
                bubble.colorBlendFactor = 1
            } else {
                bubble = glowSprite(tint, size: CGSize(width: 10, height: 10))
            }
            bubble.position = target.position + CGVector(dx: .random(in: -18...18), dy: .random(in: 4...max(6, target.height * 0.6)))
            bubble.zPosition = 18_500
            bubble.alpha = 0
            parent.addChild(bubble)
            let rise = SKAction.moveBy(x: .random(in: -6...6), y: .random(in: 22...40), duration: 0.7)
            rise.timingMode = .easeOut
            bubble.run(.sequence([
                .wait(forDuration: Double(index) * 0.05),
                .group([
                    .fadeIn(withDuration: 0.1), rise,
                    .sequence([.wait(forDuration: 0.45), .group([.scale(to: 1.5, duration: 0.15), .fadeOut(withDuration: 0.15)])]),
                ]),
                .removeFromParent(),
            ]))
        }
    }
}
