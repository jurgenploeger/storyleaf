import SpriteKit
import UIKit
import SwiftUI

/// Small reusable SpriteKit building blocks.
enum Nodes {
    static let ink = UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
    static let gold = UIColor(red: 1, green: 0.83, blue: 0.3, alpha: 1)
    /// Fairyland Online's yellow name tags.
    static let nameYellow = UIColor(red: 1, green: 0.95, blue: 0.35, alpha: 1)

    /// A cream speech bubble with a little tail, anchored at the tail's tip.
    static func speechBubble(_ text: String, maxWidth: CGFloat = 150) -> SKSpriteNode {
        let base = UIFont.systemFont(ofSize: 11, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 11) } ?? base
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph])
        let textBox = string.boundingRect(with: CGSize(width: maxWidth, height: 200), options: [.usesLineFragmentOrigin], context: nil).integral
        let padding = CGSize(width: 9, height: 5)
        let tail: CGFloat = 6
        let bubble = CGRect(x: 1, y: 1, width: textBox.width + padding.width * 2, height: textBox.height + padding.height * 2)
        let canvas = CGSize(width: bubble.width + 2, height: bubble.height + tail + 2)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            // One outline, clockwise from the top-left, that dips into the tail along the bottom
            // edge: the tail is part of the bubble, with no line drawn across where it joins.
            let radius = min(10, bubble.height / 2)
            // The tail's base stays on the straight bit of the bottom edge, however short the line.
            let half = max(2, min(5, bubble.width / 2 - radius))
            let shape = UIBezierPath()
            shape.move(to: CGPoint(x: bubble.minX + radius, y: bubble.minY))
            shape.addLine(to: CGPoint(x: bubble.maxX - radius, y: bubble.minY))
            shape.addArc(withCenter: CGPoint(x: bubble.maxX - radius, y: bubble.minY + radius), radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
            shape.addLine(to: CGPoint(x: bubble.maxX, y: bubble.maxY - radius))
            shape.addArc(withCenter: CGPoint(x: bubble.maxX - radius, y: bubble.maxY - radius), radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: true)
            shape.addLine(to: CGPoint(x: bubble.midX + half, y: bubble.maxY))
            shape.addLine(to: CGPoint(x: bubble.midX, y: bubble.maxY + tail))
            shape.addLine(to: CGPoint(x: bubble.midX - half, y: bubble.maxY))
            shape.addLine(to: CGPoint(x: bubble.minX + radius, y: bubble.maxY))
            shape.addArc(withCenter: CGPoint(x: bubble.minX + radius, y: bubble.maxY - radius), radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
            shape.addLine(to: CGPoint(x: bubble.minX, y: bubble.minY + radius))
            shape.addArc(withCenter: CGPoint(x: bubble.minX + radius, y: bubble.minY + radius), radius: radius, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
            shape.close()
            shape.lineJoinStyle = .round
            UIColor(red: 1, green: 0.98, blue: 0.9, alpha: 0.96).setFill()
            shape.fill()
            ink.withAlphaComponent(0.8).setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
            string.draw(with: CGRect(x: bubble.minX + padding.width, y: bubble.minY + padding.height, width: textBox.width, height: textBox.height),
                        options: [.usesLineFragmentOrigin], context: nil)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, size: image.size)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

    /// A market trader's sign: a little wooden board over their head with something they sell.
    static func shopSign(_ text: String) -> SKSpriteNode {
        let base = UIFont.systemFont(ofSize: 10, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? base
        let wood = UIColor(red: 0.42, green: 0.25, blue: 0.1, alpha: 1)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: wood])
        let fit = string.size()
        let board = CGRect(x: 1, y: 1, width: ceil(fit.width) + 14, height: ceil(fit.height) + 6)
        let canvas = CGSize(width: board.width + 2, height: board.height + 2)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let shape = UIBezierPath(roundedRect: board, cornerRadius: 3)
            UIColor(red: 0.95, green: 0.8, blue: 0.52, alpha: 0.97).setFill()
            shape.fill()
            wood.setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
            // Two nail heads, so it reads as a board.
            wood.setFill()
            for x in [board.minX + 3.5, board.maxX - 3.5] {
                UIBezierPath(ovalIn: CGRect(x: x - 1, y: board.midY - 1, width: 2, height: 2)).fill()
            }
            string.draw(at: CGPoint(x: board.minX + 7, y: board.minY + 3))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, size: image.size)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        return node
    }

    static func outlined(_ text: String, size: CGFloat, color: UIColor, monospaced: Bool = false) -> NSAttributedString {
        let base = monospaced ? UIFont.monospacedSystemFont(ofSize: size, weight: .bold) : UIFont.systemFont(ofSize: size, weight: .heavy)
        let font = monospaced ? base : (base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .strokeColor: ink,
            .strokeWidth: -4,
        ])
    }
}

/// How a creature fidgets while standing still (content/monsters.json `motion`); people breathe.
enum IdleMotion: String {
    case breathe, squish, hop, sway, bounce

    static func of(art: String) -> IdleMotion {
        Content.shared.monsters.first { $0.art == art }?.motion.flatMap(IdleMotion.init) ?? .breathe
    }

    /// A looping action for a sprite anchored at its feet, `height` points tall.
    func action(height: CGFloat, delay: TimeInterval) -> SKAction {
        func ease(_ action: SKAction, _ mode: SKActionTimingMode = .easeInEaseOut) -> SKAction {
            action.timingMode = mode
            return action
        }
        func scale(x: CGFloat, y: CGFloat, _ duration: TimeInterval) -> SKAction {
            .group([ease(.scaleX(to: x, duration: duration)), ease(.scaleY(to: y, duration: duration))])
        }
        let jump = max(4, height * 0.14)
        let loop: SKAction = switch self {
        case .breathe:
            .sequence([
                .group([scale(x: 0.98, y: 1.05, 0.9), ease(.moveBy(x: 0, y: 1, duration: 0.9))]),
                .group([scale(x: 1, y: 1, 0.9), ease(.moveBy(x: 0, y: -1, duration: 0.9))]),
            ])
        case .squish:
            .sequence([scale(x: 1.1, y: 0.86, 0.35), scale(x: 0.96, y: 1.06, 0.3), scale(x: 1, y: 1, 0.25), .wait(forDuration: 0.35)])
        case .hop:
            .sequence([
                .wait(forDuration: 0.9, withRange: 0.8),
                scale(x: 1.06, y: 0.9, 0.08),
                .group([ease(.moveBy(x: 0, y: jump, duration: 0.16), .easeOut), scale(x: 0.96, y: 1.08, 0.16)]),
                .group([ease(.moveBy(x: 0, y: -jump, duration: 0.14), .easeIn), scale(x: 1, y: 1, 0.14)]),
                scale(x: 1.06, y: 0.92, 0.06), scale(x: 1, y: 1, 0.08),
            ])
        case .sway:
            .sequence([ease(.rotate(toAngle: 0.08, duration: 0.8)), ease(.rotate(toAngle: -0.08, duration: 1.6)), ease(.rotate(toAngle: 0, duration: 0.8))])
        case .bounce:
            .sequence([
                .group([ease(.moveBy(x: 0, y: jump * 0.6, duration: 0.24), .easeOut), scale(x: 0.97, y: 1.05, 0.24)]),
                .group([ease(.moveBy(x: 0, y: -jump * 0.6, duration: 0.22), .easeIn), scale(x: 1, y: 1, 0.22)]),
                scale(x: 1.08, y: 0.9, 0.06), scale(x: 1, y: 1, 0.08),
            ])
        }
        return .sequence([.wait(forDuration: delay), .repeatForever(loop)])
    }
}

/// A name tag like Fairyland Online's: yellow text with a solid dark outline, an optional "[Lv.3]"
/// prefix in cream, and an optional pill after the name (BOT for computer-run adventurers). Drawn
/// into a crisp texture (outline first, then the letters on top) so the outline
/// grows outward instead of eating into small text.
final class NameTag: SKNode {
    private let sprite = SKSpriteNode()
    private var color: UIColor
    private let size: CGFloat
    /// What's drawn now, so setting the same text again skips re-rendering the texture.
    private var shown: String?
    private var label: String
    private var level: Int?
    private var badge: PlayerBadge?

    init(_ text: String, level: Int? = nil, color: UIColor = Nodes.nameYellow, size: CGFloat = 12,
         alignment: SKLabelVerticalAlignmentMode = .bottom, badge: PlayerBadge? = nil) {
        self.color = color
        self.size = size
        label = text
        self.level = level
        self.badge = badge
        super.init()
        zPosition = 5_000
        sprite.anchorPoint = CGPoint(x: 0.5, y: alignment == .top ? 1 : alignment == .center ? 0.5 : 0)
        addChild(sprite)
        redraw()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setText(_ text: String, level: Int? = nil) {
        label = text
        self.level = level
        redraw()
    }

    func setBadge(_ badge: PlayerBadge?) {
        self.badge = badge
        redraw()
    }

    /// The name in another colour (gold, at the top level).
    func setColor(_ color: UIColor) {
        self.color = color
        redraw()
    }

    private func redraw() {
        let key = "\(level.map(String.init) ?? "")|\(label)|\(badge?.rawValue ?? "")|\(color.description)"
        guard key != shown else { return }
        shown = key
        let image = Self.render(prefix: level.map { L("[Lv.{level}] ", ["level": $0]) } ?? "", text: label, color: color, size: size, badge: badge)
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        sprite.texture = texture
        sprite.size = image.size
    }

    private static func render(prefix: String, text: String, color: UIColor, size: CGFloat, badge: PlayerBadge?) -> UIImage {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        let letters = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: UIColor(red: 1, green: 0.97, blue: 0.86, alpha: 1)])
        letters.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        // A positive strokeWidth draws only the outline, centred on the glyph edge; the
        // letters drawn on top hide the inner half.
        let outline = NSAttributedString(string: prefix + text, attributes: [
            .font: font, .strokeColor: Nodes.ink, .strokeWidth: 34,
        ])
        let pad = ceil(size * 0.25)
        let textSize = letters.size()
        // The pill after the name, with as much room left before the name so it stays centred.
        let tag = badge.map { NSAttributedString(string: $0.title, attributes: [
            .font: UIFont.systemFont(ofSize: max(7, size * 0.6), weight: .black), .foregroundColor: UIColor.white,
        ]) }
        let tagSize = tag?.size() ?? .zero
        let pill = tag == nil ? CGSize.zero : CGSize(width: ceil(tagSize.width) + size * 0.7, height: ceil(tagSize.height) + size * 0.15)
        let side = tag == nil ? 0 : pill.width + size * 0.3
        let canvas = CGSize(width: ceil(textSize.width) + side * 2 + pad * 2,
                            height: max(ceil(textSize.height), pill.height) + pad * 2)
        return UIGraphicsImageRenderer(size: canvas).image { context in
            let origin = CGPoint(x: pad + side, y: (canvas.height - ceil(textSize.height)) / 2)
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 1.5, color: UIColor(white: 0, alpha: 0.45).cgColor)
            outline.draw(at: origin)
            context.cgContext.setShadow(offset: .zero, blur: 0)
            letters.draw(at: origin)
            if let badge, let tag {
                let box = CGRect(x: origin.x + ceil(textSize.width) + size * 0.3, y: (canvas.height - pill.height) / 2,
                                 width: pill.width, height: pill.height)
                let shape = UIBezierPath(roundedRect: box, cornerRadius: pill.height / 2)
                badge.uiColor.setFill()
                shape.fill()
                Nodes.ink.setStroke()
                shape.lineWidth = 1
                shape.stroke()
                tag.draw(at: CGPoint(x: box.midX - tagSize.width / 2, y: box.midY - tagSize.height / 2))
            }
        }
    }
}

final class HealthBar: SKNode {
    private let fill: SKSpriteNode
    private var manaFill: SKSpriteNode?
    private let width: CGFloat

    var fraction: CGFloat = 1 {
        didSet {
            fill.size.width = max(0, width * min(fraction, 1))
        }
    }

    var manaFraction: CGFloat = 1 {
        didSet { manaFill?.size.width = max(0, width * min(manaFraction, 1)) }
    }

    /// With a `level`, a small "Lv12" badge caps the bar's left end, so one compact plate shows both.
    /// With `mana`, a thin MP bar hangs under the HP bar.
    init(width: CGFloat, level: Int? = nil, mana: Bool = false) {
        self.width = width
        let thick: CGFloat = level == nil ? 3 : 4
        // HP is red everywhere (HUDStyle.hp), MP blue.
        fill = SKSpriteNode(color: UIColor(red: 0.93, green: 0.22, blue: 0.2, alpha: 1), size: CGSize(width: width, height: thick))
        super.init()
        var parts: [SKNode] = []
        let background = SKSpriteNode(color: UIColor(white: 0, alpha: 0.6), size: CGSize(width: width + 2, height: thick + 2))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position.x = -width / 2
        fill.zPosition = 1
        parts += [background, fill]
        // The MP bar's middle, under the HP bar's frame.
        let manaY = -(thick + 2) / 2 - 3
        if mana {
            let y = manaY
            let back = SKSpriteNode(color: UIColor(white: 0, alpha: 0.6), size: CGSize(width: width + 2, height: 5))
            back.position.y = y
            let blue = SKSpriteNode(color: UIColor(red: 0.24, green: 0.52, blue: 0.95, alpha: 1), size: CGSize(width: width, height: 3))
            blue.anchorPoint = CGPoint(x: 0, y: 0.5)
            blue.position = CGPoint(x: -width / 2, y: y)
            blue.zPosition = 1
            manaFill = blue
            parts += [back, blue]
        }
        for part in parts { addChild(part) }
        if let level {
            let texture = SKTexture(image: Self.badge(level))
            let badge = SKSpriteNode(texture: texture)
            // Tucked over the bars' left end; everything shifts so the whole plate stays centred.
            let overlap: CGFloat = 3
            let shift = (badge.size.width - overlap) / 2
            badge.position.x = -width / 2 - badge.size.width / 2 + overlap + shift
            // Centred on the bars together: from the HP frame's top to the MP bar's bottom (to the
            // nearest point, so the chip stays crisp).
            let top = (thick + 2) / 2
            let bottom = mana ? manaY - 2.5 : -top
            badge.position.y = ((top + bottom) / 2).rounded()
            badge.zPosition = 2
            addChild(badge)
            parts.forEach { $0.position.x += shift }
        }
        zPosition = 5_000
        fraction = 1
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// "Lv12" in cream on a dark rounded chip with a thin cream rim.
    private static func badge(_ level: Int) -> UIImage {
        let base = UIFont.systemFont(ofSize: 8.5, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 8.5) } ?? base
        let cream = UIColor(red: 1, green: 0.97, blue: 0.86, alpha: 1)
        let text = NSAttributedString(string: L("Lv{level}", ["level": level]), attributes: [.font: font, .foregroundColor: cream])
        let textSize = text.size()
        let canvas = CGSize(width: ceil(textSize.width) + 8, height: 12)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            let chip = UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
            Nodes.ink.withAlphaComponent(0.9).setFill()
            chip.fill()
            cream.withAlphaComponent(0.7).setStroke()
            chip.lineWidth = 1
            chip.stroke()
            text.draw(at: CGPoint(x: (canvas.width - textSize.width) / 2, y: (canvas.height - textSize.height) / 2))
        }
    }
}

extension SKSpriteNode {
    /// A quick hop toward `offset` and back, for attacks.
    func lunge(toward offset: CGVector) {
        let step = offset.normalized * 5
        run(.sequence([
            .moveBy(x: step.dx, y: step.dy, duration: 0.06),
            .moveBy(x: -step.dx, y: -step.dy, duration: 0.1),
        ]))
    }

    func flash(_ color: UIColor) {
        run(.sequence([
            .colorize(with: color, colorBlendFactor: 0.8, duration: 0.04),
            .colorize(withColorBlendFactor: 0, duration: 0.15),
        ]))
    }
}

/// Fire-and-forget visual effects; every node removes itself when done.
enum Effects {
    static func floatingText(_ text: String, color: UIColor, at point: CGPoint, in parent: SKNode, size: CGFloat = 12) {
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: size, color: color)
        label.verticalAlignmentMode = .bottom
        label.position = point
        label.zPosition = 10_000
        parent.addChild(label)
        let rise = SKAction.moveBy(x: 0, y: 26, duration: 0.9)
        rise.timingMode = .easeOut
        label.run(.sequence([
            .group([rise, .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent(),
        ]))
    }

    /// How a hit looks: an ordinary blow, a critical, a splash on a neighbour, a heal, or poison's bite.
    enum BurstStyle {
        case normal, critical, heal, splash, poison
    }

    /// A hit lands: a fireball blooms where it struck (hot white core, orange flame, flying embers,
    /// a wisp of smoke) and the number pops out above it. Heals get a soft green glow instead.
    static func damageBurst(_ text: String, style: BurstStyle, at point: CGPoint, in parent: SKNode) {
        let impact = point + CGVector(dx: .random(in: -6...6), dy: -14)
        switch style {
        case .heal: healGlow(at: impact, in: parent)
        case .poison: healGlow(at: impact, in: parent, texture: poisonGlow)
        case .normal: fireball(at: impact, in: parent, power: 1)
        case .critical: fireball(at: impact, in: parent, power: 1.6)
        case .splash: fireball(at: impact, in: parent, power: 0.6)
        }
        hitNumber(text, style: style, at: impact + CGVector(dx: 0, dy: 16), in: parent)
    }

    private static let fireCore = SoftTextures.radial(size: 64, colors: [
        .white, UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), UIColor(red: 1, green: 0.75, blue: 0.25, alpha: 0.9),
        UIColor(red: 1, green: 0.4, blue: 0.1, alpha: 0.5), UIColor(red: 0.9, green: 0.2, blue: 0.05, alpha: 0),
    ])
    private static let flame = SoftTextures.radial(size: 32, colors: [
        UIColor(red: 1, green: 0.9, blue: 0.55, alpha: 1), UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 0.85),
        UIColor(red: 0.85, green: 0.2, blue: 0.05, alpha: 0),
    ])
    private static let smoke = SoftTextures.radial(size: 48, colors: [
        UIColor(white: 0.35, alpha: 0.55), UIColor(white: 0.3, alpha: 0.3), UIColor(white: 0.25, alpha: 0),
    ])
    private static let greenGlow = SoftTextures.radial(size: 64, colors: [
        UIColor(red: 0.9, green: 1, blue: 0.9, alpha: 1), UIColor(red: 0.45, green: 0.95, blue: 0.5, alpha: 0.7),
        UIColor(red: 0.2, green: 0.8, blue: 0.35, alpha: 0),
    ])
    /// Pale lilac deepening to poison's purple.
    private static let poisonGlow = SoftTextures.radial(size: 64, colors: [
        UIColor(red: 0.93, green: 0.82, blue: 1, alpha: 1), UIColor(red: 0.7, green: 0.38, blue: 0.98, alpha: 0.7),
        UIColor(red: 0.4, green: 0.15, blue: 0.62, alpha: 0),
    ])

    private static func fireball(at point: CGPoint, in parent: SKNode, power: CGFloat) {
        // Smoke first, so the fire draws over it.
        for _ in 0..<Int(3 * power + 1) {
            let puff = SKSpriteNode(texture: smoke, size: CGSize(width: 34, height: 34) * power)
            puff.position = point + CGVector(dx: CGFloat.random(in: -10...10) * power, dy: .random(in: -4...6))
            puff.zPosition = 20_500
            puff.alpha = 0
            puff.setScale(0.6)
            parent.addChild(puff)
            let drift = SKAction.moveBy(x: .random(in: -10...10), y: CGFloat.random(in: 18...34) * power, duration: 0.9)
            drift.timingMode = .easeOut
            puff.run(.sequence([.wait(forDuration: 0.08), .group([drift, .scale(to: 1.5, duration: 0.9),
                .sequence([.fadeAlpha(to: 0.8, duration: 0.12), .fadeOut(withDuration: 0.75)])]), .removeFromParent()]))
        }
        // The bloom: a hot core that swells and burns out.
        let core = SKSpriteNode(texture: fireCore, size: CGSize(width: 70, height: 70) * power)
        core.position = point
        core.zPosition = 20_600
        core.blendMode = .add
        core.setScale(0.25)
        parent.addChild(core)
        let swell = SKAction.scale(to: 1.15, duration: 0.14)
        swell.timingMode = .easeOut
        core.run(.sequence([swell, .group([.scale(to: 1.35, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        // Tongues of flame thrown outward.
        let tongues = Int(8 * power)
        for index in 0..<tongues {
            let angle = CGFloat(index) / CGFloat(tongues) * 2 * .pi + .random(in: -0.3...0.3)
            let reach = CGFloat.random(in: 18...34) * power
            let bit = SKSpriteNode(texture: flame, size: CGSize(width: 22, height: 22) * CGFloat.random(in: 0.7...1.2) * power)
            bit.position = point
            bit.zPosition = 20_650
            bit.blendMode = .add
            parent.addChild(bit)
            let fly = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach * 0.75 + 6, duration: 0.32)
            fly.timingMode = .easeOut
            bit.run(.sequence([.group([fly, .scale(to: 0.3, duration: 0.32), .fadeOut(withDuration: 0.32)]), .removeFromParent()]))
        }
        // Embers: tiny sparks that arc out and fall.
        for _ in 0..<Int(6 * power) {
            let ember = SKSpriteNode(color: UIColor(red: 1, green: .random(in: 0.6...0.9), blue: 0.3, alpha: 1), size: CGSize(width: 2.5, height: 2.5))
            ember.position = point
            ember.zPosition = 20_700
            ember.blendMode = .add
            parent.addChild(ember)
            let dx = CGFloat.random(in: -40...40) * power
            let up = SKAction.moveBy(x: dx * 0.6, y: CGFloat.random(in: 14...30) * power, duration: 0.25)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: dx * 0.4, y: -CGFloat.random(in: 18...30), duration: 0.35)
            down.timingMode = .easeIn
            ember.run(.sequence([up, .group([down, .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
    }

    private static func healGlow(at point: CGPoint, in parent: SKNode, texture: SKTexture? = nil) {
        let glow = SKSpriteNode(texture: texture ?? greenGlow, size: CGSize(width: 60, height: 60))
        glow.position = point
        glow.zPosition = 20_600
        glow.blendMode = .add
        glow.setScale(0.4)
        parent.addChild(glow)
        glow.run(.sequence([.group([.scale(to: 1.2, duration: 0.35), .sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.35)])]), .removeFromParent()]))
    }

    /// The number itself: bold, outlined, popping up and drifting away.
    private static func hitNumber(_ text: String, style: BurstStyle, at point: CGPoint, in parent: SKNode) {
        let color: UIColor = switch style {
        case .normal: UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 1)
        case .critical: UIColor(red: 1, green: 0.62, blue: 0.2, alpha: 1)
        case .heal: UIColor(red: 0.6, green: 1, blue: 0.62, alpha: 1)
        case .splash: UIColor(red: 0.88, green: 0.88, blue: 0.95, alpha: 1)
        case .poison: UIColor(red: 0.86, green: 0.66, blue: 1, alpha: 1)
        }
        let size: CGFloat = switch style {
        case .critical: 30
        case .splash: 17
        default: 23
        }
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: size, color: color)
        label.verticalAlignmentMode = .center
        label.position = point
        label.zPosition = 21_000
        label.setScale(0.3)
        parent.addChild(label)
        let pop = SKAction.sequence([.scale(to: style == .critical ? 1.3 : 1.15, duration: 0.09), .scale(to: 1, duration: 0.08)])
        let rise = SKAction.moveBy(x: .random(in: -6...6), y: 26, duration: 0.6)
        rise.timingMode = .easeOut
        label.run(.sequence([pop, .wait(forDuration: 0.3), .group([rise, .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
    }

    static func damageNumber(_ text: String, color: UIColor, at point: CGPoint, in parent: SKNode, big: Bool) {
        let label = SKLabelNode()
        label.attributedText = Nodes.outlined(text, size: big ? 26 : 20, color: color)
        label.verticalAlignmentMode = .bottom
        label.position = point
        label.zPosition = 21_000
        label.setScale(0.3)
        parent.addChild(label)
        let pop = SKAction.sequence([.scale(to: 1.35, duration: 0.1), .scale(to: 1, duration: 0.1)])
        let rise = SKAction.moveBy(x: .random(in: -8...8), y: 34, duration: 0.8)
        rise.timingMode = .easeOut
        label.run(.sequence([pop, .group([rise, .sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.35)])]), .removeFromParent()]))
    }

    static let tapMarkerName = "tapMarker"
    /// How deep the swirl sorts: over everyone and everything that stands, whose depth is their
    /// place up the screen (`-y`, within ±15,000 points on the continent), and their name
    /// tags; under the lights, the weather and the night's shade (`Lighting`, `Sky`). Under all
    /// that stands, it was hidden behind whatever stood in front of where you tapped: a tree, a
    /// house, your party (playtesting 2026-10-16).
    static let tapMarkerZ: CGFloat = 21_000

    /// Fairyland Online's destination marker: a swirl on the ground, in Storyleaf's colours and drawn
    /// like the logo's letters: a pale leaf-green line over a forest-green outline. On every
    /// map one of the two stands out: the outline on sand, snow and candy, the line on grass,
    /// caves and dark woods. Over everything that stands (`tapMarkerZ`).
    static func tapMarker(at point: CGPoint, z: CGFloat = Effects.tapMarkerZ, in parent: SKNode) {
        let marker = SKNode()
        marker.name = tapMarkerName
        marker.position = point
        marker.zPosition = z
        parent.addChild(marker)

        let spiral = CGMutablePath()
        for step in 0...60 {
            let t = CGFloat(step) / 60 * 2.5 * 2 * .pi
            let radius = 1 + t * 1.1
            let p = CGPoint(x: cos(t) * radius, y: sin(t) * radius * 0.6 + 10)
            step == 0 ? spiral.move(to: p) : spiral.addLine(to: p)
        }
        let swirl = SKNode()
        for (color, width) in [(UIColor(Brand.forest), CGFloat(5.5)), (UIColor(Brand.leafLight), CGFloat(2.5))] {
            let line = SKShapeNode(path: spiral)
            line.strokeColor = color
            line.lineWidth = width
            line.lineCap = .round
            line.lineJoin = .round
            line.isAntialiased = true
            swirl.addChild(line)
        }
        marker.addChild(swirl)
        swirl.run(.repeat(.sequence([.scale(to: 1.15, duration: 0.2), .scale(to: 1, duration: 0.2)]), count: 2))
        marker.run(.sequence([.wait(forDuration: 0.8), .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    static func burst(at point: CGPoint, color: UIColor, count: Int = 10, in parent: SKNode) {
        for index in 0..<count {
            let bit = SKSpriteNode(color: color, size: CGSize(width: 3, height: 3))
            bit.position = point
            bit.zPosition = 9_000
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            let distance = CGFloat.random(in: 16...30)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.45)
            move.timingMode = .easeOut
            parent.addChild(bit)
            bit.run(.sequence([.group([move, .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        }
    }
}
