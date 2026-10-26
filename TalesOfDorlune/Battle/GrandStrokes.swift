import SpriteKit
import UIKit

/// The top skills' grand strokes (skills.json `grand`), played on top of their own look so the big
/// moves read as big: a crescent of light sweeping through the foes as the blow lands, or a pillar
/// of light falling from the top of the screen onto everyone the skill reaches. Both grow with the
/// skill's tier, the crescent to nearly the screen's width at the top one.
extension SkillEffects {
    /// A crescent of light, a dome-shaped band thickest in the middle and thinning to points, white
    /// to tint: nested bands from wide and faint to narrow and bright, so it glows from a bright edge.
    static let crescentTexture: SKTexture = {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Each band: how far down its outer edge starts, how thick it is in the middle, how bright.
        let bands: [(top: CGFloat, thickness: CGFloat, alpha: CGFloat)] = [(0, 40, 0.2), (6, 28, 0.35), (12, 16, 0.6), (16, 8, 1)]
        let layers = bands.map { band in
            UIGraphicsImageRenderer(size: size, format: format).image { context in
                let canvas = context.cgContext
                let outer = CGRect(x: 8, y: 12 + band.top, width: 240, height: 200)
                canvas.setFillColor(UIColor(white: 1, alpha: band.alpha).cgColor)
                canvas.fillEllipse(in: outer)
                canvas.setBlendMode(.clear)
                canvas.fillEllipse(in: outer.offsetBy(dx: 0, dy: band.thickness))
            }
        }
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for layer in layers { layer.draw(at: .zero) }
        }
        return SKTexture(image: image)
    }()

    /// The light a stroke shines in: its colour, a deeper shade under it and paler ones over it. A
    /// pale blade's light (a sword skill has no colour of its own) is cyan, as a steel sweep's is.
    static func strokeLight(_ color: UIColor) -> ElementLight {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.2 {
            return ElementLight(deep: UIColor(red: 0.12, green: 0.42, blue: 0.95, alpha: 1), main: UIColor(red: 0.45, green: 0.85, blue: 1, alpha: 1),
                                bright: UIColor(red: 0.78, green: 0.96, blue: 1, alpha: 1), core: .white)
        }
        return ElementLight(deep: UIColor(hue: hue, saturation: min(1, saturation + 0.25), brightness: brightness * 0.7, alpha: 1),
                            main: color,
                            bright: UIColor(hue: hue, saturation: saturation * 0.5, brightness: 1, alpha: 1),
                            core: UIColor(hue: hue, saturation: saturation * 0.12, brightness: 1, alpha: 1))
    }

    /// A crescent of light sweeping through `targets` as the blow lands: it swings in tilted, opens
    /// out to its full width and fades as it carries on round, with sparks flying off its edge.
    /// `width`: the screen's, which the top tier nearly spans.
    static func crescent(through targets: [BattleActor], color: UIColor, level: Int, width: CGFloat, in parent: SKNode) {
        guard !targets.isEmpty else { return }
        let light = strokeLight(color)
        // Where they stand on average.
        var sumX: CGFloat = 0, sumY: CGFloat = 0
        for target in targets {
            sumX += target.center.x
            sumY += target.center.y
        }
        let count = CGFloat(targets.count)
        let middle = CGPoint(x: sumX / count, y: sumY / count)
        let across = min(width * 1.05, width * (0.45 + 0.12 * CGFloat(level)))
        let size = CGSize(width: across, height: across / 2)
        let stroke = SKNode()
        stroke.position = middle
        stroke.zPosition = 18_200
        let layers: [(UIColor, CGFloat, SKBlendMode, CGFloat)] = [(light.deep, 1.08, .alpha, 0.5), (light.main, 1, .add, 0.95), (light.core, 0.9, .add, 0.8)]
        for (tint, scale, blend, alpha) in layers {
            let band = SKSpriteNode(texture: crescentTexture, size: size * scale)
            band.color = tint
            band.colorBlendFactor = 1
            band.blendMode = blend
            band.alpha = alpha
            stroke.addChild(band)
        }
        stroke.zRotation = -0.95
        stroke.xScale = 0.35
        stroke.alpha = 0
        parent.addChild(stroke)
        let swing = SKAction.group([.rotate(toAngle: -0.3, duration: 0.14), .scaleX(to: 1, duration: 0.14), .fadeIn(withDuration: 0.05)])
        swing.timingMode = .easeOut
        stroke.run(.sequence([
            swing,
            .group([.rotate(byAngle: 0.18, duration: 0.32), .fadeOut(withDuration: 0.32), .scale(by: 1.06, duration: 0.32)]),
            .removeFromParent(),
        ]))
        sparks(from: middle, light: light, count: 8 + 3 * level, reach: across * 0.45, delay: 0.1, in: parent)
    }

    /// A beam of light, white to tint: soft at the sides, brightest at its foot and fading up.
    static let beamTexture: SKTexture = {
        let size = CGSize(width: 32, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let canvas = context.cgContext
            for row in 0..<Int(size.height) {
                let strength = 0.2 + 0.8 * CGFloat(row) / (size.height - 1)
                let colors = [UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: strength), UIColor(white: 1, alpha: 0)].map(\.cgColor) as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) else { continue }
                canvas.saveGState()
                canvas.clip(to: CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1))
                canvas.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
                canvas.restoreGState()
            }
        }
        return SKTexture(image: image)
    }()

    /// A pillar of light falling from the top of the screen (`top`) onto each of `targets`, a ring
    /// rolling out over the ground as it lands and the ground glowing under it.
    static func skyPillar(on targets: [BattleActor], color: UIColor, level: Int, top: CGFloat, in parent: SKNode) {
        let light = strokeLight(color)
        for target in targets {
            let width = (46 + 10 * CGFloat(level)) * target.fieldScale
            let height = max(40, top + 12 - target.position.y)
            // Hung from the top of the screen and dropped down to the target's feet.
            let pillar = SKNode()
            pillar.position = CGPoint(x: target.position.x, y: top + 12)
            pillar.zPosition = 18_050
            let layers: [(UIColor, CGFloat, SKBlendMode, CGFloat)] = [(light.deep, 1.5, .alpha, 0.45), (light.main, 1, .add, 0.9), (light.core, 0.4, .add, 1)]
            for (index, (tint, scale, blend, alpha)) in layers.enumerated() {
                let beam = SKSpriteNode(texture: beamTexture, size: CGSize(width: width * scale, height: height))
                beam.anchorPoint = CGPoint(x: 0.5, y: 1)
                beam.color = tint
                beam.colorBlendFactor = 1
                beam.blendMode = blend
                beam.alpha = alpha
                beam.zPosition = 0.1 * CGFloat(index)
                pillar.addChild(beam)
            }
            pillar.yScale = 0.02
            parent.addChild(pillar)
            let fall = SKAction.scaleY(to: 1, duration: 0.14)
            fall.timingMode = .easeIn
            pillar.run(.sequence([fall, .wait(forDuration: 0.25),
                                  .group([.scaleX(to: 0.3, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
            ring(at: target.position, color: light.bright, size: CGSize(width: width, height: width * 0.36), grow: 2.4, delay: 0.14, in: parent)
            groundGlow(at: target.position, light: light, width: width * 2, appear: 0.12, hold: 0.3, in: parent)
        }
    }
}
